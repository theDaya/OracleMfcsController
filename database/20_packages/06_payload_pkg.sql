set define off

-- Reads the Office document and builds each MFCS request payload.
--
-- The whole MFCS write contract in one place: every request body the
-- orchestrator sends is built here, from the stored Office document plus
-- CONFIG defaults. orchestrator_pkg calls build_request
-- statically, so a missing mapper is a compile error, not a runtime surprise.
--
-- MFCS's read and write vocabularies disagree (the order feed says
-- physicalQuantityOrdered / originCountryId where the write wants
-- quantityOrdered / originCountry); the mappers here speak the write
-- vocabulary only.

prompt Creating payload_pkg

create or replace package payload_pkg authid definer as
    function build_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob;

    -- Readers for the stored Office request document. These moved here from
    -- mapping_pkg, which existed only to switch between the mock and
    -- real mappers and became a forwarding layer once the simulators were removed.
    function source_system(p_payload in clob) return varchar2;
    function source_style_ref(p_payload in clob) return varchar2;
    function source_order_ref(p_payload in clob) return varchar2;
    function user_id(p_payload in clob) return varchar2;
    function request_payload(p_action_request_id in varchar2) return clob;

    -- Exposed so the orchestrator can read one request field without a second
    -- JSON-reading implementation.
    function string_value(p_payload in clob, p_name in varchar2) return varchar2;

    -- A delivery location as the virtual warehouse MFCS wants, derived from the
    -- tenant's warehouse feed. Public because the order-line planner needs the
    -- same answer the order mapper gets.
    function virtual_location(p_location in varchar2) return varchar2;

    -- One row of the inbound document's SIZE_CURVE_DETAIL array. Every reader of
    -- the size curve - here and in the orchestrator - sees this shape; the
    -- json_table projection behind it is defined once (c_size_curve, in the
    -- body), so a column added to the curve lands in exactly one place.
    type t_size_curve_row is record (
        rn                 pls_integer,
        source_variant_ref varchar2(120),
        sku_size           varchar2(60),
        sku_width          varchar2(60),
        sku_id             varchar2(30),
        sku_qty            number
    );
    type t_size_curve is table of t_size_curve_row index by pls_integer;

    -- The single definition of the size-curve projection, public so the
    -- orchestrator loops the same cursor instead of keeping a copy. Ten
    -- readers used to carry their own json_table of this array; a column
    -- added to the curve is now added here and nowhere else.
    cursor c_size_curve(cp_payload clob) is
        select rn, source_variant_ref, sku_size, sku_width, sku_id, sku_qty
          from json_table(cp_payload, '$.SIZE_CURVE_DETAIL[*]'
              columns
                  rn                 for ordinality,
                  source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                  sku_size           varchar2(60)  path '$.SKU_SIZE',
                  sku_width          varchar2(60)  path '$.SKU_WIDTH',
                  sku_id             varchar2(30)  path '$.SKU_ID',
                  sku_qty            number        path '$.SKU_QTY'
          );

    -- Barcodes hang off a size-curve row, so they cannot ride in c_size_curve
    -- without multiplying it: a SKU with two barcodes would become two SKUs.
    -- They get their own projection, carrying the parent row's identity down so
    -- the reference-item builder can resolve which SKU each barcode belongs to.
    --
    -- The where clause is not a nicety. json_table's nested path is an outer
    -- join: a size-curve row with no SKU_UPCS still produces one row, with every
    -- nested column null. Without the filter a SKU without barcodes would build a
    -- level-3 item whose item number is null and send it to the tenant.
    cursor c_sku_upcs(cp_payload clob) is
        select rn, source_variant_ref, sku_id, sku_size, sku_width,
               upc_rn, upc, upc_type, primary_yn
          from json_table(cp_payload, '$.SIZE_CURVE_DETAIL[*]'
              columns
                  rn                 for ordinality,
                  source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                  sku_id             varchar2(30)  path '$.SKU_ID',
                  sku_size           varchar2(60)  path '$.SKU_SIZE',
                  sku_width          varchar2(60)  path '$.SKU_WIDTH',
                  nested path '$.SKU_UPCS[*]'
                      columns (
                          upc_rn     for ordinality,
                          upc        varchar2(30) path '$.UPC',
                          upc_type   varchar2(10) path '$.UPC_TYPE',
                          primary_yn varchar2(1)  path '$.PRIMARY_YN'
                      )
          )
         where upc is not null;

    -- UDAs are style-level. SKUs inherit them from the style, so there is
    -- deliberately no SKU-level slot in the document; the mapper writes the same
    -- set to the parent and to every child.
    --
    -- The document puts its value in whichever of the three fields suits the UDA.
    -- Which one MFCS actually reads is decided by displayType, which comes from
    -- master data rather than from the document.
    cursor c_style_udas(cp_payload clob) is
        select rn, uda_id, uda_type, uda_value, uda_text, uda_date
          from json_table(cp_payload, '$.STYLE_UDAS[*]'
              columns
                  rn        for ordinality,
                  uda_id    number        path '$.UDA_ID',
                  uda_type  varchar2(2)   path '$.UDA_TYPE',
                  uda_value varchar2(30)  path '$.UDA_VALUE',
                  uda_text  varchar2(250) path '$.UDA_TEXT',
                  uda_date  varchar2(30)  path '$.UDA_DATE'
          );


    -- The size curve of any document carrying SIZE_CURVE_DETAIL - the stored
    -- request, or an MFCS response echoing the same shape back.
    function size_curve(p_payload in clob) return t_size_curve;

    -- The MFCS SKU behind one size-curve row: the row's own SKU_ID when the
    -- document carries it, otherwise the ENTITY_MAP row filed under the same
    -- source references - by an earlier request, or by ENSURE_STYLE_SKUS when
    -- it read or created the child. Public because the order-line sync needs
    -- the same resolution the mappers use; two resolutions could disagree.
    function resolve_sku(
        p_payload            in clob,
        p_source_variant_ref in varchar2,
        p_payload_sku        in varchar2
    ) return varchar2;

    -- A child this layer has decided to create: the reserved item number plus
    -- the resolved differentiators the gap analysis compared against.
    type t_generated_child is record (
        item               varchar2(30),
        sku_size           varchar2(60),
        size_diff          varchar2(120),
        colour_diff        varchar2(120),
        source_variant_ref varchar2(120),
        sku_width          varchar2(60)
    );
    type t_generated_children is table of t_generated_child index by pls_integer;

    -- Everything the generated-child builders need: the parent's identity and
    -- attributes as the tenant reports them (via sku_pkg.style_attributes), and
    -- the children to create. A typed record rather than a JSON document on
    -- purpose - a misspelled field here is a compile error, where a misspelled
    -- JSON key would be a silent null, which is the failure mode this whole
    -- layer is built to avoid.
    type t_child_plan is record (
        style                varchar2(30),
        dept                 number,
        class                number,
        subclass             number,
        original_retail      number,
        cost_zone_group_id   number,
        item_description     varchar2(250),
        short_description    varchar2(120),
        standard_uom         varchar2(10),
        store_order_multiple varchar2(1),
        supplier             number,
        unit_cost            number,
        origin_country       varchar2(3),
        children             t_generated_children
    );

    -- One purchase-order line as the sync step wants it to be (or, for a
    -- cancellation, as the order currently has it).
    type t_order_line is record (
        item          varchar2(30),
        quantity      number,
        -- The order's current quantity for the line, when it already has one.
        -- A reduction needs a reason: MFCS wants a cancel code on the quantity
        -- that goes away, distinct from a full-line cancellation.
        prev_quantity number
    );
    type t_order_lines is table of t_order_line index by pls_integer;

    -- What SYNC_ORDER_LINES decided after reading the order back:
    -- lines to update in place, lines to add, and this style's lines to cancel.
    -- Built by the orchestrator from tenant state; typed for the same reason as
    -- t_child_plan - a misspelled field should not compile.
    type t_order_line_plan is record (
        order_no           varchar2(30),
        location           number,
        location_type      varchar2(1),
        origin_country     varchar2(3),
        unit_cost          number,
        supplier_pack_size number,
        earliest_ship_date varchar2(20),
        latest_ship_date   varchar2(20),
        updates            t_order_lines,
        creates            t_order_lines,
        cancels            t_order_lines
    );

    -- purchaseOrder/details payloads. Update and create share a line shape;
    -- cancel goes through details/update with cancelInd and the tenant's own
    -- cancel code (code type ORCA - 'S' is literally "Colour/Location
    -- Switched"). purchaseOrders/update ignores its details array on this
    -- tenant, which is why these exist at all.
    function order_details_update_request(p_plan in t_order_line_plan) return clob;
    function order_details_create_request(p_plan in t_order_line_plan) return clob;
    function order_details_cancel_request(p_plan in t_order_line_plan) return clob;

    -- Payloads for children this layer decides at run time to create, as opposed
    -- to ones the inbound document names. The other item builders walk the whole
    -- size curve, which is right for a new style and wrong when only some of its
    -- combinations are missing: re-sending the rest either does nothing or makes
    -- a second child on the same diff pair. These take the missing subset only.
    -- Not reachable through build_request - a mapper name cannot carry the plan.
    function generated_child_create_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob;

    function generated_child_sourcing_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob;

    function generated_child_com_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob;

    function generated_child_approval_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob;
end payload_pkg;
/

show errors

create or replace package body payload_pkg as

    function size_curve(p_payload in clob) return t_size_curve is
        l_rows t_size_curve;
        l_i    pls_integer := 0;
    begin
        for v in c_size_curve(p_payload) loop
            l_i := l_i + 1;
            l_rows(l_i).rn := v.rn;
            l_rows(l_i).source_variant_ref := v.source_variant_ref;
            l_rows(l_i).sku_size := v.sku_size;
            l_rows(l_i).sku_width := v.sku_width;
            l_rows(l_i).sku_id := v.sku_id;
            l_rows(l_i).sku_qty := v.sku_qty;
        end loop;
        return l_rows;
    end;

    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from request
         where action_request_id = p_action_request_id;

        return l_payload;
    end;

    function source_system(p_payload in clob) return varchar2 is
        l_value varchar2(60);
    begin
        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function source_style_ref(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function source_order_ref(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select json_value(p_payload, '$.SOURCE_ORDER_REF' returning varchar2(120) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function user_id(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select coalesce(
                   json_value(p_payload, '$.USER_ID' returning varchar2(120) null on error),
                   json_value(p_payload, '$.APPROVED_BY' returning varchar2(120) null on error),
                   'INTEGRATION'
               )
          into l_value
          from dual;
        return l_value;
    end;

    function payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from request
         where action_request_id = p_action_request_id;
        return l_payload;
    end;

    function string_value(p_payload in clob, p_name in varchar2) return varchar2 is
    begin
        return json_object_t.parse(p_payload).get_string(p_name);
    end;

    function number_value(p_payload in clob, p_name in varchar2) return number is
    begin
        return json_object_t.parse(p_payload).get_number(p_name);
    end;

    -- A delivery location, as the virtual warehouse MFCS wants.
    --
    -- The one translation that survived MAP's retirement, because it is not a
    -- naming difference: item ranging is refused against a physical warehouse at
    -- hierarchy level W, and a caller may legitimately think in physical
    -- locations. It now derives from the tenant's own warehouse feed - the row
    -- for 1927 carries primaryVirtualWarehouse 19271 - rather than from a
    -- hand-maintained MAP.ORDER_LOCATION entry.
    --
    -- Passes the value straight through when it is already virtual, or when the
    -- warehouse is unknown to master data. A caller sending the virtual warehouse
    -- directly, which is what the console does, is unaffected either way.
    function virtual_location(p_location in varchar2) return varchar2 is
        l_virtual varchar2(120);
    begin
        if p_location is null then
            return null;
        end if;
        select max(json_value(attributes, '$.primaryVirtualWarehouse'))
          into l_virtual
          from master_data
         where data_type = 'WAREHOUSE_SVC'
           and data_code = p_location;
        return nvl(l_virtual, p_location);
    end;

    -- The operations that write to a style MFCS already holds. Their item payloads
    -- are updates, which carry only what is being set; a create carries the whole
    -- structural record. CREATE_ALL is a create, because it makes the style itself.
    function targets_existing_style(p_operation in varchar2) return boolean is
    begin
        return p_operation in ('MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER');
    end;

    function request_style(p_action_request_id in varchar2) return varchar2 is
        l_style varchar2(30);
    begin
        select style_no into l_style
          from request
         where action_request_id = p_action_request_id;
        return l_style;
    end;

    function request_order(p_action_request_id in varchar2) return varchar2 is
        l_order varchar2(30);
    begin
        select order_no into l_order
          from request
         where action_request_id = p_action_request_id;
        return l_order;
    end;

    function resolve_sku(
        p_payload            in clob,
        p_source_variant_ref in varchar2,
        p_payload_sku        in varchar2
    ) return varchar2 is
        l_sku varchar2(30) := p_payload_sku;
        l_source_system varchar2(60);
        l_source_style_ref varchar2(120);
    begin
        if l_sku is not null then
            return l_sku;
        end if;

        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60)),
               json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120))
          into l_source_system, l_source_style_ref
          from dual;

        select max(mfcs_sku_no)
          into l_sku
          from entity_map
         where source_system = l_source_system
           and source_style_ref = l_source_style_ref
           and source_variant_ref = p_source_variant_ref;
        return l_sku;
    end;

    function item_number_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_count number;
    begin
        -- One number per child plus one for the style itself.
        l_count := size_curve(l_payload).count + 1;
        l_root.put('itemNumberType', 'ITEM');
        l_root.put('quantity', l_count);
        l_root.put('daysUntilExpiry', 14);
        return l_root.to_clob;
    end;

    procedure append_parent_item(
        p_items       in out nocopy json_array_t,
        p_operation   in varchar2,
        p_style       in varchar2,
        p_department  in number,
        p_class       in number,
        p_subclass    in number,
        p_retail      in number,
        p_source_ref  in varchar2,
        p_color       in varchar2,
        -- Defaulted so a caller that has no brand to give does not have to say so.
        p_brand       in varchar2 default null
    ) is
        l_cost_zone_group_id number :=
            to_number(config_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_parent_diff1 varchar2(80) :=
            config_pkg.get_config('MFCS_PARENT_DIFF1_GROUP', 'RMS_ALL_C');
        l_parent_diff2 varchar2(80) :=
            config_pkg.get_config('MFCS_PARENT_DIFF2_GROUP', 'ALL');
        l_store_order_multiple varchar2(1) :=
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_item json_object_t := json_object_t();
    begin
        l_item.put('item', p_style);
        l_item.put('itemDescription', substr(p_source_ref, 1, 250));
        l_item.put('shortDescription', substr(p_source_ref, 1, 120));
        l_item.put('dataLoadingDestination', 'RMS');
        -- Omitted rather than sent null when the document carries no brand: the
        -- update services treat a null as a value and would clear an existing one.
        if p_brand is not null then
            l_item.put('brandName', p_brand);
        end if;
        -- storeOrderMultiple is not optional on an update, even one that only touches
        -- descriptions: items/update answers a payload without it with
        -- "Field must be entered.Field: STORE_ORD_MULT ... CORESVC_ITEM.PROCESS_IM".
        -- Proven live, which is why it sits outside the create-only block.
        l_item.put('storeOrderMultiple', l_store_order_multiple);
        if not targets_existing_style(p_operation) then
            l_item.put('itemNumberType', 'ITEM');
            l_item.put('itemLevel', 1);
            l_item.put('tranLevel', 2);
            l_item.put('dept', p_department);
            l_item.put('class', p_class);
            l_item.put('subclass', p_subclass);
            l_item.put('status', 'W');
            l_item.put('approveInd', 'N');
            l_item.put('standardUom', 'EA');
            l_item.put('merchandiseInd', 'Y');
            l_item.put('inventoryInd', 'Y');
            l_item.put('sellableInd', 'Y');
            l_item.put('orderableInd', 'Y');
            l_item.put('originalRetail', p_retail);
            l_item.put('costZoneGroupId', l_cost_zone_group_id);
            l_item.put('diff1', l_parent_diff1);
            l_item.put('diff1Type', 'C');
            l_item.put('diff2', l_parent_diff2);
            l_item.put('diff2Type', 'S');
        end if;
        p_items.append(l_item);
    end;

    procedure append_child_items(
        p_items       in out nocopy json_array_t,
        p_payload     in clob,
        p_operation   in varchar2,
        p_style       in varchar2,
        p_department  in number,
        p_class       in number,
        p_subclass    in number,
        p_retail      in number,
        p_source_ref  in varchar2,
        p_color       in varchar2
    ) is
        l_cost_zone_group_id number :=
            to_number(config_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_store_order_multiple varchar2(1) :=
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        for v in c_size_curve(p_payload) loop
            l_sku := resolve_sku(p_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('itemDescription', substr(p_source_ref || ' ' || v.sku_size, 1, 250));
            l_item.put('shortDescription', substr(p_source_ref, 1, 120));
            l_item.put('dataLoadingDestination', 'RMS');
            -- Required on update as well as create; see append_parent_item.
            l_item.put('storeOrderMultiple', l_store_order_multiple);
            if not targets_existing_style(p_operation) then
                l_item.put('itemParent', p_style);
                l_item.put('itemNumberType', 'ITEM');
                l_item.put('itemLevel', 2);
                l_item.put('tranLevel', 2);
                l_item.put('dept', p_department);
                l_item.put('class', p_class);
                l_item.put('subclass', p_subclass);
                l_item.put('status', 'W');
                l_item.put('approveInd', 'N');
                l_item.put('standardUom', 'EA');
                l_item.put('merchandiseInd', 'Y');
                l_item.put('inventoryInd', 'Y');
                l_item.put('sellableInd', 'Y');
                l_item.put('orderableInd', 'Y');
                l_item.put('originalRetail', p_retail);
                l_item.put('costZoneGroupId', l_cost_zone_group_id);
                l_item.put('diff1', p_color);
                l_item.put('diff1Type', 'C');
                l_item.put('diff2', v.sku_size);
                l_item.put('diff2Type', 'S');
            end if;
            p_items.append(l_item);
        end loop;
    end;

    procedure item_create_context(
        p_action_request_id in varchar2,
        o_payload           out clob,
        o_operation         out varchar2,
        o_style             out varchar2,
        o_department        out number,
        o_class             out number,
        o_subclass          out number,
        o_retail            out number,
        o_source_ref        out varchar2,
        o_color             out varchar2
    ) is
    begin
        o_payload := payload(p_action_request_id);
        o_style := request_style(p_action_request_id);
        select json_value(o_payload, '$.OPERATION_NAME' returning varchar2(30)),
               json_value(o_payload, '$.DEPARTMENT' returning number),
               json_value(o_payload, '$.CLASS' returning number),
               json_value(o_payload, '$.SUBCLASS' returning number),
               json_value(o_payload, '$.RETAIL_PRICE' returning number),
               json_value(o_payload, '$.SOURCE_STYLE_REF' returning varchar2(120)),
               json_value(o_payload, '$.COLOUR' returning varchar2(10))
          into o_operation, o_department, o_class, o_subclass, o_retail, o_source_ref, o_color
          from dual;
    end;

    function parent_item_create_request(p_action_request_id in varchar2) return clob is
        l_payload clob;
        l_operation varchar2(30);
        l_style varchar2(30);
        l_department number;
        l_class number;
        l_subclass number;
        l_retail number;
        l_source_ref varchar2(120);
        l_color varchar2(10);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
    begin
        item_create_context(p_action_request_id, l_payload, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);
        append_parent_item(l_items, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color,
            json_value(l_payload, '$.BRAND' returning varchar2(120) null on error));
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function child_item_create_request(p_action_request_id in varchar2) return clob is
        l_payload clob;
        l_operation varchar2(30);
        l_style varchar2(30);
        l_department number;
        l_class number;
        l_subclass number;
        l_retail number;
        l_source_ref varchar2(120);
        l_color varchar2(10);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
    begin
        item_create_context(p_action_request_id, l_payload, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);
        append_child_items(l_items, l_payload, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_create_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_operation varchar2(30);
        l_style varchar2(30) := request_style(p_action_request_id);
        l_department number;
        l_class number;
        l_subclass number;
        l_retail number;
        l_source_ref varchar2(120);
        l_color varchar2(10);
        l_cost_zone_group_id number :=
            to_number(config_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
    begin
        select json_value(l_payload, '$.OPERATION_NAME' returning varchar2(30)),
               json_value(l_payload, '$.DEPARTMENT' returning number),
               json_value(l_payload, '$.CLASS' returning number),
               json_value(l_payload, '$.SUBCLASS' returning number),
               json_value(l_payload, '$.RETAIL_PRICE' returning number),
               json_value(l_payload, '$.SOURCE_STYLE_REF' returning varchar2(120)),
               json_value(l_payload, '$.COLOUR' returning varchar2(10))
          into l_operation, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color
          from dual;

        append_parent_item(l_items, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color,
            json_value(l_payload, '$.BRAND' returning varchar2(120) null on error));
        append_child_items(l_items, l_payload, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function supplier_payload(
        p_item     in varchar2,
        p_supplier in number,
        p_cost     in number,
        p_country  in varchar2
    ) return json_object_t is
        l_item json_object_t := json_object_t();
        l_country_node json_object_t;
        l_suppliers json_array_t;
        l_countries json_array_t;
        l_supplier_node json_object_t;
    begin
        l_country_node := json_object_t();
        l_country_node.put('originCountry', p_country);
        l_country_node.put('primaryCountryInd', 'Y');
        l_country_node.put('unitCost', p_cost);
        l_country_node.put('defaultUop', config_pkg.get_config('MFCS_DEFAULT_UOP', 'EA'));
        l_country_node.put('costUom', config_pkg.get_config('MFCS_COST_UOM', 'EA'));
        l_country_node.put('supplierPackSize', to_number(config_pkg.get_config('MFCS_SUPPLIER_PACK_SIZE', '1')));
        l_country_node.put('innerPackSize', to_number(config_pkg.get_config('MFCS_INNER_PACK_SIZE', '1')));
        l_country_node.put('purchaseType', to_number(config_pkg.get_config('MFCS_PURCHASE_TYPE', '0')));
        l_countries := json_array_t();
        l_countries.append(l_country_node);

        l_supplier_node := json_object_t();
        l_supplier_node.put('supplier', p_supplier);
        l_supplier_node.put('primarySupplierInd', 'Y');
        -- The create service defaults this; the update service demands it, with
        -- "This column should not be null.Field: DIRECT_SHIP_IND ...
        -- CORESVC_ITEM.PROCESS_IS". Sent on both paths because the tenant stores N
        -- on every item anyway, so the create payload was only ever relying on luck.
        l_supplier_node.put('directShipInd', config_pkg.get_config('MFCS_DIRECT_SHIP_IND', 'N'));
        -- The packaging names. suppliers/update refuses without innerName, and there
        -- is no reason to think it stops there, so all three go every time rather
        -- than one per failed round trip. The values are the tenant's own: code types
        -- INRN, CASN and PALN, loaded into master data by master_pkg.refresh_all.
        -- EA rather than the spec's INR example because the pack sizes here are 1.
        l_supplier_node.put('innerName', config_pkg.get_config('MFCS_INNER_NAME', 'EA'));
        l_supplier_node.put('caseName', config_pkg.get_config('MFCS_CASE_NAME', 'CS'));
        l_supplier_node.put('palletName', config_pkg.get_config('MFCS_PALLET_NAME', 'PAL'));
        l_supplier_node.put('countryOfSourcing', l_countries);
        l_suppliers := json_array_t();
        l_suppliers.append(l_supplier_node);

        l_item.put('item', p_item);
        l_item.put('dataLoadingDestination', 'RMS');
        l_item.put('supplier', l_suppliers);
        return l_item;
    end;

    function parent_item_sourcing_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_supplier number;
        l_cost number;
        l_country varchar2(3);
    begin
        select json_value(l_payload, '$.SUPPLIER' returning number),
               json_value(l_payload, '$.UNIT_COST' returning number),
               json_value(l_payload, '$.ORIGIN_COUNTRY' returning varchar2(3))
          into l_supplier, l_cost, l_country
          from dual;

        l_items.append(supplier_payload(request_style(p_action_request_id), l_supplier, l_cost, l_country));
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_sourcing_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_supplier number;
        l_cost number;
        l_country varchar2(3);
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.SUPPLIER' returning number),
               json_value(l_payload, '$.UNIT_COST' returning number),
               json_value(l_payload, '$.ORIGIN_COUNTRY' returning varchar2(3))
          into l_supplier, l_cost, l_country
          from dual;

        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_items.append(supplier_payload(l_sku, l_supplier, l_cost, l_country));
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function child_item_sourcing_request(p_action_request_id in varchar2) return clob is
    begin
        return item_sourcing_request(p_action_request_id);
    end;

    function item_country_of_manufacture_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_supplier_node json_object_t;
        l_manufacture_node json_object_t;
        l_suppliers json_array_t;
        l_manufacturers json_array_t;
        l_supplier number;
        l_manufacturer_country varchar2(3) :=
            config_pkg.get_config('MFCS_MANUFACTURER_COUNTRY', 'VN');

        procedure append_item(p_item in varchar2) is
        begin
            l_manufacture_node := json_object_t();
            l_manufacture_node.put('manufacturerCountry', l_manufacturer_country);
            l_manufacture_node.put('primaryManufacturerCountryInd', 'Y');
            l_manufacturers := json_array_t();
            l_manufacturers.append(l_manufacture_node);

            l_supplier_node := json_object_t();
            l_supplier_node.put('supplier', l_supplier);
            l_supplier_node.put('countryOfManufacture', l_manufacturers);
            l_suppliers := json_array_t();
            l_suppliers.append(l_supplier_node);

            l_item := json_object_t();
            l_item.put('item', p_item);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('supplier', l_suppliers);
            l_items.append(l_item);
        end;
    begin
        select json_value(l_payload, '$.SUPPLIER' returning number)
          into l_supplier
          from dual;

        append_item(request_style(p_action_request_id));

        for v in c_size_curve(l_payload) loop
            append_item(resolve_sku(l_payload, v.source_variant_ref, v.sku_id));
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    -- A UDA's displayType, from master data.
    --
    -- MFCS rejects a uda row without displayType, and displayType decides which of
    -- udaValue / udaText / udaDate is read. Asking Office to send it would be
    -- asking them to restate something the tenant already publishes, so it is
    -- looked up from the definitions master_pkg.load_udas stores.
    --
    -- The fallbacks matter on a tenant whose UDA feed has not been refreshed. An
    -- explicit UDA_TYPE in the document wins, then master data, then the shape of
    -- the document row itself. Guessing beats sending nothing: a null displayType
    -- is a certain rejection, where a wrong guess is at least diagnosable.
    function uda_display_type(
        p_uda_id   in number,
        p_uda_type in varchar2,
        p_uda_text in varchar2,
        p_uda_date in varchar2
    ) return varchar2 is
        l_type varchar2(2);
    begin
        if p_uda_type is not null then
            return upper(p_uda_type);
        end if;

        begin
            select json_value(attributes, '$.displayType' returning varchar2(2))
              into l_type
              from master_data
             where data_type = 'UDA'
               and data_code = to_char(p_uda_id)
               and parent_code = '~';
        exception
            when no_data_found then
                l_type := null;
        end;

        if l_type is not null then
            return l_type;
        elsif p_uda_date is not null then
            return 'DT';
        elsif p_uda_text is not null then
            return 'FF';
        else
            return 'LV';
        end if;
    end;

    -- The style's UDA rows. Built fresh per caller rather than shared, because
    -- json_array_t is a reference type: attaching one instance to several items
    -- would alias the same rows across the payload.
    function style_uda_array(p_payload in clob) return json_array_t is
        l_udas json_array_t := json_array_t();
        l_uda json_object_t;
        l_type varchar2(2);
    begin
        for u in c_style_udas(p_payload) loop
            l_type := uda_display_type(u.uda_id, u.uda_type, u.uda_text, u.uda_date);
            l_uda := json_object_t();
            l_uda.put('udaId', u.uda_id);
            l_uda.put('displayType', l_type);
            case l_type
                when 'FF' then l_uda.put('udaText', nvl(u.uda_text, u.uda_value));
                when 'DT' then l_uda.put('udaDate', nvl(u.uda_date, u.uda_value));
                else l_uda.put('udaValue', u.uda_value);
            end case;
            l_udas.append(l_uda);
        end loop;
        return l_udas;
    end;

    function item_uda_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_style varchar2(30) := request_style(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        -- The parent carries the style's UDAs as well as the children, since SKUs
        -- inherit them and the tenant is not known to cascade. Skipped only when
        -- the style number is not resolvable yet.
        if l_style is not null then
            l_item := json_object_t();
            l_item.put('item', l_style);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('uda', style_uda_array(l_payload));
            l_items.append(l_item);
        end if;

        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            -- An empty array when the document carries no STYLE_UDAS. MFCS accepts
            -- it and does nothing, which keeps the step explicitly logged and keeps
            -- documents written before STYLE_UDAS behaving exactly as they did.
            l_item.put('uda', style_uda_array(l_payload));
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    -- Barcodes, as level-3 items under their SKU.
    --
    -- There is no reference-item service on this tenant - none in 323 spec paths -
    -- so a UPC is an item like any other, created through items/create. Three
    -- things are load-bearing and were each found the hard way, live:
    --
    --   itemNumberType must be EAN13. ITEM and an absent type both demand a
    --   9-character number, and UPC-A demands 12.
    --
    --   costZoneGroupId must be sent and must equal the parent's, or MFCS answers
    --   "Field cannot be modified. Field: COST_ZONE_GROUP_ID" - an error naming a
    --   field the request never contained.
    --
    --   status and itemSupplier are inherited from the parent, so they are not
    --   sent. The created record comes back approved with the parent's supplier
    --   already attached.
    function reference_item_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_style varchar2(30) := request_style(p_action_request_id);
        l_department number;
        l_class number;
        l_subclass number;
        l_source_ref varchar2(120);
        l_color varchar2(10);
        l_cost_zone_group_id number :=
            to_number(config_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_default_type varchar2(10) :=
            config_pkg.get_config('MFCS_UPC_ITEM_NUMBER_TYPE', 'EAN13');
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.DEPARTMENT' returning number),
               json_value(l_payload, '$.CLASS' returning number),
               json_value(l_payload, '$.SUBCLASS' returning number),
               json_value(l_payload, '$.SOURCE_STYLE_REF' returning varchar2(120)),
               json_value(l_payload, '$.COLOUR' returning varchar2(10))
          into l_department, l_class, l_subclass, l_source_ref, l_color
          from dual;

        for u in c_sku_upcs(l_payload) loop
            l_sku := resolve_sku(l_payload, u.source_variant_ref, u.sku_id);
            l_item := json_object_t();
            l_item.put('item', u.upc);
            l_item.put('itemParent', l_sku);
            l_item.put('itemGrandparent', l_style);
            l_item.put('itemLevel', 3);
            l_item.put('tranLevel', 2);
            l_item.put('itemNumberType', nvl(u.upc_type, l_default_type));
            l_item.put('primaryReferenceItemInd', nvl(upper(u.primary_yn), 'N'));
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('itemDescription', substr(l_source_ref || ' ' || u.sku_size, 1, 250));
            l_item.put('shortDescription', substr(l_source_ref, 1, 120));
            l_item.put('dept', l_department);
            l_item.put('class', l_class);
            l_item.put('subclass', l_subclass);
            l_item.put('diff1', l_color);
            l_item.put('diff2', u.sku_size);
            l_item.put('sellableInd', 'Y');
            l_item.put('orderableInd', 'Y');
            l_item.put('merchandiseInd', 'Y');
            l_item.put('inventoryInd', 'Y');
            l_item.put('standardUom', 'EA');
            l_item.put('costZoneGroupId', l_cost_zone_group_id);
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_location_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_location json_object_t;
        l_locations json_array_t;
        l_delivery number;
        l_hierarchy_value number;
        l_hierarchy_level varchar2(2) :=
            config_pkg.get_config('MFCS_LOCATION_HIERARCHY_LEVEL', 'CH');
        l_store_order_multiple varchar2(1) :=
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_taxable_ind varchar2(1) :=
            config_pkg.get_config('MFCS_TAXABLE_IND', 'Y');
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.DELIVERY_LOC' returning number)
          into l_delivery from dual;
        -- DELIVERY_LOC is an Office PHYSICAL location (1927). At hierarchyLevel W
        -- MFCS wants the VIRTUAL warehouse (19271) and rejects the physical one
        -- with "Invalid Warehouse". Map it the same way the purchase order does,
        -- so item ranging and ordering cannot disagree about where the item goes.
        l_hierarchy_value := to_number(
            coalesce(
                case when l_delivery is not null
                     then virtual_location(l_delivery)
                end,
                to_char(l_delivery),
                config_pkg.get_config('MFCS_LOCATION_HIERARCHY_VALUE', '19271')
            ));
        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_location := json_object_t();
            l_location.put('hierarchyValue', l_hierarchy_value);
            l_location.put('status', 'A');
            l_location.put('storeOrderMultiple', l_store_order_multiple);
            l_location.put('taxableInd', l_taxable_ind);
            l_locations := json_array_t();
            l_locations.append(l_location);

            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('hierarchyLevel', l_hierarchy_level);
            l_item.put('locations', l_locations);
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_approval_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_store_order_multiple varchar2(1) :=
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_source_ref varchar2(120);
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.SOURCE_STYLE_REF' returning varchar2(120))
          into l_source_ref
          from dual;

        l_item := json_object_t();
        l_item.put('item', request_style(p_action_request_id));
        l_item.put('itemDescription', substr(l_source_ref, 1, 250));
        l_item.put('shortDescription', substr(l_source_ref, 1, 120));
        l_item.put('status', 'A');
        l_item.put('approveInd', 'Y');
        l_item.put('storeOrderMultiple', l_store_order_multiple);
        l_item.put('dataLoadingDestination', 'RMS');
        l_items.append(l_item);
        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('itemDescription', substr(l_source_ref, 1, 250));
            l_item.put('shortDescription', substr(l_source_ref, 1, 120));
            l_item.put('status', 'A');
            l_item.put('approveInd', 'Y');
            l_item.put('storeOrderMultiple', l_store_order_multiple);
            l_item.put('dataLoadingDestination', 'RMS');
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function initial_retail_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_retail number;
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.RETAIL_PRICE' returning number) into l_retail from dual;
        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('originalRetail', l_retail);
            l_item.put('dataLoadingDestination', 'RMS');
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function po_number_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
    begin
        l_root.put('supplier', number_value(l_payload, 'SUPPLIER'));
        l_root.put('quantity', 1);
        l_root.put('expiryDays', to_number(config_pkg.get_config('MFCS_ORDER_RESERVATION_DAYS_UNTIL_EXPIRY', '1')));
        return l_root.to_clob;
    end;

    function optional_string(
        p_payload in clob,
        p_name    in varchar2
    ) return varchar2 is
    begin
        return json_object_t.parse(p_payload).get_string(p_name);
    exception
        when others then
            return null;
    end;

    function optional_number(
        p_payload in clob,
        p_name    in varchar2
    ) return number is
    begin
        return json_object_t.parse(p_payload).get_number(p_name);
    exception
        when others then
            return null;
    end;

    function order_location(p_payload in clob) return number is
        l_delivery varchar2(30);
        l_location varchar2(30);
    begin
        l_delivery := to_char(optional_number(p_payload, 'DELIVERY_LOC'));
        if l_delivery is not null then
            l_location := virtual_location(l_delivery);
        else
            l_location := config_pkg.get_config('MFCS_ORDER_DEFAULT_LOCATION', null);
        end if;
        return to_number(l_location);
    end;

    function purchase_order_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_orders json_array_t := json_array_t();
        l_order json_object_t := json_object_t();
        l_details json_array_t := json_array_t();
        l_detail json_object_t;
        l_expenses json_array_t := json_array_t();
        l_expense json_object_t;
        l_sku varchar2(30);
        l_operation varchar2(30);
        l_order_location number := order_location(l_payload);
        l_location_type varchar2(1) := config_pkg.get_config('MFCS_ORDER_LOCATION_TYPE', 'W');
        l_written_date varchar2(10) := substr(coalesce(optional_string(l_payload, 'WRITTEN_DATE'), to_char(sysdate, 'YYYY-MM-DD')), 1, 10);
        l_import_country varchar2(3) := coalesce(
            optional_string(l_payload, 'IMPORT_COUNTRY'),
            config_pkg.get_config('MFCS_ORDER_DEFAULT_IMPORT_COUNTRY', string_value(l_payload, 'ORIGIN_COUNTRY'))
        );
        l_terms varchar2(15) := coalesce(optional_string(l_payload, 'TERMS'), config_pkg.get_config('MFCS_ORDER_DEFAULT_TERMS', null));
    begin
        select json_value(l_payload, '$.OPERATION_NAME' returning varchar2(30)) into l_operation from dual;
        l_order.put('orderNo', to_number(request_order(p_action_request_id)));
        l_order.put('supplier', number_value(l_payload, 'SUPPLIER'));
        l_order.put('currencyCode', string_value(l_payload, 'CURRENCY_CODE'));
        if l_terms is not null then
            l_order.put('terms', l_terms);
        end if;
        l_order.put('notBeforeDate', string_value(l_payload, 'NOT_BEFORE_DATE'));
        l_order.put('notAfterDate', string_value(l_payload, 'NOT_AFTER_DATE'));
        if optional_string(l_payload, 'OTB_EOW_DATE') is not null then
            l_order.put('otbEowDate', optional_string(l_payload, 'OTB_EOW_DATE'));
        end if;
        l_order.put('earliestShipDate', string_value(l_payload, 'EARLIEST_SHIP_DATE'));
        l_order.put('latestShipDate', string_value(l_payload, 'LATEST_SHIP_DATE'));
        l_order.put('dept', number_value(l_payload, 'DEPARTMENT'));
        l_order.put('status', config_pkg.get_config('MFCS_ORDER_STATUS', 'A'));
        l_order.put('exchangeRate', coalesce(optional_number(l_payload, 'ORDER_EXCHANGE_RATE'), 1));
        l_order.put('includeOnOrderInd', config_pkg.get_config('MFCS_INCLUDE_ON_ORDER_IND', 'Y'));
        l_order.put('writtenDate', l_written_date);
        l_order.put('origin', config_pkg.get_config('MFCS_ORDER_ORIGIN', '2'));
        l_order.put('ediPoInd', config_pkg.get_config('MFCS_EDI_PO_IND', 'N'));
        l_order.put('preMarkInd', config_pkg.get_config('MFCS_PRE_MARK_IND', 'N'));
        l_order.put('approvedBy', user_id(l_payload));
        l_order.put('commentDesc', coalesce(optional_string(l_payload, 'ORDER_AMEND_MSG'), optional_string(l_payload, 'SPECIAL_INSTRUCTION'), source_order_ref(l_payload)));
        l_order.put('dataLoadingDestination', 'RMS');
        l_order.put('importCountry', l_import_country);
        l_order.put('orderType', config_pkg.get_config('MFCS_ORDER_TYPE', 'N/B'));
        if optional_string(l_payload, 'PO_TYPE') is not null then
            l_order.put('purchaseOrderType', optional_string(l_payload, 'PO_TYPE'));
        end if;
        l_order.put('location', l_order_location);
        l_order.put('locationType', l_location_type);
        l_order.put('qualityControlInd', config_pkg.get_config('MFCS_QUALITY_CONTROL_IND', 'N'));
        l_order.put('freightTerms', config_pkg.get_config('MFCS_FREIGHT_TERMS', 'PREPAID'));

        for v in c_size_curve(l_payload) loop
            l_sku := resolve_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_detail := json_object_t();
            l_detail.put('item', l_sku);
            l_detail.put('location', l_order_location);
            l_detail.put('locationType', l_location_type);
            l_detail.put('unitCost', number_value(l_payload, 'UNIT_COST'));
            l_detail.put('originCountry', string_value(l_payload, 'ORIGIN_COUNTRY'));
            l_detail.put('supplierPackSize', to_number(config_pkg.get_config('MFCS_SUPPLIER_PACK_SIZE', '1')));
            l_detail.put('quantityOrdered', v.sku_qty);
            l_detail.put('earliestShipDate', string_value(l_payload, 'EARLIEST_SHIP_DATE'));
            l_detail.put('latestShipDate', string_value(l_payload, 'LATEST_SHIP_DATE'));
            l_details.append(l_detail);

            -- Non-merchandise costs, one expense row per SKU per location. This is
            -- the ORDLOC_EXP equivalent: unit cost covers the merchandise, these
            -- cover freight, duty, handling and so on, and together they give
            -- landed cost. MFCS accepts them inside the order create, so they do
            -- not need a separate call.
            for e in (
                select component, calculation_basis, component_rate, component_currency,
                       per_count, per_count_uom, in_duty, in_expense, in_alc
                  from json_table(l_payload, '$.NON_MERCH_COSTS[*]'
                      columns
                          component          varchar2(30)  path '$.COMPONENT',
                          calculation_basis  varchar2(10)  path '$.CALCULATION_BASIS',
                          component_rate     number        path '$.RATE',
                          component_currency varchar2(10)  path '$.CURRENCY',
                          per_count          number        path '$.PER_COUNT',
                          per_count_uom      varchar2(10)  path '$.PER_COUNT_UOM',
                          in_duty            varchar2(1)   path '$.IN_DUTY',
                          in_expense         varchar2(1)   path '$.IN_EXPENSE',
                          in_alc             varchar2(1)   path '$.IN_ALC'
                  )
            ) loop
                l_expense := json_object_t();
                l_expense.put('item', l_sku);
                l_expense.put('location', l_order_location);
                l_expense.put('locationType', l_location_type);
                l_expense.put('component', e.component);
                l_expense.put('calculationBasis',
                    nvl(e.calculation_basis, config_pkg.get_config('MFCS_EXPENSE_CALC_BASIS', 'V')));
                l_expense.put('componentRate', e.component_rate);
                l_expense.put('componentCurrency',
                    nvl(e.component_currency, string_value(l_payload, 'CURRENCY_CODE')));
                if e.per_count is not null then
                    l_expense.put('perCount', e.per_count);
                    l_expense.put('perCountUom',
                        nvl(e.per_count_uom, config_pkg.get_config('MFCS_COST_UOM', 'EA')));
                end if;
                -- Nomination flags decide whether a component feeds duty, expense
                -- and actual landed cost. Defaulted rather than omitted, because
                -- omitting them changes what the cost is counted towards.
                l_expense.put('inDuty', nvl(e.in_duty, config_pkg.get_config('MFCS_EXPENSE_IN_DUTY', 'N')));
                l_expense.put('inExpense', nvl(e.in_expense, config_pkg.get_config('MFCS_EXPENSE_IN_EXPENSE', 'Y')));
                l_expense.put('inAlc', nvl(e.in_alc, config_pkg.get_config('MFCS_EXPENSE_IN_ALC', 'Y')));
                l_expenses.append(l_expense);
            end loop;
        end loop;
        l_order.put('details', l_details);
        if l_expenses.get_size > 0 then
            l_order.put('expenses', l_expenses);
        end if;
        l_orders.append(l_order);
        l_root.put('items', l_orders);
        return l_root.to_clob;
    end;

    -- Sourcing terms for a generated child. The document wins where it names
    -- them, because that is the commercial decision the request is carrying. The
    -- parent style is the fallback, for the order-shaped documents that name a
    -- style and say nothing about sourcing at all.
    procedure generated_sourcing_context(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan,
        o_supplier          out number,
        o_cost              out number,
        o_country           out varchar2
    ) is
        l_payload clob := payload(p_action_request_id);
    begin
        select json_value(l_payload, '$.SUPPLIER' returning number),
               json_value(l_payload, '$.UNIT_COST' returning number),
               json_value(l_payload, '$.ORIGIN_COUNTRY' returning varchar2(3))
          into o_supplier, o_cost, o_country
          from dual;

        o_supplier := coalesce(o_supplier, p_plan.supplier);
        o_cost := coalesce(o_cost, p_plan.unit_cost);
        o_country := coalesce(o_country, p_plan.origin_country);

        -- Approval requires sourcing, so a child created without it would be
        -- stranded in worksheet status. Better to say so before anything has
        -- been created.
        if o_supplier is null or o_country is null then
            raise_application_error(-20964,
                'Cannot create children for style ' || p_plan.style
                || ': neither the request nor the style itself gives a supplier and origin '
                || 'country, and MFCS will not approve an item that has no sourcing.');
        end if;
    end;

    function generated_child_create_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        -- Everything structural comes from the parent as the tenant holds it,
        -- not from configuration. A child that disagreed with its parent about
        -- the hierarchy would be rejected; one that agreed with our defaults
        -- instead of with its parent would be worse, because it would be
        -- accepted and wrong. Configuration only fills what the read did not
        -- carry.
        l_cost_zone_group_id number := nvl(p_plan.cost_zone_group_id,
            to_number(config_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000')));
        l_store_order_multiple varchar2(1) := nvl(p_plan.store_order_multiple,
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E'));
        l_standard_uom varchar2(10) := nvl(p_plan.standard_uom, 'EA');
        l_child t_generated_child;
    begin
        for i in 1 .. p_plan.children.count loop
            l_child := p_plan.children(i);
            l_item := json_object_t();
            l_item.put('item', l_child.item);
            l_item.put('itemParent', p_plan.style);
            l_item.put('itemDescription',
                substr(trim(p_plan.item_description || ' ' || l_child.sku_size
                    || ' ' || l_child.sku_width), 1, 250));
            l_item.put('shortDescription',
                substr(nvl(p_plan.short_description, p_plan.item_description), 1, 120));
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('itemNumberType', 'ITEM');
            l_item.put('itemLevel', 2);
            l_item.put('tranLevel', 2);
            l_item.put('dept', p_plan.dept);
            l_item.put('class', p_plan.class);
            l_item.put('subclass', p_plan.subclass);
            l_item.put('status', 'W');
            l_item.put('approveInd', 'N');
            l_item.put('standardUom', l_standard_uom);
            l_item.put('merchandiseInd', 'Y');
            l_item.put('inventoryInd', 'Y');
            l_item.put('sellableInd', 'Y');
            l_item.put('orderableInd', 'Y');
            l_item.put('storeOrderMultiple', l_store_order_multiple);
            if p_plan.original_retail is not null then
                l_item.put('originalRetail', p_plan.original_retail);
            end if;
            l_item.put('costZoneGroupId', l_cost_zone_group_id);
            -- The diffs are already resolved. The plan carries the values the
            -- gap analysis compared against, so a child cannot be created on a
            -- different combination from the one found missing.
            l_item.put('diff1', l_child.colour_diff);
            l_item.put('diff1Type', 'C');
            l_item.put('diff2', l_child.size_diff);
            l_item.put('diff2Type', 'S');
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function generated_child_sourcing_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_supplier number;
        l_cost number;
        l_country varchar2(3);
    begin
        generated_sourcing_context(p_action_request_id, p_plan, l_supplier, l_cost, l_country);

        for i in 1 .. p_plan.children.count loop
            l_items.append(supplier_payload(p_plan.children(i).item, l_supplier, l_cost, l_country));
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function generated_child_com_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_supplier_node json_object_t;
        l_manufacture_node json_object_t;
        l_suppliers json_array_t;
        l_manufacturers json_array_t;
        l_supplier number;
        l_cost number;
        l_country varchar2(3);
        l_manufacturer_country varchar2(3) :=
            config_pkg.get_config('MFCS_MANUFACTURER_COUNTRY', 'VN');
    begin
        generated_sourcing_context(p_action_request_id, p_plan, l_supplier, l_cost, l_country);

        -- Only the new children. The parent already carries a country of
        -- manufacture, or it could not have been approved in the first place.
        for i in 1 .. p_plan.children.count loop
            l_manufacture_node := json_object_t();
            l_manufacture_node.put('manufacturerCountry', l_manufacturer_country);
            l_manufacture_node.put('primaryManufacturerCountryInd', 'Y');
            l_manufacturers := json_array_t();
            l_manufacturers.append(l_manufacture_node);

            l_supplier_node := json_object_t();
            l_supplier_node.put('supplier', l_supplier);
            l_supplier_node.put('countryOfManufacture', l_manufacturers);
            l_suppliers := json_array_t();
            l_suppliers.append(l_supplier_node);

            l_item := json_object_t();
            l_item.put('item', p_plan.children(i).item);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('supplier', l_suppliers);
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function generated_child_approval_request(
        p_action_request_id in varchar2,
        p_plan              in t_child_plan
    ) return clob is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_store_order_multiple varchar2(1) := nvl(p_plan.store_order_multiple,
            config_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E'));

        procedure append_approval(p_item in varchar2, p_description in varchar2) is
        begin
            l_item := json_object_t();
            l_item.put('item', p_item);
            l_item.put('itemDescription', substr(p_description, 1, 250));
            l_item.put('shortDescription',
                substr(nvl(p_plan.short_description, p_description), 1, 120));
            l_item.put('status', 'A');
            l_item.put('approveInd', 'Y');
            l_item.put('storeOrderMultiple', l_store_order_multiple);
            l_item.put('dataLoadingDestination', 'RMS');
            l_items.append(l_item);
        end;
    begin
        -- The parent goes in every time, not only when a read says it is
        -- unapproved. Deciding from observed status would be a partial update,
        -- which this layer does not do; re-approving an approved item costs a
        -- field in a payload that is being sent regardless.
        append_approval(p_plan.style, p_plan.item_description);

        for i in 1 .. p_plan.children.count loop
            append_approval(p_plan.children(i).item,
                trim(p_plan.item_description || ' ' || p_plan.children(i).sku_size
                    || ' ' || p_plan.children(i).sku_width));
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    -- Shared line shape for details create/update. Everything except item and
    -- quantity is order-level on this integration: one style, one supplier,
    -- one delivery location per document.
    function order_line_node(
        p_plan in t_order_line_plan,
        p_line in t_order_line
    ) return json_object_t is
        l_line json_object_t := json_object_t();
    begin
        l_line.put('item', p_line.item);
        l_line.put('location', p_plan.location);
        l_line.put('locationType', p_plan.location_type);
        l_line.put('unitCost', p_plan.unit_cost);
        l_line.put('originCountry', p_plan.origin_country);
        l_line.put('supplierPackSize', p_plan.supplier_pack_size);
        l_line.put('quantityOrdered', p_line.quantity);
        -- Reducing a line needs a reason - B, "Buyer Cancelled" - distinct from a
        -- full-line cancellation's S, "Colour/Location Switched" (both from the
        -- tenant's own code type ORCA). quantityOrdered is authoritative;
        -- quantityCancelled is deliberately NOT sent. It proved to be
        -- cumulative-absolute on this tenant: re-sending a line's existing
        -- cancelled quantity is a silent no-op, which left a cancel half-applied
        -- the first time this ran live.
        if p_line.prev_quantity is not null and p_line.quantity < p_line.prev_quantity then
            l_line.put('cancelCode', config_pkg.get_config('MFCS_ORDER_REDUCE_CANCEL_CODE', 'B'));
        end if;
        l_line.put('earliestShipDate', p_plan.earliest_ship_date);
        l_line.put('latestShipDate', p_plan.latest_ship_date);
        return l_line;
    end;

    function order_details_envelope(
        p_plan    in t_order_line_plan,
        p_details in json_array_t
    ) return clob is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_order json_object_t := json_object_t();
    begin
        l_order.put('orderNo', to_number(p_plan.order_no));
        l_order.put('dataLoadingDestination', 'RMS');
        l_order.put('details', p_details);
        l_items.append(l_order);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function order_details_update_request(p_plan in t_order_line_plan) return clob is
        l_details json_array_t := json_array_t();
    begin
        for i in 1 .. p_plan.updates.count loop
            l_details.append(order_line_node(p_plan, p_plan.updates(i)));
        end loop;
        return order_details_envelope(p_plan, l_details);
    end;

    function order_details_create_request(p_plan in t_order_line_plan) return clob is
        l_details json_array_t := json_array_t();
    begin
        for i in 1 .. p_plan.creates.count loop
            l_details.append(order_line_node(p_plan, p_plan.creates(i)));
        end loop;
        return order_details_envelope(p_plan, l_details);
    end;

    function order_details_cancel_request(p_plan in t_order_line_plan) return clob is
        l_details json_array_t := json_array_t();
        l_line json_object_t;
        l_cancel_code varchar2(6) := config_pkg.get_config('MFCS_ORDER_CANCEL_CODE', 'S');
    begin
        -- A full cancellation drives quantityOrdered to zero and says why. Not
        -- quantityCancelled: that field is cumulative-absolute on this tenant,
        -- so a line with a prior partial cancellation ignores a repeat of its
        -- existing cancelled quantity - proven live when one of three identical
        -- cancels silently did nothing. quantityOrdered:0 zeroes the line
        -- regardless of its history.
        for i in 1 .. p_plan.cancels.count loop
            l_line := json_object_t();
            l_line.put('item', p_plan.cancels(i).item);
            l_line.put('location', p_plan.location);
            l_line.put('locationType', p_plan.location_type);
            l_line.put('quantityOrdered', 0);
            l_line.put('cancelInd', 'Y');
            l_line.put('cancelCode', l_cancel_code);
            l_details.append(l_line);
        end loop;
        return order_details_envelope(p_plan, l_details);
    end;

    function build_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob is
    begin
        case p_mapper_name
            when 'build_item_number_request' then return item_number_request(p_action_request_id);
            when 'build_parent_item_create_request' then return parent_item_create_request(p_action_request_id);
            when 'build_child_item_create_request' then return child_item_create_request(p_action_request_id);
            when 'build_item_create_request' then return item_create_request(p_action_request_id);
            when 'build_parent_item_sourcing_request' then return parent_item_sourcing_request(p_action_request_id);
            when 'build_child_item_sourcing_request' then return child_item_sourcing_request(p_action_request_id);
            when 'build_item_sourcing_request' then return item_sourcing_request(p_action_request_id);
            when 'build_item_country_of_manufacture_request' then return item_country_of_manufacture_request(p_action_request_id);
            when 'build_item_uda_request' then return item_uda_request(p_action_request_id);
            when 'build_reference_item_request' then return reference_item_request(p_action_request_id);
            when 'build_item_location_request' then return item_location_request(p_action_request_id);
            when 'build_item_approval_request' then return item_approval_request(p_action_request_id);
            when 'build_initial_retail_request' then return initial_retail_request(p_action_request_id);
            when 'build_po_number_request' then return po_number_request(p_action_request_id);
            when 'build_purchase_order_request' then return purchase_order_request(p_action_request_id);
            when 'build_purchase_order_verify_request' then return '{}';
            else raise_application_error(-20820, 'Unsupported public mapper: ' || p_mapper_name);
        end case;
    end;
end payload_pkg;
/

show errors

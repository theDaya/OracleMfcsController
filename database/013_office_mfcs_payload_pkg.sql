-- Builds the MFCS request payload for each orchestration step.
--
-- This is THE production mapper. office_mfcs_mapping_pkg delegates every
-- build_*_request call here. It previously lived under tests/ and was described
-- as simulator-only, which was wrong and produced ORA-20811 on any install that
-- followed the old README order.

set define off

prompt Creating OFFICE MFCS MFCS payload mapper package

create or replace package office_mfcs_payload_pkg authid definer as
    function build_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob;
end office_mfcs_payload_pkg;
/

create or replace package body office_mfcs_payload_pkg as
    function payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from office_mfcs_request
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

    function mapped_config_value(
        p_prefix  in varchar2,
        p_value   in varchar2
    ) return varchar2 is
    begin
        if p_value is null then
            return null;
        end if;
        return office_mfcs_request_pkg.get_config(p_prefix || upper(p_value), p_value);
    end;

    function request_style(p_action_request_id in varchar2) return varchar2 is
        l_style varchar2(30);
    begin
        select style_no into l_style
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_style;
    end;

    function request_order(p_action_request_id in varchar2) return varchar2 is
        l_order varchar2(30);
    begin
        select order_no into l_order
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_order;
    end;

    function resolved_sku(
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
          from office_mfcs_entity_map
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
        select count(*) + 1
          into l_count
          from json_table(l_payload, '$.PLMSizeCurveDtl[*]' columns x path '$');
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
        p_color       in varchar2
    ) is
        l_cost_zone_group_id number :=
            to_number(office_mfcs_request_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_parent_diff1 varchar2(80) :=
            office_mfcs_request_pkg.get_config('MFCS_PARENT_DIFF1_GROUP', 'RMS_ALL_C');
        l_parent_diff2 varchar2(80) :=
            office_mfcs_request_pkg.get_config('MFCS_PARENT_DIFF2_GROUP', 'ALL');
        l_store_order_multiple varchar2(1) :=
            office_mfcs_request_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_item json_object_t := json_object_t();
    begin
        l_item.put('item', p_style);
        l_item.put('itemDescription', substr(p_source_ref, 1, 250));
        l_item.put('shortDescription', substr(p_source_ref, 1, 120));
        l_item.put('dataLoadingDestination', 'RMS');
        if p_operation <> 'MODIFY_STYLE' then
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
            l_item.put('storeOrderMultiple', l_store_order_multiple);
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
            to_number(office_mfcs_request_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
        l_store_order_multiple varchar2(1) :=
            office_mfcs_request_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        for v in (
            select source_variant_ref, sku_size, sku_width, sku_id
              from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_size varchar2(60) path '$.SKU_SIZE',
                      sku_width varchar2(60) path '$.SKU_WIDTH',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(p_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('itemDescription', substr(p_source_ref || ' ' || v.sku_size || ' ' || v.sku_width, 1, 250));
            l_item.put('shortDescription', substr(p_source_ref, 1, 120));
            l_item.put('dataLoadingDestination', 'RMS');
            if p_operation <> 'MODIFY_STYLE' then
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
                l_item.put('storeOrderMultiple', l_store_order_multiple);
                l_item.put('originalRetail', p_retail);
                l_item.put('costZoneGroupId', l_cost_zone_group_id);
                l_item.put('diff1', mapped_config_value('MAP.COLOUR.', p_color));
                l_item.put('diff1Type', 'C');
                l_item.put('diff2', mapped_config_value('MAP.SIZE.', v.sku_size));
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
        append_parent_item(l_items, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);
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
            to_number(office_mfcs_request_pkg.get_config('MFCS_COST_ZONE_GROUP_ID', '2000'));
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

        append_parent_item(l_items, l_operation, l_style, l_department, l_class, l_subclass, l_retail, l_source_ref, l_color);
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
        l_country_node.put('defaultUop', office_mfcs_request_pkg.get_config('MFCS_DEFAULT_UOP', 'EA'));
        l_country_node.put('costUom', office_mfcs_request_pkg.get_config('MFCS_COST_UOM', 'EA'));
        l_country_node.put('supplierPackSize', to_number(office_mfcs_request_pkg.get_config('MFCS_SUPPLIER_PACK_SIZE', '1')));
        l_country_node.put('innerPackSize', to_number(office_mfcs_request_pkg.get_config('MFCS_INNER_PACK_SIZE', '1')));
        l_country_node.put('purchaseType', to_number(office_mfcs_request_pkg.get_config('MFCS_PURCHASE_TYPE', '0')));
        l_countries := json_array_t();
        l_countries.append(l_country_node);

        l_supplier_node := json_object_t();
        l_supplier_node.put('supplier', p_supplier);
        l_supplier_node.put('primarySupplierInd', 'Y');
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

        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
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
            office_mfcs_request_pkg.get_config('MFCS_MANUFACTURER_COUNTRY', 'VN');

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

        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            append_item(resolved_sku(l_payload, v.source_variant_ref, v.sku_id));
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_uda_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('uda', json_array_t());
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
            office_mfcs_request_pkg.get_config('MFCS_LOCATION_HIERARCHY_LEVEL', 'CH');
        l_store_order_multiple varchar2(1) :=
            office_mfcs_request_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
        l_taxable_ind varchar2(1) :=
            office_mfcs_request_pkg.get_config('MFCS_TAXABLE_IND', 'Y');
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.DELIVERY_LOC' returning number)
          into l_delivery from dual;
        l_hierarchy_value := coalesce(
            l_delivery,
            to_number(office_mfcs_request_pkg.get_config('MFCS_LOCATION_HIERARCHY_VALUE', '1'))
        );
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
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
            office_mfcs_request_pkg.get_config('MFCS_STORE_ORDER_MULTIPLE', 'E');
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
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
            )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
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
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF', sku_id varchar2(30) path '$.SKU_ID')
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
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
        l_root.put('expiryDays', to_number(office_mfcs_request_pkg.get_config('MFCS_ORDER_RESERVATION_DAYS_UNTIL_EXPIRY', '1')));
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
            l_location := office_mfcs_request_pkg.get_config('MAP.ORDER_LOCATION.' || l_delivery, l_delivery);
        else
            l_location := office_mfcs_request_pkg.get_config('MFCS_ORDER_DEFAULT_LOCATION', null);
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
        l_sku varchar2(30);
        l_operation varchar2(30);
        l_order_location number := order_location(l_payload);
        l_location_type varchar2(1) := office_mfcs_request_pkg.get_config('MFCS_ORDER_LOCATION_TYPE', 'W');
        l_written_date varchar2(10) := substr(coalesce(optional_string(l_payload, 'WRITTEN_DATE'), to_char(sysdate, 'YYYY-MM-DD')), 1, 10);
        l_import_country varchar2(3) := coalesce(
            optional_string(l_payload, 'IMPORT_COUNTRY'),
            office_mfcs_request_pkg.get_config('MFCS_ORDER_DEFAULT_IMPORT_COUNTRY', string_value(l_payload, 'ORIGIN_COUNTRY'))
        );
        l_terms varchar2(15) := coalesce(optional_string(l_payload, 'TERMS'), office_mfcs_request_pkg.get_config('MFCS_ORDER_DEFAULT_TERMS', null));
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
        l_order.put('status', office_mfcs_request_pkg.get_config('MFCS_ORDER_STATUS', 'A'));
        l_order.put('exchangeRate', coalesce(optional_number(l_payload, 'ORDER_EXCHANGE_RATE'), 1));
        l_order.put('includeOnOrderInd', office_mfcs_request_pkg.get_config('MFCS_INCLUDE_ON_ORDER_IND', 'Y'));
        l_order.put('writtenDate', l_written_date);
        l_order.put('origin', office_mfcs_request_pkg.get_config('MFCS_ORDER_ORIGIN', '2'));
        l_order.put('ediPoInd', office_mfcs_request_pkg.get_config('MFCS_EDI_PO_IND', 'N'));
        l_order.put('preMarkInd', office_mfcs_request_pkg.get_config('MFCS_PRE_MARK_IND', 'N'));
        l_order.put('approvedBy', office_mfcs_mapping_pkg.user_id(l_payload));
        l_order.put('commentDesc', coalesce(optional_string(l_payload, 'ORDER_AMEND_MSG'), optional_string(l_payload, 'SPECIAL_INSTRUCTION'), office_mfcs_mapping_pkg.source_order_ref(l_payload)));
        l_order.put('dataLoadingDestination', 'RMS');
        l_order.put('importCountry', l_import_country);
        l_order.put('orderType', office_mfcs_request_pkg.get_config('MFCS_ORDER_TYPE', 'N/B'));
        if optional_string(l_payload, 'PO_TYPE') is not null then
            l_order.put('purchaseOrderType', optional_string(l_payload, 'PO_TYPE'));
        end if;
        l_order.put('location', l_order_location);
        l_order.put('locationType', l_location_type);
        l_order.put('qualityControlInd', office_mfcs_request_pkg.get_config('MFCS_QUALITY_CONTROL_IND', 'N'));
        l_order.put('freightTerms', office_mfcs_request_pkg.get_config('MFCS_FREIGHT_TERMS', 'PREPAID'));

        for v in (
            select source_variant_ref, sku_id, sku_qty
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID',
                      sku_qty number path '$.SKU_QTY')
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_detail := json_object_t();
            l_detail.put('item', l_sku);
            l_detail.put('location', l_order_location);
            l_detail.put('locationType', l_location_type);
            l_detail.put('unitCost', number_value(l_payload, 'UNIT_COST'));
            l_detail.put('originCountry', string_value(l_payload, 'ORIGIN_COUNTRY'));
            l_detail.put('supplierPackSize', to_number(office_mfcs_request_pkg.get_config('MFCS_SUPPLIER_PACK_SIZE', '1')));
            l_detail.put('quantityOrdered', v.sku_qty);
            l_detail.put('earliestShipDate', string_value(l_payload, 'EARLIEST_SHIP_DATE'));
            l_detail.put('latestShipDate', string_value(l_payload, 'LATEST_SHIP_DATE'));
            l_details.append(l_detail);
        end loop;
        l_order.put('details', l_details);
        l_orders.append(l_order);
        l_root.put('items', l_orders);
        return l_root.to_clob;
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
            when 'build_item_location_request' then return item_location_request(p_action_request_id);
            when 'build_item_approval_request' then return item_approval_request(p_action_request_id);
            when 'build_initial_retail_request' then return initial_retail_request(p_action_request_id);
            when 'build_po_number_request' then return po_number_request(p_action_request_id);
            when 'build_purchase_order_request' then return purchase_order_request(p_action_request_id);
            when 'build_purchase_order_verify_request' then return '{}';
            else raise_application_error(-20820, 'Unsupported public mapper: ' || p_mapper_name);
        end case;
    end;
end office_mfcs_payload_pkg;
/

show errors

prompt OFFICE MFCS MFCS payload mapper package created

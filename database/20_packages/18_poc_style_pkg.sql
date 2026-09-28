set define off

-- Office style-composition POC: the calling system, not the integration layer.
--
-- This package composes an MFCS item number and description from a style and a
-- supplier colour, gathers everything else the console captured, and hands the
-- result to api_pkg as an ordinary inbound document. The controller accepts a
-- number and a description; it does not invent either. Keeping the rule here is
-- what lets a second caller number and name its items differently without this
-- repo knowing.
--
-- The composition rule, from the Office specification:
--
--   style number  = style/model number + supplier colour code
--   style desc    = style/model description + supplier colour name
--   sku number    = style number + size differentiator
--   sku desc      = style description + size description
--
-- Numbers are concatenated with no separator, as specified. That is safe here
-- for a reason worth stating: a five-digit style and a three-digit colour code
-- compose eight characters, and every number MFCS generates for itself is nine,
-- so the two namespaces cannot collide. Change either width and that stops being
-- true.
--
-- Nothing reaches MFCS until a draft has been submitted for review and then
-- approved. Submitting builds the document and freezes it; approving replays
-- that frozen document rather than rebuilding it, so what the approver saw is
-- what MFCS receives. Rebuilding at approval would make the approval decorative.

prompt Creating poc_style_pkg

create or replace package poc_style_pkg authid definer as
    -- The composition rule, exposed so the console can show what will be sent
    -- before anything is sent. Same functions the document builder uses, so the
    -- preview cannot disagree with the payload.
    function compose_style_no(
        p_style_no    in varchar2,
        p_colour_code in varchar2
    ) return varchar2;

    function compose_style_desc(
        p_style_desc  in varchar2,
        p_colour_name in varchar2
    ) return varchar2;

    function compose_sku_no(
        p_style_no    in varchar2,
        p_colour_code in varchar2,
        p_sku_size    in varchar2
    ) return varchar2;

    function compose_sku_desc(
        p_style_desc  in varchar2,
        p_colour_name in varchar2,
        p_size_desc   in varchar2
    ) return varchar2;

    -- Recomputes every composed value on a draft and its size curve, and stores
    -- them. A draft that was seeded from MFCS rather than composed is left
    -- alone: its numbers belong to the tenant and are not ours to rebuild.
    procedure refresh_composition(p_draft_id in number);

    -- The inbound document this draft would send. Built from the stored
    -- composition, so what the console previews is what api_pkg receives.
    function build_document(p_draft_id in number) return clob;

    -- Validates the document without registering or sending anything.
    procedure validate_draft(
        p_draft_id    in number,
        o_http_status out number,
        o_response    out clob
    );

    -- Submit for review. Validates, freezes the document on the draft and
    -- records who submitted it. Makes no MFCS call.
    procedure submit_for_review(
        p_draft_id    in number,
        p_submitted_by in varchar2,
        o_http_status out number,
        o_response    out clob
    );

    -- Approve, and send. Replays the document frozen at submit.
    procedure approve_draft(
        p_draft_id    in number,
        p_approved_by in varchar2,
        o_http_status out number,
        o_response    out clob
    );

    -- Back to DRAFT, discarding the frozen document and the review record. The
    -- only way to edit a submitted draft, and deliberately explicit: a change
    -- made behind an approval is a change nobody approved.
    procedure reopen_draft(p_draft_id in number);

    -- Seeds a draft from an order that already exists in MFCS, for amendment.
    -- Returns the new draft id.
    function seed_from_order(
        p_order_no in varchar2,
        p_user_id  in varchar2
    ) return number;

    -- Unpacks the controller's status document onto the draft: the MFCS style
    -- number, the purchase order number, and each SKU number against the size
    -- curve row that asked for it.
    --
    -- This is the whole of the POC's read side, and it deliberately parses a
    -- response document rather than querying MFCS_INTEGRATION.REQUEST. The
    -- controller's contract is that document; joining to its tables instead
    -- would make every internal change of theirs a change here.
    procedure apply_response(
        p_draft_id in number,
        p_response in clob
    );

    -- Re-asks the controller what became of this draft's request and applies the
    -- answer. Sends nothing. Use it after a resume, or behind a Refresh button:
    -- an order number is recorded the moment it is reserved, so a run that
    -- stopped after that still has something worth collecting.
    procedure refresh_from_controller(p_draft_id in number);
end poc_style_pkg;
/

show errors

create or replace package body poc_style_pkg as

    e_not_editable exception;
    pragma exception_init(e_not_editable, -20960);

    -- Joins a head and a tail within a limit, trimming the *head* when it will
    -- not fit. The tail is the discriminator - the colour, or the size - and a
    -- description that loses it stops telling two styles apart, which is exactly
    -- what a plain substr on the whole string would do.
    function join_capped(
        p_head in varchar2,
        p_tail in varchar2,
        p_max  in pls_integer
    ) return varchar2 is
        l_tail varchar2(4000) := trim(p_tail);
        l_head varchar2(4000) := trim(p_head);
        l_room pls_integer;
    begin
        if l_tail is null then
            return substr(l_head, 1, p_max);
        end if;
        if l_head is null then
            return substr(l_tail, 1, p_max);
        end if;

        l_room := p_max - length(l_tail) - 1;
        if l_room <= 0 then
            return substr(l_tail, 1, p_max);
        end if;

        return trim(substr(l_head, 1, l_room)) || ' ' || l_tail;
    end;

    function compose_style_no(
        p_style_no    in varchar2,
        p_colour_code in varchar2
    ) return varchar2 is
    begin
        if p_style_no is null or p_colour_code is null then
            return null;
        end if;
        return trim(p_style_no) || trim(p_colour_code);
    end;

    function compose_style_desc(
        p_style_desc  in varchar2,
        p_colour_name in varchar2
    ) return varchar2 is
    begin
        -- 250 is items/create's limit for itemDescription.
        return join_capped(p_style_desc, p_colour_name, 250);
    end;

    function compose_sku_no(
        p_style_no    in varchar2,
        p_colour_code in varchar2,
        p_sku_size    in varchar2
    ) return varchar2 is
    begin
        if p_sku_size is null then
            return null;
        end if;
        return compose_style_no(p_style_no, p_colour_code) || trim(p_sku_size);
    end;

    function compose_sku_desc(
        p_style_desc  in varchar2,
        p_colour_name in varchar2,
        p_size_desc   in varchar2
    ) return varchar2 is
    begin
        return join_capped(compose_style_desc(p_style_desc, p_colour_name), p_size_desc, 250);
    end;

    -- A size differentiator's description, for the SKU description. Master data
    -- is the tenant's own list, which is why the console reads it rather than a
    -- local table.
    function size_desc(p_sku_size in varchar2) return varchar2 is
        l_desc varchar2(400);
    begin
        select max(description)
          into l_desc
          from master_data
         where data_type = 'DIFF_S'
           and data_code = p_sku_size;
        return nvl(l_desc, p_sku_size);
    end;

    function draft_status(p_draft_id in number) return varchar2 is
        l_status varchar2(30);
    begin
        select draft_status into l_status from poc_style_draft where draft_id = p_draft_id;
        return l_status;
    end;

    procedure require_status(p_draft_id in number, p_expected in varchar2) is
        l_status varchar2(30) := draft_status(p_draft_id);
    begin
        if l_status <> p_expected then
            raise_application_error(-20960,
                'Draft ' || p_draft_id || ' is ' || l_status
                || ', and this action needs it to be ' || p_expected || '.');
        end if;
    end;

    procedure refresh_composition(p_draft_id in number) is
        l_style_no varchar2(20);
        l_style_desc varchar2(250);
        l_colour_name varchar2(120);
        l_colour_code varchar2(10);
        l_origin varchar2(20);
    begin
        select d.origin, m.style_no, m.style_desc, c.colour_name, cc.colour_code
          into l_origin, l_style_no, l_style_desc, l_colour_name, l_colour_code
          from poc_style_draft d
          left join poc_style_model m on m.style_no = d.style_no
          left join poc_supplier_colour c on c.colour_id = d.colour_id
          left join poc_supplier_colour_code cc on cc.colour_code_id = d.colour_code_id
         where d.draft_id = p_draft_id;

        -- An amended draft carries numbers MFCS already assigned. Recomposing
        -- them would invent a different style than the one being amended.
        if l_origin = 'AMENDED' then
            return;
        end if;

        update poc_style_draft
           set composed_item_no = compose_style_no(l_style_no, l_colour_code),
               composed_item_desc = compose_style_desc(l_style_desc, l_colour_name),
               last_updated_at = systimestamp
         where draft_id = p_draft_id;

        for s in (select draft_sku_id, sku_size
                    from poc_style_draft_sku
                   where draft_id = p_draft_id) loop
            -- Composed in PL/SQL and bound in, not called from the update:
            -- size_desc is private to this body and SQL cannot see it.
            declare
                l_sku_no varchar2(25) := compose_sku_no(l_style_no, l_colour_code, s.sku_size);
                l_sku_desc varchar2(250) :=
                    compose_sku_desc(l_style_desc, l_colour_name, size_desc(s.sku_size));
            begin
                update poc_style_draft_sku
                   set composed_sku_no = l_sku_no,
                       composed_sku_desc = l_sku_desc
                 where draft_sku_id = s.draft_sku_id;
            end;
        end loop;
    end;

    -- The style-level attribute arrays. Each is omitted entirely when the draft
    -- captured none, so a document from this console is byte-identical to one
    -- written before these fields existed when nothing was captured.
    procedure add_attribute_arrays(p_doc in out nocopy json_object_t, p_draft_id in number) is
        l_arr json_array_t;
        l_row json_object_t;
    begin
        l_arr := json_array_t();
        for u in (select uda_id, uda_value, uda_text, uda_date
                    from poc_draft_uda where draft_id = p_draft_id order by uda_id) loop
            l_row := json_object_t();
            l_row.put('UDA_ID', u.uda_id);
            if u.uda_value is not null then l_row.put('UDA_VALUE', u.uda_value); end if;
            if u.uda_text  is not null then l_row.put('UDA_TEXT',  u.uda_text);  end if;
            if u.uda_date  is not null then
                l_row.put('UDA_DATE', to_char(u.uda_date, 'YYYY-MM-DD'));
            end if;
            l_arr.append(l_row);
        end loop;
        if l_arr.get_size > 0 then
            p_doc.put('STYLE_UDAS', l_arr);
        end if;

        l_arr := json_array_t();
        for s in (select season_id, phase_id, sequence_no
                    from poc_draft_season where draft_id = p_draft_id order by season_id) loop
            l_row := json_object_t();
            l_row.put('SEASON_ID', s.season_id);
            if s.phase_id is not null then l_row.put('PHASE_ID', s.phase_id); end if;
            if s.sequence_no is not null then l_row.put('SEQUENCE_NO', s.sequence_no); end if;
            l_arr.append(l_row);
        end loop;
        if l_arr.get_size > 0 then
            p_doc.put('STYLE_SEASONS', l_arr);
        end if;

        l_arr := json_array_t();
        for i in (select image_name, image_address, image_type, primary_yn, display_priority
                    from poc_draft_image where draft_id = p_draft_id order by draft_image_id) loop
            l_row := json_object_t();
            l_row.put('IMAGE_NAME', i.image_name);
            if i.image_address is not null then l_row.put('IMAGE_ADDRESS', i.image_address); end if;
            if i.image_type is not null then l_row.put('IMAGE_TYPE', i.image_type); end if;
            l_row.put('PRIMARY_YN', nvl(i.primary_yn, 'N'));
            if i.display_priority is not null then
                l_row.put('DISPLAY_PRIORITY', i.display_priority);
            end if;
            l_arr.append(l_row);
        end loop;
        if l_arr.get_size > 0 then
            p_doc.put('STYLE_IMAGES', l_arr);
        end if;

        l_arr := json_array_t();
        for h in (select hts, import_country, origin_country, effect_from, effect_to
                    from poc_draft_hts where draft_id = p_draft_id order by draft_hts_id) loop
            l_row := json_object_t();
            l_row.put('HTS', h.hts);
            if h.import_country is not null then l_row.put('IMPORT_COUNTRY', h.import_country); end if;
            if h.origin_country is not null then l_row.put('ORIGIN_COUNTRY', h.origin_country); end if;
            if h.effect_from is not null then
                l_row.put('EFFECT_FROM', to_char(h.effect_from, 'YYYY-MM-DD'));
            end if;
            if h.effect_to is not null then
                l_row.put('EFFECT_TO', to_char(h.effect_to, 'YYYY-MM-DD'));
            end if;
            l_arr.append(l_row);
        end loop;
        if l_arr.get_size > 0 then
            p_doc.put('STYLE_HTS', l_arr);
        end if;
    end;

    function build_document(p_draft_id in number) return clob is
        l_doc json_object_t := json_object_t();
        l_curve json_array_t := json_array_t();
        l_row json_object_t;
        l_upcs json_array_t;
        l_upc json_object_t;
        d poc_style_draft%rowtype;
    begin
        refresh_composition(p_draft_id);

        select * into d from poc_style_draft where draft_id = p_draft_id;

        l_doc.put('ACTION_REQUEST_ID', nvl(d.action_request_id,
            'POC-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3')));
        l_doc.put('OPERATION_NAME', d.operation_name);
        l_doc.put('SOURCE_SYSTEM', 'OFFICE_POC');
        l_doc.put('SOURCE_STYLE_REF', d.composed_item_desc);
        l_doc.put('SOURCE_VERSION', '1');
        l_doc.put('USER_ID', nvl(d.created_by, 'OFFICE_POC'));

        -- The composed number and description, and the type that makes MFCS
        -- accept the number. MANL is the only type a caller-chosen number can
        -- be: ITEM demands nine characters and a valid Oracle check digit.
        if d.origin = 'COMPOSED' then
            l_doc.put('ITEM_NUMBER', d.composed_item_no);
            l_doc.put('ITEM_NUMBER_TYPE', 'MANL');
        end if;
        l_doc.put('ITEM_DESCRIPTION', d.composed_item_desc);

        -- An amended draft addresses a style MFCS already holds.
        if d.style is not null then
            l_doc.put('STYLE', d.style);
        end if;

        l_doc.put('DEPARTMENT', d.department);
        l_doc.put('CLASS', d.class);
        l_doc.put('SUBCLASS', d.subclass);
        l_doc.put('SUPPLIER', to_char(d.supplier));
        l_doc.put('ORIGIN_COUNTRY', d.origin_country);
        l_doc.put('CURRENCY_CODE', d.currency_code);
        l_doc.put('UNIT_COST', d.unit_cost);
        l_doc.put('RETAIL_PRICE', d.retail_price);

        -- The MFCS colour differentiator, which is not the supplier colour. The
        -- diff defines the SKU and has to be one the tenant holds; the supplier
        -- colour composes the number and the description. Both travel, and
        -- conflating them would be easy and expensive.
        l_doc.put('COLOUR', d.mfcs_colour);

        -- The order half, present only when an order rides along.
        if d.operation_name in ('CREATE_ALL', 'MODIFY_ORDER') then
            l_doc.put('SOURCE_ORDER_REF', nvl(d.source_order_ref,
                'POC-ORDER-' || p_draft_id));
            if d.order_no is not null then
                l_doc.put('ORDER_NO', d.order_no);
            end if;
            l_doc.put('DELIVERY_LOC', d.delivery_loc);
            l_doc.put('IMPORT_COUNTRY', d.import_country);
            l_doc.put('NOT_BEFORE_DATE', to_char(d.not_before_date, 'YYYY-MM-DD'));
            l_doc.put('NOT_AFTER_DATE', to_char(d.not_after_date, 'YYYY-MM-DD'));
            l_doc.put('OTB_EOW_DATE', to_char(d.otb_eow_date, 'YYYY-MM-DD'));
            l_doc.put('EARLIEST_SHIP_DATE', to_char(d.earliest_ship_date, 'YYYY-MM-DD'));
            l_doc.put('LATEST_SHIP_DATE', to_char(d.latest_ship_date, 'YYYY-MM-DD'));
        end if;

        add_attribute_arrays(l_doc, p_draft_id);

        for s in (select draft_sku_id, sku_size, sku_qty, composed_sku_no, composed_sku_desc
                    from poc_style_draft_sku
                   where draft_id = p_draft_id
                   order by sku_size) loop
            l_row := json_object_t();
            l_row.put('SOURCE_VARIANT_REF', s.composed_sku_no);
            l_row.put('SKU_SIZE', s.sku_size);
            l_row.put('SKU_QTY', s.sku_qty);
            if d.origin = 'COMPOSED' then
                l_row.put('ITEM_NUMBER', s.composed_sku_no);
            else
                l_row.put('SKU_ID', s.composed_sku_no);
            end if;
            l_row.put('ITEM_DESCRIPTION', s.composed_sku_desc);

            l_upcs := json_array_t();
            for u in (select upc, upc_type, primary_yn
                        from poc_draft_sku_upc
                       where draft_sku_id = s.draft_sku_id
                       order by primary_yn desc, upc) loop
                l_upc := json_object_t();
                l_upc.put('UPC', u.upc);
                l_upc.put('UPC_TYPE', u.upc_type);
                l_upc.put('PRIMARY_YN', u.primary_yn);
                l_upcs.append(l_upc);
            end loop;
            if l_upcs.get_size > 0 then
                l_row.put('SKU_UPCS', l_upcs);
            end if;

            l_curve.append(l_row);
        end loop;
        l_doc.put('SIZE_CURVE_DETAIL', l_curve);

        return l_doc.to_clob;
    end;

    procedure validate_draft(
        p_draft_id    in number,
        o_http_status out number,
        o_response    out clob
    ) is
    begin
        api_pkg.validate_transaction(build_document(p_draft_id), o_http_status, o_response);
    end;

    procedure submit_for_review(
        p_draft_id    in number,
        p_submitted_by in varchar2,
        o_http_status out number,
        o_response    out clob
    ) is
        l_document clob;
        l_action_request_id varchar2(80);
    begin
        require_status(p_draft_id, 'DRAFT');

        -- Validate before freezing. A document frozen with a known fault is a
        -- review of something that cannot be sent, which wastes the reviewer.
        l_document := build_document(p_draft_id);
        api_pkg.validate_transaction(l_document, o_http_status, o_response);

        if o_http_status not between 200 and 299 then
            return;
        end if;

        -- The id is fixed here, before the document is frozen, so an approval
        -- and any later resume address one request rather than becoming several.
        select action_request_id into l_action_request_id
          from poc_style_draft where draft_id = p_draft_id;

        if l_action_request_id is null then
            l_action_request_id := 'POC-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
            update poc_style_draft
               set action_request_id = l_action_request_id
             where draft_id = p_draft_id;
            l_document := build_document(p_draft_id);
        end if;

        update poc_style_draft
           set request_payload = l_document,
               draft_status = 'SUBMITTED',
               submitted_by = p_submitted_by,
               submitted_at = systimestamp,
               last_updated_at = systimestamp
         where draft_id = p_draft_id;
        commit;
    end;

    procedure approve_draft(
        p_draft_id    in number,
        p_approved_by in varchar2,
        o_http_status out number,
        o_response    out clob
    ) is
        l_document clob;
    begin
        require_status(p_draft_id, 'SUBMITTED');

        -- The document frozen at submit, replayed. Not rebuilt: the approver
        -- approved what they were shown, and rebuilding here would send
        -- something else if anything underneath had moved.
        select request_payload into l_document
          from poc_style_draft where draft_id = p_draft_id;

        update poc_style_draft
           set draft_status = 'APPROVED',
               approved_by = p_approved_by,
               approved_at = systimestamp,
               last_updated_at = systimestamp
         where draft_id = p_draft_id;
        commit;

        api_pkg.submit_transaction(l_document, o_http_status, o_response);

        update poc_style_draft
           set response_payload = o_response,
               http_status = o_http_status,
               draft_status = case when o_http_status between 200 and 299
                                   then 'COMPLETED' else 'FAILED' end,
               last_updated_at = systimestamp
         where draft_id = p_draft_id;
        commit;

        -- Unconditionally, including on failure. A run that reserved an order
        -- number and then failed to create the order has still burned that
        -- number in MFCS, and the draft is the only place it can be tied back
        -- to what asked for it.
        apply_response(p_draft_id, o_response);
    end;

    procedure reopen_draft(p_draft_id in number) is
    begin
        if draft_status(p_draft_id) not in ('SUBMITTED', 'FAILED') then
            raise_application_error(-20960,
                'Only a submitted or failed draft can be reopened.');
        end if;

        update poc_style_draft
           set draft_status = 'DRAFT',
               request_payload = null,
               submitted_by = null,
               submitted_at = null,
               approved_by = null,
               approved_at = null,
               last_updated_at = systimestamp
         where draft_id = p_draft_id;
        commit;
    end;

    function seed_from_order(
        p_order_no in varchar2,
        p_user_id  in varchar2
    ) return number is
        l_order clob;
        l_style_doc clob;
        l_draft_id number;
        l_style varchar2(30);
        l_colour varchar2(60);
        l_style_desc varchar2(250);
    begin
        -- browse_pkg resolves what an order read does not carry: the parent style
        -- behind the SKUs on the detail lines, and each line's display size.
        l_order := browse_pkg.get_order(p_order_no, 'Y');

        -- browse_pkg puts what it worked out on "resolved": the parent style and
        -- colour at order level, and on each line the diffs and the SKU's own
        -- description. The order read itself carries none of that.
        select json_value(l_order, '$.items[0].resolved.style' returning varchar2(30) null on error),
               json_value(l_order, '$.items[0].resolved.colour' returning varchar2(60) null on error)
          into l_style, l_colour
          from dual;

        if l_style is null then
            raise_application_error(-20961,
                'MFCS returned no style behind order ' || p_order_no
                || ', so there is nothing to amend against.');
        end if;

        -- Read into locals first: INSERT ... SELECT cannot carry a RETURNING
        -- clause, and the draft id is needed to hang the size curve off.
        declare
            l_dept number;
            l_supplier number;
            l_currency varchar2(3);
            l_desc varchar2(250);
            l_loc number;
            l_import varchar2(3);
            l_nbd date; l_nad date; l_otb date; l_esd date; l_lsd date;
            -- Bound in as values, not called from the insert: a local function is
            -- invisible to SQL, which is what PLS-00231 means when it says so.
            function d(p_path in varchar2) return date is
                l_raw varchar2(30);
            begin
                l_raw := json_value(l_order, p_path returning varchar2(30) null on error);
                return to_date(substr(l_raw, 1, 10), 'YYYY-MM-DD');
            exception
                when others then return null;
            end;
        begin
            l_nbd := d('$.items[0].notBeforeDate');
            l_nad := d('$.items[0].notAfterDate');
            l_otb := d('$.items[0].otbEowDate');
            l_esd := d('$.items[0].earliestShipDate');
            l_lsd := d('$.items[0].latestShipDate');

            -- The order does not carry the style's description, so read the style.
            -- One extra call, on an amendment only, for a name the reviewer needs.
            l_style_doc := browse_pkg.get_style(l_style, 'N');
            l_style_desc := json_value(l_style_doc, '$.items[0].itemDescription'
                returning varchar2(250) null on error);

            select json_value(l_order, '$.items[0].dept' returning number null on error),
                   json_value(l_order, '$.items[0].supplier' returning number null on error),
                   json_value(l_order, '$.items[0].currencyCode' returning varchar2(3) null on error),
                   json_value(l_order, '$.items[0].resolved.styleDescription' returning varchar2(250) null on error),
                   -- physicalLocation, the physical warehouse the read reports. The
                -- mapper translates it to the virtual one on the way out, because
                -- MFCS refuses ranging against a physical location at level W.
                json_value(l_order, '$.items[0].details[0].physicalLocation' returning number null on error),
                   json_value(l_order, '$.items[0].importCountry' returning varchar2(3) null on error)
              into l_dept, l_supplier, l_currency, l_desc, l_loc, l_import
              from dual;

            insert into poc_style_draft (
                operation_name, origin, style, order_no, source_order_ref,
                department, supplier, currency_code, mfcs_colour,
                composed_item_no, composed_item_desc,
                not_before_date, not_after_date, otb_eow_date,
                earliest_ship_date, latest_ship_date, delivery_loc, import_country,
                created_by, draft_status
            ) values (
                'MODIFY_ORDER', 'AMENDED', l_style, p_order_no,
                'POC-AMEND-' || p_order_no,
                l_dept, l_supplier, l_currency, l_colour,
                l_style, nvl(l_style_desc, nvl(l_desc, 'Order ' || p_order_no)),
                l_nbd, l_nad, l_otb, l_esd, l_lsd,
                l_loc, l_import,
                p_user_id, 'DRAFT'
            ) returning draft_id into l_draft_id;
        end;

        -- The order's own lines become the size curve. Quantity is the thing an
        -- amendment is usually about, which is why the review stage leaves it
        -- editable when everything else is frozen.
        insert into poc_style_draft_sku (draft_id, sku_size, sku_qty, composed_sku_no, composed_sku_desc)
        select l_draft_id,
               nvl(d.size_diff, d.item),
               nvl(d.qty, 1),
               d.item,
               d.item_desc
          from json_table(l_order, '$.items[0].details[*]'
              columns
                  item      varchar2(30)  path '$.item',
                  -- Read gives physicalQuantityOrdered where write wants
                  -- quantityOrdered; this is the read.
                  qty       number        path '$.physicalQuantityOrdered',
                  item_desc varchar2(250) path '$.resolved.itemDescription',
                  size_diff varchar2(60)  path '$.resolved.diff2'
          ) d
         where d.item is not null;

        commit;
        return l_draft_id;
    end;

    procedure apply_response(
        p_draft_id in number,
        p_response in clob
    ) is
        l_style varchar2(30);
        l_order varchar2(30);
    begin
        if p_response is null then
            return;
        end if;

        -- STYLE and ORDER_NO come from request_pkg.build_status_response, which
        -- reads REQUEST rather than any one call's reply. ORDER_NO is therefore
        -- present from RESERVE_ORDER_NUMBER onwards, whatever happened after it.
        select json_value(p_response, '$.STYLE' returning varchar2(30) null on error),
               json_value(p_response, '$.ORDER_NO' returning varchar2(30) null on error)
          into l_style, l_order
          from dual;

        -- coalesce, never overwrite with null: a resume or a refresh that comes
        -- back before the order number exists must not erase one already held,
        -- and on a MODIFY_ORDER draft the order number was an input.
        update poc_style_draft
           set style = coalesce(l_style, style),
               order_no = coalesce(l_order, order_no),
               last_updated_at = systimestamp
         where draft_id = p_draft_id;

        -- SIZE_CURVE_DETAIL keys back on SOURCE_VARIANT_REF, which build_document
        -- sets to the composed SKU number. That is what makes the match exact
        -- rather than positional - a size curve can gain or lose rows between
        -- one request and the next.
        for r in (
            select variant_ref, sku_id
              from json_table(p_response, '$.SIZE_CURVE_DETAIL[*]'
                  columns
                      variant_ref varchar2(30) path '$.SOURCE_VARIANT_REF',
                      sku_id      varchar2(30) path '$.SKU_ID')
             where sku_id is not null
        ) loop
            update poc_style_draft_sku
               set mfcs_sku_no = r.sku_id
             where draft_id = p_draft_id
               and composed_sku_no = r.variant_ref;
        end loop;

        commit;
    exception
        -- A draft that cannot read its response is still a draft that sent one.
        -- Losing the identifiers is a reporting problem; raising here would turn
        -- a completed MFCS run into a failed-looking one, which is worse.
        when others then
            rollback;
    end;

    procedure refresh_from_controller(p_draft_id in number) is
        l_action_request_id varchar2(80);
        l_status number;
        l_response clob;
    begin
        select action_request_id into l_action_request_id
          from poc_style_draft where draft_id = p_draft_id;

        if l_action_request_id is null then
            return;  -- Never submitted; there is nothing to ask about.
        end if;

        api_pkg.get_transaction(l_action_request_id, l_status, l_response);

        if l_status = 200 then
            update poc_style_draft
               set response_payload = l_response,
                   http_status = l_status,
                   -- Promoted to COMPLETED, never demoted. A run that finished
                   -- after a resume should say so; one still in progress must
                   -- not be called failed just because it has not finished, and
                   -- approve_draft already records a genuine failure.
                   draft_status = case
                       when json_value(l_response, '$.STATUS') = 'COMPLETED'
                       then 'COMPLETED' else draft_status end,
                   last_updated_at = systimestamp
             where draft_id = p_draft_id;
            commit;

            apply_response(p_draft_id, l_response);
        end if;
    end;
end poc_style_pkg;
/

show errors

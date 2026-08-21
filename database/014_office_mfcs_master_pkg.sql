set define off

prompt Creating OFFICE MFCS master-data package

create or replace package office_mfcs_master_pkg authid definer as
    -- Reads MFCS foundation data into OFFICE_MFCS_MASTER_DATA so the console can
    -- offer dropdowns without a round trip per keystroke, and pass-through readers
    -- for browsing live styles and orders.

    procedure refresh_all(o_summary out clob);

    -- Live pass-through reads. These are not cached: a browse screen should show
    -- what MFCS holds right now.
    function list_styles(
        p_limit      in number default 50,
        p_dept       in varchar2 default null,
        p_item_level in varchar2 default '1'
    ) return clob;

    function list_orders(
        p_limit    in number default 50,
        p_supplier in varchar2 default null
    ) return clob;

    -- Decodes the stored bearer token's JWT claims so an expired credential is
    -- diagnosable without leaving the database. Never returns the token itself.
    function token_status return clob;

    function get_style(p_item in varchar2) return clob;

    -- p_enrich resolves what an order read does not carry but a MODIFY_ORDER
    -- request needs: the parent style behind the SKUs on the detail lines, and
    -- each line's display size (reverse-mapped from its MFCS size diff through
    -- MAP.SIZE.*). Adds an "officeMfcs" object at the root and on each line.
    function get_order(
        p_order_no in varchar2,
        p_enrich   in varchar2 default 'Y'
    ) return clob;
end office_mfcs_master_pkg;
/

show errors

create or replace package body office_mfcs_master_pkg as

    -- Deliberately NOT cached in a package global. ORDS pools database sessions,
    -- so a session that once read an expired token would keep replaying it for
    -- the life of that session, giving intermittent 401s that follow no pattern
    -- from the caller's point of view. A single indexed lookup per call is
    -- cheap; being wrong about a credential is not.
    function bearer return varchar2 is
        l_ref varchar2(200);
        l_token varchar2(32767);
    begin
        l_ref := office_mfcs_request_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
        select dbms_lob.substr(secret_value, 32767, 1) into l_token
          from office_mfcs_secret where secret_ref = l_ref;
        l_token := trim(l_token);
        if lower(substr(l_token, 1, 7)) = 'bearer ' then
            l_token := trim(substr(l_token, 8));
        end if;
        return l_token;
    exception
        when no_data_found then
            raise_application_error(-20890,
                'MFCS bearer token is not configured in OFFICE_MFCS_SECRET under ref ' || l_ref || '.');
    end;

    function token_status return clob is
        l_root json_object_t := json_object_t();
        l_ref varchar2(200);
        l_token varchar2(32767);
        l_seg varchar2(32767);
        l_json varchar2(32767);
        l_claims json_object_t;
        l_exp number;
        l_iat number;
        l_now number;
    begin
        l_ref := office_mfcs_request_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
        l_root.put('secretRef', l_ref);

        begin
            select dbms_lob.substr(secret_value, 32767, 1) into l_token
              from office_mfcs_secret where secret_ref = l_ref;
        exception
            when no_data_found then
                l_root.put('present', false);
                l_root.put('message', 'No row in OFFICE_MFCS_SECRET under ref ' || l_ref || '.');
                return l_root.to_clob;
        end;

        l_token := trim(l_token);
        if lower(substr(l_token, 1, 7)) = 'bearer ' then
            l_token := trim(substr(l_token, 8));
        end if;

        l_root.put('present', true);
        l_root.put('length', length(l_token));
        l_root.put('segments', length(l_token) - length(replace(l_token, '.', '')) + 1);

        -- Middle JWT segment, base64url-decoded.
        l_seg := regexp_substr(l_token, '[^.]+', 1, 2);
        if l_seg is null then
            l_root.put('message', 'Not a JWT; cannot read expiry.');
            return l_root.to_clob;
        end if;

        l_seg := replace(replace(l_seg, '-', '+'), '_', '/');
        l_seg := l_seg || rpad('=', mod(4 - mod(length(l_seg), 4), 4), '=');

        begin
            l_json := utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(l_seg)));
            l_claims := json_object_t.parse(l_json);
            l_exp := l_claims.get_number('exp');
            l_iat := l_claims.get_number('iat');
        exception
            when others then
                l_root.put('message', 'Could not decode JWT claims: ' || substr(sqlerrm, 1, 200));
                return l_root.to_clob;
        end;

        l_now := (cast(systimestamp at time zone 'UTC' as date) - date '1970-01-01') * 86400;

        if l_iat is not null then
            l_root.put('issuedAt', to_char(date '1970-01-01' + l_iat / 86400, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
        end if;
        if l_exp is not null then
            l_root.put('expiresAt', to_char(date '1970-01-01' + l_exp / 86400, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
            l_root.put('expired', l_exp < l_now);
            l_root.put('secondsRemaining', round(l_exp - l_now));
            l_root.put('message',
                case when l_exp < l_now
                     then 'Token expired ' || round((l_now - l_exp) / 60) || ' minute(s) ago. Re-issue it in Postman.'
                     else 'Token valid for a further ' || round((l_exp - l_now) / 60) || ' minute(s).'
                end);
        end if;

        return l_root.to_clob;
    end;

    function http_get(p_path in varchar2, o_status out number) return clob is
        l_response clob;
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || bearer;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';
        apex_web_service.g_request_headers(3).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(3).value := lower(rawtohex(sys_guid()));

        l_response := apex_web_service.make_rest_request(
            p_url => rtrim(office_mfcs_request_pkg.get_config('MFCS_BASE_URL'), '/') || p_path,
            p_http_method => 'GET',
            p_transfer_timeout => to_number(office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );
        o_status := apex_web_service.g_status_code;
        return l_response;
    end;

    procedure upsert(
        p_type   in varchar2,
        p_code   in varchar2,
        p_parent in varchar2,
        p_desc   in varchar2,
        p_attrs  in clob,
        p_source in varchar2
    ) is
    begin
        if p_code is null then
            return;
        end if;
        merge into office_mfcs_master_data d
        using (select p_type dt, p_code dc, nvl(p_parent, '~') pc from dual) s
        on (d.data_type = s.dt and d.data_code = s.dc and d.parent_code = s.pc)
        when matched then update set
            d.description = nvl(p_desc, d.description),
            d.attributes = nvl(p_attrs, d.attributes),
            d.source = p_source,
            d.refreshed_at = systimestamp
        when not matched then insert (data_type, data_code, parent_code, description, attributes, source)
        values (s.dt, s.dc, s.pc, p_desc, p_attrs, p_source);
    end;

    procedure log_refresh(
        p_type in varchar2,
        p_source in varchar2,
        p_status in number,
        p_rows in number,
        p_message in varchar2,
        p_started in timestamp with time zone
    ) is
    begin
        merge into office_mfcs_master_refresh r
        using (select p_type dt from dual) s
        on (r.data_type = s.dt)
        when matched then update set
            r.source = p_source, r.http_status = p_status, r.row_count = p_rows,
            r.message = p_message, r.started_at = p_started, r.completed_at = systimestamp
        when not matched then insert (data_type, source, http_status, row_count, message, started_at, completed_at)
        values (p_type, p_source, p_status, p_rows, p_message, p_started, systimestamp);
    end;

    -- Reads a foundation service straight into the cache.
    procedure load_direct(
        p_type       in varchar2,
        p_path       in varchar2,
        p_code_field in varchar2,
        p_desc_field in varchar2,
        p_limit      in number default 500
    ) is
        l_status number;
        l_body clob;
        l_items json_array_t;
        l_row json_object_t;
        l_count number := 0;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'ENDPOINT:' || p_path;
    begin
        l_body := http_get(p_path || '?limit=' || p_limit, l_status);
        if l_status not between 200 and 299 then
            log_refresh(p_type, l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        l_items := json_object_t.parse(l_body).get_array('items');
        for i in 0 .. l_items.get_size - 1 loop
            l_row := treat(l_items.get(i) as json_object_t);
            upsert(
                p_type => p_type,
                p_code => l_row.get_string(p_code_field),
                p_parent => null,
                p_desc => l_row.get_string(p_desc_field),
                p_attrs => l_row.to_clob,
                p_source => l_source
            );
            l_count := l_count + 1;
        end loop;

        log_refresh(p_type, l_source, l_status, l_count,
            case when l_count = 0 then 'Service returned no rows (empty publish queue).' else null end,
            l_started);
    exception
        when others then
            log_refresh(p_type, l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- Recovers hierarchy, differentiator and supplier values from the item feed,
    -- because the dedicated foundation services are empty on this tenant.
    procedure harvest_from_items(p_pages in number default 10, p_limit in number default 200) is
        l_status number;
        l_body clob;
        l_root json_object_t;
        l_items json_array_t;
        l_it json_object_t;
        l_sups json_array_t;
        l_sup json_object_t;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'DERIVED:/services/foundation/item';
        l_path varchar2(400);
        l_offset varchar2(200);
        l_items_seen number := 0;
        l_more boolean := true;
        l_page number := 0;
        l_dept varchar2(120);
        l_class varchar2(120);
    begin
        while l_more and l_page < p_pages loop
            l_page := l_page + 1;
            l_path := '/MerchIntegrations/services/foundation/item?limit=' || p_limit;
            if l_offset is not null then
                l_path := l_path || '&offsetkey=' || l_offset;
            end if;

            l_body := http_get(l_path, l_status);
            exit when l_status not between 200 and 299;

            l_root := json_object_t.parse(l_body);
            l_items := l_root.get_array('items');
            exit when l_items is null or l_items.get_size = 0;

            for i in 0 .. l_items.get_size - 1 loop
                l_it := treat(l_items.get(i) as json_object_t);
                l_items_seen := l_items_seen + 1;
                l_offset := l_it.get_string('item');

                l_dept := to_char(l_it.get_number('dept'));
                l_class := to_char(l_it.get_number('class'));

                upsert('DEPARTMENT', l_dept, null, l_it.get_string('deptName'), null, l_source);
                upsert('CLASS', l_class, l_dept, l_it.get_string('className'), null, l_source);
                upsert('SUBCLASS', to_char(l_it.get_number('subclass')),
                       l_dept || '.' || l_class, l_it.get_string('subclassName'), null, l_source);

                -- diff1/diff2 carry their own type flag (C = colour, S = size).
                if l_it.get_string('diff1') is not null then
                    upsert('DIFF_' || nvl(l_it.get_string('diff1Type'), 'X'),
                           l_it.get_string('diff1'), null, null, null, l_source);
                end if;
                if l_it.get_string('diff2') is not null then
                    upsert('DIFF_' || nvl(l_it.get_string('diff2Type'), 'X'),
                           l_it.get_string('diff2'), null, null, null, l_source);
                end if;

                if l_it.get_string('standardUom') is not null then
                    upsert('UOM', l_it.get_string('standardUom'), null, null, null, l_source);
                end if;

                begin
                    l_sups := l_it.get_array('supplier');
                    if l_sups is not null then
                        for j in 0 .. l_sups.get_size - 1 loop
                            l_sup := treat(l_sups.get(j) as json_object_t);
                            upsert('SUPPLIER', to_char(l_sup.get_number('supplier')), null,
                                   l_sup.get_string('supplierName'), l_sup.to_clob, l_source);
                        end loop;
                    end if;
                exception when others then null;
                end;
            end loop;

            l_more := nvl(l_root.get_string('hasMore'), 'false') = 'true';
        end loop;

        log_refresh('DERIVED_FROM_ITEMS', l_source, l_status, l_items_seen,
            'Scanned ' || l_items_seen || ' items across ' || l_page || ' page(s).', l_started);
    exception
        when others then
            log_refresh('DERIVED_FROM_ITEMS', l_source, l_status, l_items_seen, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- Order feed supplies the location values the warehouse/store services do not.
    procedure harvest_from_orders(p_limit in number default 200) is
        l_status number;
        l_body clob;
        l_items json_array_t;
        l_o json_object_t;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'DERIVED:/services/procurement/order';
        l_seen number := 0;
    begin
        l_body := http_get('/MerchIntegrations/services/procurement/order?limit=' || p_limit, l_status);
        if l_status not between 200 and 299 then
            log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        l_items := json_object_t.parse(l_body).get_array('items');
        for i in 0 .. l_items.get_size - 1 loop
            l_o := treat(l_items.get(i) as json_object_t);
            l_seen := l_seen + 1;
            upsert('SUPPLIER', to_char(l_o.get_number('supplier')), null, null, null, l_source);
            upsert('CURRENCY', l_o.get_string('currencyCode'), null, null, null, l_source);
            if l_o.get_number('virtualWarehouse') is not null then
                upsert('LOCATION_W', to_char(l_o.get_number('virtualWarehouse')), null,
                       'Virtual warehouse', null, l_source);
            end if;
            if l_o.get_number('physicalLocation') is not null then
                upsert('LOCATION_P', to_char(l_o.get_number('physicalLocation')), null,
                       'Physical location', null, l_source);
            end if;
            if l_o.get_string('terms') is not null then
                upsert('TERMS', l_o.get_string('terms'), null, l_o.get_string('termsCode'), null, l_source);
            end if;
        end loop;

        log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, l_seen,
            'Scanned ' || l_seen || ' orders.', l_started);
    exception
        when others then
            log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, l_seen, substr(sqlerrm, 1, 1000), l_started);
    end;

    procedure refresh_all(o_summary out clob) is
        l_root json_object_t := json_object_t();
        l_arr json_array_t := json_array_t();
        l_row json_object_t;
    begin
        -- Services that return rows on this tenant.
        load_direct('BRAND', '/MerchIntegrations/services/item/brands', 'brandName', 'brandDescription');
        load_direct('SEASON', '/MerchIntegrations/services/item/foundation/seasons', 'season', 'description');
        load_direct('ORG_HIER', '/MerchIntegrations/services/foundation/orghier', 'hierarchyId', 'hierarchyName');

        -- Attempted anyway, so the refresh log records that they are still empty
        -- rather than leaving it a mystery.
        load_direct('DEPARTMENT_SVC', '/MerchIntegrations/services/foundation/merchhier/deps', 'dept', 'deptName');
        load_direct('DIFF_SVC', '/MerchIntegrations/services/foundation/diffid', 'diffId', 'diffDesc');
        load_direct('SUPPLIER_SVC', '/MerchIntegrations/services/foundation/supplier', 'supplier', 'supplierName');
        load_direct('UDA_SVC', '/MerchIntegrations/services/foundation/uda', 'udaId', 'udaDesc');
        load_direct('WAREHOUSE_SVC', '/MerchIntegrations/services/foundation/warehouse', 'wh', 'whName');
        load_direct('STORE_SVC', '/MerchIntegrations/services/foundation/store', 'store', 'storeName');

        harvest_from_items;
        harvest_from_orders;
        commit;

        for r in (
            select m.data_type, count(*) cnt, max(m.source) src,
                   to_char(max(m.refreshed_at), 'YYYY-MM-DD"T"HH24:MI:SS') last_refresh
              from office_mfcs_master_data m
             group by m.data_type
             order by m.data_type
        ) loop
            l_row := json_object_t();
            l_row.put('dataType', r.data_type);
            l_row.put('count', r.cnt);
            l_row.put('source', r.src);
            l_row.put('refreshedAt', r.last_refresh);
            l_arr.append(l_row);
        end loop;
        l_root.put('cached', l_arr);

        l_arr := json_array_t();
        for r in (
            select data_type, source, http_status, row_count, message,
                   to_char(completed_at, 'YYYY-MM-DD"T"HH24:MI:SS') completed
              from office_mfcs_master_refresh order by data_type
        ) loop
            l_row := json_object_t();
            l_row.put('dataType', r.data_type);
            l_row.put('source', r.source);
            l_row.put('httpStatus', r.http_status);
            l_row.put('rowCount', r.row_count);
            l_row.put('message', r.message);
            l_row.put('completedAt', r.completed);
            l_arr.append(l_row);
        end loop;
        l_root.put('log', l_arr);

        o_summary := l_root.to_clob;
    end;

    function list_styles(
        p_limit      in number default 50,
        p_dept       in varchar2 default null,
        p_item_level in varchar2 default '1'
    ) return clob is
        l_status number;
        l_path varchar2(600);
    begin
        l_path := '/MerchIntegrations/services/foundation/item?limit=' || nvl(p_limit, 50);
        if p_item_level is not null then
            l_path := l_path || '&itemLevel=' || p_item_level;
        end if;
        if p_dept is not null then
            l_path := l_path || '&deptId=' || p_dept;
        end if;
        return http_get(l_path, l_status);
    end;

    function list_orders(
        p_limit    in number default 50,
        p_supplier in varchar2 default null
    ) return clob is
        l_status number;
        l_path varchar2(600);
    begin
        l_path := '/MerchIntegrations/services/procurement/order?limit=' || nvl(p_limit, 50);
        if p_supplier is not null then
            l_path := l_path || '&supplier=' || p_supplier;
        end if;
        return http_get(l_path, l_status);
    end;

    function get_style(p_item in varchar2) return clob is
        l_status number;
    begin
        return http_get('/MerchIntegrations/services/foundation/item/' || p_item, l_status);
    end;

    -- Given an MFCS size diff such as 070, recover the display size (7) by
    -- reversing the MAP.SIZE.* configuration the mapper uses on the way out.
    function display_size(p_diff in varchar2) return varchar2 is
        l_code varchar2(120);
    begin
        if p_diff is null then
            return null;
        end if;
        select substr(config_key, length('MAP.SIZE.') + 1)
          into l_code
          from office_mfcs_config
         where config_key like 'MAP.SIZE.%'
           and environment = 'DEFAULT'
           and enabled_ind = 'Y'
           and dbms_lob.substr(config_value, 400, 1) = p_diff
           and rownum = 1;
        return l_code;
    exception
        when no_data_found then return null;
    end;

    function get_order(
        p_order_no in varchar2,
        p_enrich   in varchar2 default 'Y'
    ) return clob is
        l_status number;
        l_body clob;
        l_root json_object_t;
        l_orders json_array_t;
        l_order json_object_t;
        l_details json_array_t;
        l_line json_object_t;
        l_item_body clob;
        l_item json_object_t;
        l_meta json_object_t;
        l_order_meta json_object_t;
        l_style varchar2(30);
        l_colour varchar2(120);
    begin
        l_body := http_get('/MerchIntegrations/services/procurement/order/' || p_order_no, l_status);
        if nvl(p_enrich, 'Y') <> 'Y' or l_status not between 200 and 299 then
            return l_body;
        end if;

        l_root := json_object_t.parse(l_body);
        l_orders := l_root.get_array('items');
        if l_orders is null or l_orders.get_size = 0 then
            return l_body;
        end if;

        l_order := treat(l_orders.get(0) as json_object_t);
        l_details := l_order.get_array('details');
        if l_details is null then
            return l_body;
        end if;

        for i in 0 .. l_details.get_size - 1 loop
            l_line := treat(l_details.get(i) as json_object_t);
            begin
                l_item_body := http_get(
                    '/MerchIntegrations/services/foundation/item/' || l_line.get_string('item'),
                    l_status);
                if l_status between 200 and 299 then
                    l_item := treat(json_object_t.parse(l_item_body).get_array('items').get(0) as json_object_t);
                    l_meta := json_object_t();
                    l_meta.put('itemParent', l_item.get_string('itemParent'));
                    l_meta.put('diff1', l_item.get_string('diff1'));
                    l_meta.put('diff2', l_item.get_string('diff2'));
                    l_meta.put('displaySize', display_size(l_item.get_string('diff2')));
                    l_meta.put('itemDescription', l_item.get_string('itemDescription'));
                    l_line.put('officeMfcs', l_meta);

                    if l_style is null then
                        l_style := l_item.get_string('itemParent');
                    end if;
                    if l_colour is null then
                        l_colour := l_item.get_string('diff1');
                    end if;
                end if;
            exception
                when others then null;
            end;
        end loop;

        l_order_meta := json_object_t();
        l_order_meta.put('style', l_style);
        l_order_meta.put('colour', l_colour);
        l_order_meta.put('enriched', true);
        l_order.put('officeMfcs', l_order_meta);

        return l_root.to_clob;
    end;
end office_mfcs_master_pkg;
/

show errors

prompt OFFICE MFCS master-data package created

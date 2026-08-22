set define off

-- Live style and order reads for the console's browse screen.
--
-- Deliberately uncached: a browse screen should show current tenant state.

prompt Creating browse_pkg

create or replace package browse_pkg authid definer as
    function list_styles(
        p_limit      in number default 50,
        p_dept       in varchar2 default null,
        p_item_level in varchar2 default '1'
    ) return clob;

    function list_orders(
        p_limit    in number default 50,
        p_supplier in varchar2 default null
    ) return clob;

    -- p_with_skus attaches the style's child SKUs under resolved.skus.
    --
    -- The MerchIntegrations item service cannot do this: it has no itemParent
    -- filter, its response schema carries no child collection (itemParent and
    -- itemGrandparent point upward, referenceItem holds level-3 UPCs), and no
    -- child-item service exists among its 90 GET paths.
    --
    -- The tenant also serves an older API family that is absent from the
    -- MerchIntegrations OpenAPI document:
    --
    --   GET /RmsReSTServices/services/private/Item/itemDetail?item=<style>
    --
    -- which returns the style together with its children in a single call. That
    -- is used first. It carries fewer fields than the MerchIntegrations read, so
    -- each child is then fetched in full for the detail regions.
    --
    -- Because that service is undocumented for this tenant, a scan of the item
    -- feed remains as a fallback. resolved.source records which path was taken.
    function get_style(
        p_item      in varchar2,
        p_with_skus in varchar2 default 'N'
    ) return clob;

    -- p_enrich resolves what an order read does not carry but a MODIFY_ORDER
    -- request needs: the parent style behind the SKUs on the detail lines, and
    -- each line's display size, reverse-mapped from its MFCS size diff through
    -- MAP.SIZE.*. Adds an "resolved" object at the root and on each line.
    --
    -- Without it a browsed order fails validation on STYLE_REQUIRED_OR_RESOLVABLE
    -- and MAPPING_NOT_FOUND.
    function get_order(
        p_order_no in varchar2,
        p_enrich   in varchar2 default 'Y'
    ) return clob;
end browse_pkg;
/

show errors

create or replace package body browse_pkg as

    -- Upstream failures must not be served to the console as HTTP 200 with an
    -- HTML body. MFCS answers an expired token with an HTML 401 page; passing
    -- that through untouched makes a dead credential look like an endpoint that
    -- works and simply has no data, which is exactly the wrong diagnosis.
    function passthrough(p_path in varchar2) return clob is
        l_status number;
        l_body clob;
        l_err json_object_t;
    begin
        l_body := client_pkg.get_json(p_path, l_status);
        if l_status between 200 and 299 then
            return l_body;
        end if;
        l_err := json_object_t();
        l_err.put('error', 'MFCS returned HTTP ' || l_status);
        l_err.put('httpStatus', l_status);
        l_err.put('path', p_path);
        l_err.put('hint', case when l_status = 401
                               then 'The bearer token is rejected - it has most likely expired.'
                               else 'See detail for what MFCS reported.' end);
        l_err.put('detail', substr(dbms_lob.substr(l_body, 900, 1), 1, 900));
        l_err.put('items', json_array_t());
        return l_err.to_clob;
    end;

    function display_size(p_diff in varchar2) return varchar2 is
        l_code varchar2(120);
    begin
        if p_diff is null then
            return null;
        end if;
        select substr(config_key, length('MAP.SIZE.') + 1)
          into l_code
          from config
         where config_key like 'MAP.SIZE.%'
           and environment = 'DEFAULT'
           and enabled_ind = 'Y'
           and dbms_lob.substr(config_value, 400, 1) = p_diff
           and rownum = 1;
        return l_code;
    exception
        when no_data_found then return null;
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
        return passthrough(l_path);
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
        return passthrough(l_path);
    end;

    -- Child item numbers for a style, via the RmsReSTServices item hierarchy read.
    -- Returns an empty collection if the service is unavailable, so the caller can
    -- fall back.
    function child_numbers_via_item_detail(
        p_item   in varchar2,
        o_ok     out boolean
    ) return apex_t_varchar2 is
        l_status number;
        l_body clob;
        l_arr json_array_t;
        l_row json_object_t;
        l_out apex_t_varchar2 := apex_t_varchar2();
    begin
        o_ok := false;
        l_body := client_pkg.get_json(
            '/RmsReSTServices/services/private/Item/itemDetail?item=' || p_item, l_status);
        if l_status not between 200 and 299 then
            return l_out;
        end if;

        l_arr := json_array_t.parse(l_body);
        o_ok := true;
        for i in 0 .. l_arr.get_size - 1 loop
            l_row := treat(l_arr.get(i) as json_object_t);
            -- The array is not ordered parent-first, so match on the relationship
            -- rather than on position.
            if l_row.get_string('itemParent') = p_item then
                apex_string.push(l_out, l_row.get_string('item'));
            end if;
        end loop;
        return l_out;
    exception
        when others then
            o_ok := false;
            return apex_t_varchar2();
    end;

    -- Fallback: page the item feed and match itemParent. Projects only the two
    -- fields the match needs via the include parameter, which takes a 200-row page
    -- from roughly 1.1MB to 30KB.
    function child_numbers_via_scan(
        p_item      in varchar2,
        p_dept      in number,
        o_scanned   out pls_integer,
        o_truncated out boolean
    ) return apex_t_varchar2 is
        c_max_pages constant pls_integer := 25;
        c_page_size constant pls_integer := 500;
        l_status number;
        l_body clob;
        l_feed json_object_t;
        l_items json_array_t;
        l_row json_object_t;
        l_out apex_t_varchar2 := apex_t_varchar2();
        l_page pls_integer := 0;
        l_more boolean := true;
        l_offset varchar2(200);
        l_path varchar2(1000);
    begin
        o_scanned := 0;
        while l_more and l_page < c_max_pages loop
            l_page := l_page + 1;
            l_path := '/MerchIntegrations/services/foundation/item?itemLevel=2&limit='
                   || c_page_size || '&include=items.item,items.itemParent';
            if p_dept is not null then
                l_path := l_path || '&deptId=' || p_dept;
            end if;
            if l_offset is not null then
                l_path := l_path || '&offsetkey=' || l_offset;
            end if;

            l_body := client_pkg.get_json(l_path, l_status);
            exit when l_status not between 200 and 299;

            l_feed := json_object_t.parse(l_body);
            l_items := l_feed.get_array('items');
            exit when l_items is null or l_items.get_size = 0;

            for i in 0 .. l_items.get_size - 1 loop
                l_row := treat(l_items.get(i) as json_object_t);
                l_offset := l_row.get_string('item');
                o_scanned := o_scanned + 1;
                if l_row.get_string('itemParent') = p_item then
                    apex_string.push(l_out, l_row.get_string('item'));
                end if;
            end loop;

            l_more := nvl(l_feed.get_string('hasMore'), 'false') = 'true';
        end loop;
        o_truncated := l_page >= c_max_pages and l_more;
        return l_out;
    end;

    function get_style(
        p_item      in varchar2,
        p_with_skus in varchar2 default 'N'
    ) return clob is
        l_status number;
        l_body clob;
        l_root json_object_t;
        l_items json_array_t;
        l_style json_object_t;
        l_dept number;
        l_meta json_object_t;
        l_numbers apex_t_varchar2;
        l_skus json_array_t := json_array_t();
        l_ok boolean;
        l_scanned pls_integer := 0;
        l_truncated boolean := false;
        l_source varchar2(60);
        l_child_body clob;
        l_child_items json_array_t;
    begin
        l_body := passthrough('/MerchIntegrations/services/foundation/item/' || p_item);

        if nvl(p_with_skus, 'N') <> 'Y'
           or json_object_t.parse(l_body).has('error') then
            return l_body;
        end if;

        l_root := json_object_t.parse(l_body);
        l_items := l_root.get_array('items');
        if l_items is null or l_items.get_size = 0 then
            return l_body;
        end if;
        l_style := treat(l_items.get(0) as json_object_t);

        if nvl(l_style.get_number('itemLevel'), 1) <> 1 then
            l_meta := json_object_t();
            l_meta.put('skus', json_array_t());
            l_meta.put('skuCount', 0);
            l_meta.put('source', 'none');
            l_meta.put('note', 'Not a parent item.');
            l_style.put('resolved', l_meta);
            return l_root.to_clob;
        end if;

        l_dept := l_style.get_number('dept');

        l_numbers := child_numbers_via_item_detail(p_item, l_ok);
        if l_ok then
            l_source := 'itemDetail';
        else
            l_numbers := child_numbers_via_scan(p_item, l_dept, l_scanned, l_truncated);
            l_source := 'feed scan';
        end if;

        -- itemDetail carries a thinner document than the MerchIntegrations read,
        -- so fetch each child in full for the supplier, country and UDA regions.
        for i in 1 .. l_numbers.count loop
            l_child_body := client_pkg.get_json(
                '/MerchIntegrations/services/foundation/item/' || l_numbers(i), l_status);
            if l_status between 200 and 299 then
                l_child_items := json_object_t.parse(l_child_body).get_array('items');
                if l_child_items is not null and l_child_items.get_size > 0 then
                    l_skus.append(treat(l_child_items.get(0) as json_object_t));
                end if;
            end if;
        end loop;

        l_meta := json_object_t();
        l_meta.put('skus', l_skus);
        l_meta.put('skuCount', l_skus.get_size);
        l_meta.put('source', l_source);
        l_meta.put('truncated', l_truncated);
        if l_source = 'itemDetail' then
            l_meta.put('note',
                'Children read from RmsReSTServices Item/itemDetail, which returns a '
                || 'style together with its children in one call.');
        else
            l_meta.put('itemsScanned', l_scanned);
            l_meta.put('note',
                'itemDetail was unavailable, so children were found by scanning the '
                || 'item feed. A SKU that is not approved and published will not appear.');
        end if;
        l_style.put('resolved', l_meta);

        return l_root.to_clob;
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
        l_body := passthrough('/MerchIntegrations/services/procurement/order/' || p_order_no);
        if nvl(p_enrich, 'Y') <> 'Y'
           or json_object_t.parse(l_body).has('error') then
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
                l_item_body := client_pkg.get_json(
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
                    l_line.put('resolved', l_meta);

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
        l_order.put('resolved', l_order_meta);

        return l_root.to_clob;
    end;
end browse_pkg;
/

show errors

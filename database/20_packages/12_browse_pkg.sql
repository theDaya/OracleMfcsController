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

    function get_style(p_item in varchar2) return clob;

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
        return client_pkg.get_json(l_path, l_status);
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
        return client_pkg.get_json(l_path, l_status);
    end;

    function get_style(p_item in varchar2) return clob is
        l_status number;
    begin
        return client_pkg.get_json('/MerchIntegrations/services/foundation/item/' || p_item, l_status);
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
        l_body := client_pkg.get_json('/MerchIntegrations/services/procurement/order/' || p_order_no, l_status);
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

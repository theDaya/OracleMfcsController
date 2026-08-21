set define off
set serveroutput on size unlimited
set lines 240

-- READ-ONLY sweep of the master-data GET services named in the tenant OpenAPI
-- document. Reports row counts so we know which ones can actually back a
-- dropdown or a browse screen.

declare
    l_token varchar2(32767);
    l_base varchar2(400);
    l_ref varchar2(200);

    function cfg(p_key in varchar2, p_default in varchar2 default null) return varchar2 is
        l_v varchar2(4000);
    begin
        select dbms_lob.substr(config_value, 4000, 1) into l_v
          from config
         where config_key = p_key and environment = 'DEFAULT' and enabled_ind = 'Y';
        return l_v;
    exception
        when no_data_found then return p_default;
    end;

    procedure probe(p_label in varchar2, p_path in varchar2) is
        l_body clob;
        l_status number;
        l_count number;
        l_has_more varchar2(10);
        l_snip varchar2(150);
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';

        l_body := apex_web_service.make_rest_request(
            p_url => l_base || p_path,
            p_http_method => 'GET',
            p_transfer_timeout => 60
        );
        l_status := apex_web_service.g_status_code;

        if l_status between 200 and 299 then
            begin
                select json_value(l_body, '$.count' returning number null on error),
                       json_value(l_body, '$.hasMore' returning varchar2(10) null on error)
                  into l_count, l_has_more
                  from dual;
            exception when others then l_count := null; end;
            l_snip := replace(substr(dbms_lob.substr(l_body, 150, 1), 1, 150), chr(10), ' ');
            dbms_output.put_line(rpad(p_label, 26) || rpad(l_status, 5)
                || 'rows=' || rpad(nvl(to_char(l_count), '?'), 6)
                || 'more=' || rpad(nvl(l_has_more, '?'), 6) || l_snip);
        else
            dbms_output.put_line(rpad(p_label, 26) || rpad(l_status, 5) || 'NOT AVAILABLE');
        end if;
    exception
        when others then
            dbms_output.put_line(rpad(p_label, 26) || 'ERR  ' || substr(sqlerrm, 1, 100));
    end;
begin
    l_ref := cfg('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
    select dbms_lob.substr(secret_value, 32767, 1) into l_token
      from secret where secret_ref = l_ref;
    l_token := trim(l_token);
    if lower(substr(l_token, 1, 7)) = 'bearer ' then
        l_token := trim(substr(l_token, 8));
    end if;
    l_base := rtrim(cfg('MFCS_BASE_URL'), '/');

    dbms_output.put_line(rpad('SERVICE', 26) || rpad('HTTP', 5) || rpad('COUNT', 12) || rpad('MORE', 6) || 'HEAD');
    dbms_output.put_line(rpad('-', 200, '-'));

    -- Merchandise hierarchy.
    probe('merchhier/division', '/MerchIntegrations/services/foundation/merchhier/division?limit=5');
    probe('merchhier/groups', '/MerchIntegrations/services/foundation/merchhier/groups?limit=5');
    probe('merchhier/deps', '/MerchIntegrations/services/foundation/merchhier/deps?limit=5');
    probe('merchhier/class', '/MerchIntegrations/services/foundation/merchhier/class?limit=5');
    probe('merchhier/subclass', '/MerchIntegrations/services/foundation/merchhier/subclass?limit=5');

    -- Differentiators - currently hardcoded as MAP.COLOUR.* / MAP.SIZE.*.
    probe('difftype', '/MerchIntegrations/services/foundation/difftype?limit=5');
    probe('diffid', '/MerchIntegrations/services/foundation/diffid?limit=5');
    probe('diffgroup', '/MerchIntegrations/services/foundation/diffgroup?limit=5');

    -- Partners and locations.
    probe('supplier', '/MerchIntegrations/services/foundation/supplier?limit=5');
    probe('partner', '/MerchIntegrations/services/foundation/partner?limit=5');
    probe('store', '/MerchIntegrations/services/foundation/store?limit=5');
    probe('warehouse', '/MerchIntegrations/services/foundation/warehouse?limit=5');
    probe('orghier', '/MerchIntegrations/services/foundation/orghier?limit=5');

    -- Item attributes.
    probe('uda', '/MerchIntegrations/services/foundation/uda?limit=5');
    probe('item/brands', '/MerchIntegrations/services/item/brands?limit=5');
    probe('seasons', '/MerchIntegrations/services/item/foundation/seasons?limit=5');

    -- Transactional listings for the browse screen.
    probe('item', '/MerchIntegrations/services/foundation/item?limit=5');
    probe('procurement/order', '/MerchIntegrations/services/procurement/order?limit=5');
end;
/

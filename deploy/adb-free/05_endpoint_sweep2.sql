set define off
-- Run as OFFICE_MFCS. READ-ONLY sweep of candidate master-data endpoints.
-- Resolves which GET paths this tenant actually exposes, so the Postman
-- collection's "candidate" list can be reduced to facts.
--
-- Creates nothing. 200 = exists. 404 = wrong path. 400 = path exists but
-- arguments are wrong (still a hit worth chasing). 401/403 = scope problem.

set serveroutput on
set lines 240

declare
    l_token varchar2(32767);
    l_base varchar2(400);
    l_ref varchar2(200);

    function cfg(p_key in varchar2, p_default in varchar2 default null) return varchar2 is
        l_v varchar2(4000);
    begin
        select dbms_lob.substr(config_value, 4000, 1) into l_v
          from office_mfcs_config
         where config_key = p_key and environment = 'DEFAULT' and enabled_ind = 'Y';
        return l_v;
    exception
        when no_data_found then return p_default;
    end;

    procedure probe(p_label in varchar2, p_path in varchar2) is
        l_body clob;
        l_status number;
        l_verdict varchar2(40);
        l_snip varchar2(220);
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';

        l_body := apex_web_service.make_rest_request(
            p_url => l_base || p_path,
            p_http_method => 'GET',
            p_transfer_timeout => 30
        );
        l_status := apex_web_service.g_status_code;

        l_verdict := case
            when l_status between 200 and 299 then 'EXISTS'
            when l_status = 400 then 'EXISTS (bad args)'
            when l_status in (401, 403) then 'AUTH/SCOPE'
            when l_status = 404 then 'no'
            when l_status = 405 then 'EXISTS (wrong method)'
            else 'http ' || l_status
        end;

        l_snip := replace(replace(substr(dbms_lob.substr(l_body, 200, 1), 1, 200), chr(10), ' '), chr(13), ' ');

        dbms_output.put_line(rpad(p_label, 30) || rpad(l_status, 6) || rpad(l_verdict, 22) || l_snip);
    exception
        when others then
            dbms_output.put_line(rpad(p_label, 30) || rpad('ERR', 6) || substr(sqlerrm, 1, 120));
    end;
begin
    l_ref := cfg('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
    select dbms_lob.substr(secret_value, 32767, 1) into l_token
      from office_mfcs_secret where secret_ref = l_ref;
    l_token := trim(l_token);
    if lower(substr(l_token, 1, 7)) = 'bearer ' then
        l_token := trim(substr(l_token, 8));
    end if;
    l_base := rtrim(cfg('MFCS_BASE_URL'), '/');

    dbms_output.put_line(rpad('ENDPOINT', 30) || rpad('CODE', 6) || rpad('VERDICT', 22) || 'RESPONSE HEAD');
    dbms_output.put_line(rpad('-', 150, '-'));

    -- Pattern discovered: SINGULAR path + query params = search/list.
    --                     SINGULAR path + /{id}      = single record.
    probe('item?dept', '/MerchIntegrations/services/foundation/item?dept=1517&limit=5');
    probe('item?itemLevel=1', '/MerchIntegrations/services/foundation/item?itemLevel=1&limit=5');
    probe('item?itemParent', '/MerchIntegrations/services/foundation/item?itemParent=100050005&limit=5');

    probe('order?supplier', '/MerchIntegrations/services/procurement/order?supplier=700087&limit=5');
    probe('order?dept', '/MerchIntegrations/services/procurement/order?dept=1517&limit=5');
    probe('order?status=A', '/MerchIntegrations/services/procurement/order?status=A&limit=5');
    probe('order (no args)', '/MerchIntegrations/services/procurement/order?limit=5');

    probe('supplier?supplier', '/MerchIntegrations/services/foundation/supplier?supplier=700087&limit=5');
    probe('supplier (no args)', '/MerchIntegrations/services/foundation/supplier?limit=5');

    probe('uda?limit', '/MerchIntegrations/services/foundation/uda?limit=20');
    probe('diff?diffType=C', '/MerchIntegrations/services/foundation/diff?diffType=C&limit=10');
    probe('diff (no args)', '/MerchIntegrations/services/foundation/diff?limit=10');
    probe('diffGroup', '/MerchIntegrations/services/foundation/diffGroup?limit=10');

    probe('store?limit', '/MerchIntegrations/services/foundation/store?limit=10');
    probe('warehouse?limit', '/MerchIntegrations/services/foundation/warehouse?limit=10');
    probe('location?limit', '/MerchIntegrations/services/foundation/location?limit=10');
    probe('merchHierarchy?dept', '/MerchIntegrations/services/foundation/merchandiseHierarchy?dept=1517');
    probe('department?limit', '/MerchIntegrations/services/foundation/department?limit=10');
    probe('class?dept=1517', '/MerchIntegrations/services/foundation/class?dept=1517&limit=10');
    probe('subclass?dept', '/MerchIntegrations/services/foundation/subclass?dept=1517&limit=10');
    probe('itemSupplier?item', '/MerchIntegrations/services/foundation/itemSupplier?item=11743');
    probe('itemLocation?item', '/MerchIntegrations/services/foundation/itemLocation?item=11743');
end;
/

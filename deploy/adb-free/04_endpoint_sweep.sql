set define off
-- Run as MFCS_INTEGRATION. READ-ONLY sweep of candidate master-data endpoints.
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
          from config
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
      from secret where secret_ref = l_ref;
    l_token := trim(l_token);
    if lower(substr(l_token, 1, 7)) = 'bearer ' then
        l_token := trim(substr(l_token, 8));
    end if;
    l_base := rtrim(cfg('MFCS_BASE_URL'), '/');

    dbms_output.put_line(rpad('ENDPOINT', 30) || rpad('CODE', 6) || rpad('VERDICT', 22) || 'RESPONSE HEAD');
    dbms_output.put_line(rpad('-', 150, '-'));

    -- Known good, as controls.
    probe('item/{id}', '/MerchIntegrations/services/foundation/item/11743');
    probe('order/{no}', '/MerchIntegrations/services/procurement/order/25005');
    probe('restService/status', '/MerchIntegrations/services/administration/operations/restService/status'
        || '?xCorrelationId=sweep-control&includePayload=Y');

    dbms_output.put_line(rpad('-', 150, '-'));

    -- Merchandise hierarchy.
    probe('merchHier/departments', '/MerchIntegrations/services/foundation/merchandiseHierarchy/departments');
    probe('merchHier/classes', '/MerchIntegrations/services/foundation/merchandiseHierarchy/classes?dept=1517');
    probe('merchHier/subclasses', '/MerchIntegrations/services/foundation/merchandiseHierarchy/subclasses?dept=1517&class=6892');
    probe('foundation/department/1517', '/MerchIntegrations/services/foundation/department/1517');
    probe('foundation/departments', '/MerchIntegrations/services/foundation/departments');

    -- Supplier.
    probe('foundation/supplier/700087', '/MerchIntegrations/services/foundation/supplier/700087');
    probe('foundation/suppliers', '/MerchIntegrations/services/foundation/suppliers');

    -- Differentiators.
    probe('foundation/diffs', '/MerchIntegrations/services/foundation/diffs?diffType=C');
    probe('foundation/diff/08610', '/MerchIntegrations/services/foundation/diff/08610');
    probe('foundation/diffGroups', '/MerchIntegrations/services/foundation/diffGroups');

    -- Locations.
    probe('orgHier/locations', '/MerchIntegrations/services/foundation/organizationHierarchy/locations');
    probe('foundation/stores', '/MerchIntegrations/services/foundation/stores');
    probe('foundation/warehouses', '/MerchIntegrations/services/foundation/warehouses');
    probe('foundation/store/1927', '/MerchIntegrations/services/foundation/store/1927');
    probe('foundation/warehouse/19271', '/MerchIntegrations/services/foundation/warehouse/19271');

    -- UDAs.
    probe('foundation/udas', '/MerchIntegrations/services/foundation/udas');
    probe('foundation/uda', '/MerchIntegrations/services/foundation/uda');

    -- Search / list.
    probe('foundation/items?dept', '/MerchIntegrations/services/foundation/items?dept=1517');
    probe('procurement/orders?supp', '/MerchIntegrations/services/procurement/orders?supplier=700087');
    probe('foundation/item?dept', '/MerchIntegrations/services/foundation/item?dept=1517');
end;
/

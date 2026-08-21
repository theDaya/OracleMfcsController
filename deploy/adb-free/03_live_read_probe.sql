-- Run as MFCS_INTEGRATION. READ-ONLY probe against the live MFCS tenant.
-- Creates nothing. Uses the same token handling as CLIENT_PKG.access_token
-- in STATIC_BEARER mode: read SECRET, trim, strip any 'Bearer ' prefix.

set serveroutput on
set lines 220

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
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';
        apex_web_service.g_request_headers(3).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(3).value := sys_guid();

        l_body := apex_web_service.make_rest_request(
            p_url => l_base || p_path,
            p_http_method => 'GET',
            p_transfer_timeout => to_number(cfg('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );
        l_status := apex_web_service.g_status_code;

        dbms_output.put_line('----------------------------------------------------------');
        dbms_output.put_line(rpad(p_label, 22) || ' HTTP ' || l_status
            || '   ' || nvl(dbms_lob.getlength(l_body), 0) || ' bytes');
        if l_body is not null and dbms_lob.getlength(l_body) > 0 then
            dbms_output.put_line(substr(dbms_lob.substr(l_body, 900, 1), 1, 900));
        end if;
    exception
        when others then
            dbms_output.put_line('----------------------------------------------------------');
            dbms_output.put_line(rpad(p_label, 22) || ' FAIL - ' || sqlerrm);
    end;
begin
    l_ref := cfg('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
    l_base := rtrim(cfg('MFCS_BASE_URL'), '/');

    begin
        select dbms_lob.substr(secret_value, 32767, 1) into l_token
          from secret where secret_ref = l_ref;
    exception
        when no_data_found then
            dbms_output.put_line('No secret row for ref ' || l_ref || ' - nothing to test.');
            return;
    end;

    l_token := trim(l_token);
    if lower(substr(l_token, 1, 7)) = 'bearer ' then
        l_token := trim(substr(l_token, 8));
    end if;

    dbms_output.put_line('Token ref    : ' || l_ref);
    dbms_output.put_line('Token length : ' || length(l_token));
    dbms_output.put_line('Token segments (JWT has 3): ' || (regexp_count(l_token, '\.') + 1));
    dbms_output.put_line('Base URL     : ' || l_base);

    probe('REST service status',
          '/MerchIntegrations/services/administration/operations/restService/status');
    probe('Foundation item 11743', '/MerchIntegrations/services/foundation/item/11743');
    probe('Order 25005', '/MerchIntegrations/services/procurement/order/25005');
end;
/

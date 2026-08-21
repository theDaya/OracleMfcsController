-- Run as OFFICE_MFCS.
-- Proves DNS resolution, the network ACL and TLS trust are all working, without
-- needing a bearer token. An HTTP 401 is a PASS here: it means the request
-- reached MFCS and was rejected on credentials, not on plumbing.
--
-- ORA-24247 means the network ACL is missing (run 01_network_acl.sql).
-- ORA-29024 / ORA-29106 means the TLS certificate was not trusted.

set serveroutput on
set lines 200

declare
    l_response clob;
    l_url varchar2(400);

    procedure probe(p_label in varchar2, p_url in varchar2) is
        l_body clob;
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Accept';
        apex_web_service.g_request_headers(1).value := 'application/json';

        l_body := apex_web_service.make_rest_request(
            p_url => p_url,
            p_http_method => 'GET',
            p_transfer_timeout => 30
        );

        dbms_output.put_line(rpad(p_label, 12) || ' HTTP ' || apex_web_service.g_status_code
            || case
                 when apex_web_service.g_status_code in (401, 403) then '  PASS - reached host, rejected on auth'
                 when apex_web_service.g_status_code between 200 and 299 then '  PASS - reachable'
                 else '  reached host'
               end);
    exception
        when others then
            dbms_output.put_line(rpad(p_label, 12) || ' FAIL - ' || sqlerrm);
    end;
begin
    select dbms_lob.substr(config_value, 4000, 1) into l_url
      from office_mfcs_config
     where config_key = 'MFCS_BASE_URL' and environment = 'DEFAULT';

    probe('MFCS', rtrim(l_url, '/')
        || '/MerchIntegrations/services/administration/operations/restService/status');

    select dbms_lob.substr(config_value, 4000, 1) into l_url
      from office_mfcs_config
     where config_key = 'MFCS_TOKEN_URL' and environment = 'DEFAULT';

    probe('IDCS', l_url);
end;
/

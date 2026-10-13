-- Can RDS reach MFCS and its token host? Run in APEX SQL Workshop > SQL
-- COMMANDS (not Scripts - Commands shows DBMS Output). Changes nothing.
--
-- The controller's only outbound route is apex_web_service, so that is what
-- this calls. Neither call carries a credential, so neither can do anything:
-- the point is only whether a connection is made at all.
--
-- What each line means:
--   any HTTP status (401, 400, 405 ...)  the network path is open. 401 from
--                                        MFCS is the expected answer.
--   ORA-24247                            no network ACE for this host - for
--                                        this schema or the APEX engine schema
--   ORA-29024 / certificate              the host's certificate is not trusted
--   ORA-12535 / timed out                a firewall is dropping the traffic

declare
    l_body clob;

    procedure probe(p_label in varchar2, p_url in varchar2) is
    begin
        apex_web_service.g_request_headers.delete;
        l_body := apex_web_service.make_rest_request(
            p_url => p_url,
            p_http_method => 'GET',
            p_transfer_timeout => 20);
        dbms_output.put_line(rpad(p_label, 12) || 'HTTP ' || apex_web_service.g_status_code);
    exception
        when others then
            dbms_output.put_line(rpad(p_label, 12) || substr(sqlerrm, 1, 300));
            dbms_output.put_line(rpad(' ', 12) || substr(dbms_utility.format_error_stack, 1, 300));
    end;
begin
    probe('MFCS', 'https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com'
               || '/rgbu-rex-truw-stg3-mfcs/MerchIntegrations/services/item/brands?limit=1');
    probe('TOKEN HOST', 'https://idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com'
               || '/oauth2/v1/token');
end;
/

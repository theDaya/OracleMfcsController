set define off
set serveroutput on

-- Can the token endpoint actually be reached the way client_pkg reaches it?
--
-- Both paths are tested, and the second is the one that matters. utl_http runs
-- as MFCS_INTEGRATION; apex_web_service runs as the APEX engine schema, which
-- needs its own ACE on the same host. A run where the first passes and the
-- second fails is the exact state this repo was in on 2026-09-21, and it is why
-- testing only the first is worse than not testing at all - it reports success
-- for a configuration that cannot make a single real call.
--
-- Sends a deliberately incomplete request: HTTP 400 is the right answer, because
-- it proves IDCS replied. ORA-24247 means the ACE for that principal is missing.

declare
    l_url varchar2(500);
    l_body clob;
    l_pass boolean := true;
begin
    select dbms_lob.substr(config_value, 500, 1) into l_url
      from config where config_key = 'MFCS_TOKEN_URL' and environment = 'DEFAULT';

    declare
        l_req utl_http.req;
        l_res utl_http.resp;
    begin
        l_req := utl_http.begin_request(l_url, 'POST');
        l_res := utl_http.get_response(l_req);
        dbms_output.put_line('utl_http  (as MFCS_INTEGRATION) : OK, HTTP ' || l_res.status_code);
        utl_http.end_response(l_res);
    exception
        when others then
            l_pass := false;
            dbms_output.put_line('utl_http  (as MFCS_INTEGRATION) : FAILED - '
                || substr(utl_http.get_detailed_sqlerrm, 1, 120));
    end;

    begin
        apex_web_service.g_request_headers.delete;
        l_body := apex_web_service.make_rest_request(
            p_url => l_url, p_http_method => 'POST',
            p_body => 'grant_type=client_credentials', p_transfer_timeout => 20);
        dbms_output.put_line('apex_web_service (as APEX engine): OK, HTTP '
            || apex_web_service.g_status_code);
    exception
        when others then
            l_pass := false;
            dbms_output.put_line('apex_web_service (as APEX engine): FAILED - '
                || substr(utl_http.get_detailed_sqlerrm, 1, 120));
            dbms_output.put_line('  ^ this is the one client_pkg uses. Grant the ACE to the');
            dbms_output.put_line('    APEX engine schema, not just to MFCS_INTEGRATION.');
    end;

    dbms_output.put_line('');
    dbms_output.put_line(case when l_pass
        then 'Both paths reach the token host.'
        else 'Not ready - see above.' end);
end;
/

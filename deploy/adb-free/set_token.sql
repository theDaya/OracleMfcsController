-- Run as OFFICE_MFCS. Loads a Postman-issued bearer token, and repairs the
-- secret_ref if a previous load used the wrong one.
--
-- Usage:
--   sqlplus office_mfcs/<pw>@myatp_low @set_token.sql "<paste-token>"
--
-- The token may be pasted with or without a leading "Bearer ".
--
-- Why the repair step exists: the controller looks the token up by the ref named
-- in MFCS_BEARER_TOKEN_REF (default MFCS_BEARER_TOKEN). A row stored under any
-- other ref is invisible to it and fails with ORA-20890, which reads like a
-- missing token rather than a misfiled one.

set define off
set serveroutput on
set verify off

declare
    l_token varchar2(32767) := trim('&1');
    l_ref   varchar2(200);
    l_other number;
    l_len   number;
begin
    l_ref := office_mfcs_request_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');

    if lower(substr(l_token, 1, 7)) = 'bearer ' then
        l_token := trim(substr(l_token, 8));
    end if;

    if l_token is null or length(l_token) < 20 then
        raise_application_error(-20001, 'No token supplied. Pass it as the first argument.');
    end if;

    -- Repair: fold any row stored under a different ref into the configured one.
    select count(*) into l_other
      from office_mfcs_secret
     where secret_ref <> l_ref
       and secret_ref not like 'MFCS_WALLET%';

    if l_other > 0 then
        dbms_output.put_line('Found ' || l_other || ' secret row(s) under an unexpected ref; removing.');
        delete from office_mfcs_secret
         where secret_ref <> l_ref
           and secret_ref not like 'MFCS_WALLET%';
    end if;

    merge into office_mfcs_secret s
    using (select l_ref secret_ref, l_token secret_value from dual) x
    on (s.secret_ref = x.secret_ref)
    when matched then update set
        s.secret_value = x.secret_value,
        s.updated_at = systimestamp
    when not matched then insert (secret_ref, secret_value, description)
    values (x.secret_ref, x.secret_value, 'Postman-issued MFCS bearer token');

    commit;

    select dbms_lob.getlength(secret_value) into l_len
      from office_mfcs_secret where secret_ref = l_ref;

    dbms_output.put_line('Stored under ref : ' || l_ref);
    dbms_output.put_line('Token length     : ' || l_len);
    dbms_output.put_line('Segments (JWT=3) : ' || (length(l_token) - length(replace(l_token, '.', '')) + 1));
end;
/

prompt
prompt Verifying against MFCS...
declare
    l_status clob;
begin
    l_status := office_mfcs_master_pkg.token_status;
    dbms_output.put_line(l_status);
end;
/

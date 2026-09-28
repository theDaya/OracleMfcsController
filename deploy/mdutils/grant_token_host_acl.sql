set define off
set serveroutput on

-- Run as SYS, CONNECTED TO FREEPDB1, not to CDB$ROOT.
--
--     alter session set container = FREEPDB1;
--
-- Network ACLs are per-container. An ACE appended in the root does not apply to
-- the PDB where MFCS_INTEGRATION lives.
--
-- ==========================================================================
-- TWO principals need the grant, and missing the second one is the trap.
-- ==========================================================================
--
-- client_pkg reaches MFCS through apex_web_service, which is a DEFINER-RIGHTS
-- package owned by the APEX engine schema (APEX_260100 here). An outbound call
-- it makes runs with the APEX schema's network privileges, NOT with
-- MFCS_INTEGRATION's. So granting only MFCS_INTEGRATION looks correct, passes a
-- utl_http test, and still fails every real call.
--
-- Verified exactly that way on 2026-09-21, after the first grant:
--
--   utl_http from MFCS_INTEGRATION  -> IDCS answered HTTP 400   (ACE present)
--   apex_web_service, same URL      -> ORA-24247                (ACE missing)
--
-- The MFCS host already carries both ACEs, which is why calls to it have always
-- worked, and why the difference never showed up before the token endpoint
-- became something the database itself had to reach.
--
-- The APEX owner is derived rather than hardcoded so this survives an upgrade:
-- APEX_260100 becomes APEX_270100 and a hardcoded grant silently stops matching.

select sys_context('userenv', 'con_name') as container,
       sys_context('userenv', 'current_user') as connected_as
  from dual;

declare
    l_host varchar2(200) :=
        'idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com';
    l_apex_owner varchar2(128);

    procedure append(p_principal in varchar2, p_lower in number, p_upper in number) is
    begin
        dbms_network_acl_admin.append_host_ace(
            host       => l_host,
            lower_port => p_lower,
            upper_port => p_upper,
            ace        => xs$ace_type(
                privilege_list => xs$name_list('connect', 'resolve'),
                principal_name => p_principal,
                principal_type => xs_acl.ptype_db));
        dbms_output.put_line('OK - ' || p_principal
            || case when p_lower is null then ' (all ports)' else ' (port 443)' end);
    end;

    procedure grant_to(p_principal in varchar2) is
    begin
        begin
            append(p_principal, 443, 443);
        exception
            when others then
                if sqlcode = -24244 then
                    -- Some releases refuse an explicit port range when the host
                    -- already carries an ACL with different bounds. Wider than
                    -- intended; the output says so rather than hiding it.
                    append(p_principal, null, null);
                else
                    raise;
                end if;
        end;
    end;
begin
    select table_owner into l_apex_owner
      from all_synonyms
     where owner = 'PUBLIC' and synonym_name = 'APEX_WEB_SERVICE';

    dbms_output.put_line('APEX engine schema: ' || l_apex_owner);

    grant_to('MFCS_INTEGRATION');
    grant_to(l_apex_owner);
end;
/
commit;

prompt
prompt Then, as MFCS_INTEGRATION:
prompt   deploy/mdutils/sql.sh deploy/mdutils/verify_token_host.sql
prompt
prompt Note that script tests utl_http, which uses the MFCS_INTEGRATION ACE only.
prompt It passing does NOT prove the APEX one landed - the real call does.
prompt

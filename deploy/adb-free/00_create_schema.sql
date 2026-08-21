-- Run as ADMIN against the adb-free container (myatp_low).
-- Creates the integration schema that owns the Office MFCS objects and ORDS module.

set define off
set serveroutput on

prompt Creating OFFICE_MFCS schema

declare
    l_exists number;
begin
    select count(*) into l_exists from dba_users where username = 'OFFICE_MFCS';
    if l_exists = 0 then
        execute immediate 'create user office_mfcs identified by "CsidbaLocal2026"';
        dbms_output.put_line('Created user OFFICE_MFCS.');
    else
        dbms_output.put_line('User OFFICE_MFCS already exists; leaving password unchanged.');
    end if;
end;
/

-- Object privileges the README calls for.
grant create session to office_mfcs;
grant create table to office_mfcs;
grant create sequence to office_mfcs;
grant create procedure to office_mfcs;
grant create view to office_mfcs;
grant create type to office_mfcs;
grant unlimited tablespace to office_mfcs;

-- Canonical request hashing.
grant execute on sys.dbms_crypto to office_mfcs;

-- ADB bundles these for application schemas; granted explicitly so the install
-- does not depend on a role that may differ between environments.
grant execute on sys.dbms_lob to office_mfcs;
grant execute on sys.dbms_lock to office_mfcs;

-- ORDS. The repo's 020 script calls ords.enable_schema itself, but the schema
-- must be ORDS-enabled by an administrator first in an Autonomous Database.
begin
    ords_admin.enable_schema(
        p_enabled             => true,
        p_schema              => 'OFFICE_MFCS',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'office_mfcs',
        p_auto_rest_auth      => false
    );
    commit;
end;
/

prompt OFFICE_MFCS schema ready

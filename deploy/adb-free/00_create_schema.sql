-- Run as ADMIN against the adb-free container (myatp_low).
-- Creates the integration schema that owns the Office MFCS objects and ORDS module.

set define off
set serveroutput on

prompt Creating MFCS_INTEGRATION schema

declare
    l_exists number;
begin
    select count(*) into l_exists from dba_users where username = 'MFCS_INTEGRATION';
    if l_exists = 0 then
        execute immediate 'create user mfcs_integration identified by "CsidbaLocal2026"';
        dbms_output.put_line('Created user MFCS_INTEGRATION.');
    else
        dbms_output.put_line('User MFCS_INTEGRATION already exists; leaving password unchanged.');
    end if;
end;
/

-- Object privileges the README calls for.
grant create session to mfcs_integration;
grant create table to mfcs_integration;
grant create sequence to mfcs_integration;
grant create procedure to mfcs_integration;
grant create view to mfcs_integration;
grant create type to mfcs_integration;
grant unlimited tablespace to mfcs_integration;

-- Canonical request hashing.
grant execute on sys.dbms_crypto to mfcs_integration;

-- ADB bundles these for application schemas; granted explicitly so the install
-- does not depend on a role that may differ between environments.
grant execute on sys.dbms_lob to mfcs_integration;
grant execute on sys.dbms_lock to mfcs_integration;

-- ORDS. The repo's 020 script calls ords.enable_schema itself, but the schema
-- must be ORDS-enabled by an administrator first in an Autonomous Database.
begin
    ords_admin.enable_schema(
        p_enabled             => true,
        p_schema              => 'MFCS_INTEGRATION',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'mfcs_integration',
        p_auto_rest_auth      => false
    );
    commit;
end;
/

prompt MFCS_INTEGRATION schema ready

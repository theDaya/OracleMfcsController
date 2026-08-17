set define off
whenever sqlerror exit failure rollback

prompt Preparing OFFICE_MFCS_APP schema

declare
    l_count number;
begin
    select count(*)
      into l_count
      from dba_users
     where username = 'OFFICE_MFCS_APP';

    if l_count = 0 then
        execute immediate 'create user office_mfcs_app no authentication';
    end if;
end;
/

grant create session, create table, create sequence, create procedure, create view
    to office_mfcs_app;
grant unlimited tablespace to office_mfcs_app;
grant execute on sys.dbms_crypto to office_mfcs_app;
alter user office_mfcs_app grant connect through admin;

prompt OFFICE_MFCS_APP schema ready

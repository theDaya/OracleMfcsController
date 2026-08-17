set define off
whenever sqlerror exit failure rollback

declare
    l_count number;
begin
    select count(*) into l_count from dba_users where username = 'OFFICE_MFCS_UI_APP';
    if l_count = 0 then
        execute immediate 'create user office_mfcs_ui_app no authentication';
    end if;
end;
/

grant create session, create table, create sequence, create procedure to office_mfcs_ui_app;
grant unlimited tablespace to office_mfcs_ui_app;
grant execute on office_mfcs_app.office_mfcs_api_pkg to office_mfcs_ui_app;
grant select on office_mfcs_app.item_master to office_mfcs_ui_app;
grant select on office_mfcs_app.item_supplier to office_mfcs_ui_app;
grant select on office_mfcs_app.item_supp_country to office_mfcs_ui_app;
grant select on office_mfcs_app.item_loc to office_mfcs_ui_app;
grant select on office_mfcs_app.item_uda to office_mfcs_ui_app;
grant select on office_mfcs_app.ordhead to office_mfcs_ui_app;
grant select on office_mfcs_app.ordsku to office_mfcs_ui_app;
grant select on office_mfcs_app.ordloc to office_mfcs_ui_app;
grant select on office_mfcs_app.sups to office_mfcs_ui_app;
grant select on office_mfcs_app.store to office_mfcs_ui_app;
grant select on office_mfcs_app.wh to office_mfcs_ui_app;
grant select on office_mfcs_app.local_mfcs_rest_event to office_mfcs_ui_app;
alter user office_mfcs_ui_app grant connect through admin;

prompt OFFICE_MFCS_UI_APP schema prepared

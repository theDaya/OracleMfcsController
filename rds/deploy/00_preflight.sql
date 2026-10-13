-- Preflight for installing the IE_MFCS controller into RDS.
--
-- Run in APEX: SQL Workshop > SQL Scripts > Upload, then Run. It changes
-- nothing. Every check is a query, so its answer shows in the results.
-- Send back the results of every statement, including any that errored -
-- an error here is an answer too.

-- 1. Who and where. Expect MFCS_RDS_CUSTOM in current_user and
--    current_schema: that is the schema objects land in and whose privileges
--    apply. user, session_user and proxy_user show ORDS_PUBLIC_USER_DIS in
--    RDS, and that is normal - APEX connects as the ORDS account and runs each
--    statement as the workspace schema (seen 2026-10-13).
select user as schema_name,
       sys_context('userenv', 'session_user') as session_user,
       sys_context('userenv', 'current_user') as current_user,
       sys_context('userenv', 'current_schema') as current_schema,
       sys_context('userenv', 'proxy_user') as proxy_user,
       sys_context('userenv', 'con_name') as container
  from dual;

select product, version_full
  from product_component_version;

-- 2. Nothing installed yet. Expect 0.
select count(*) as existing_ie_mfcs_objects
  from user_objects
 where object_name like 'IE\_MFCS\_%' escape '\';

-- 3. Can this schema create what the install creates. Expect all six rows.
select privilege
  from session_privs
 where privilege in ('CREATE TABLE', 'CREATE VIEW', 'CREATE SEQUENCE',
                     'CREATE PROCEDURE', 'CREATE TYPE', 'CREATE JOB')
 order by privilege;

-- 4. SELECT on the four RDS views, and HOW it is held. A view over another
--    schema's object needs the grant made to this schema directly. If a view
--    shows only VIA ROLE, the install's views will fail with ORA-01031 and
--    the grant has to be made directly.
select table_name, privilege, 'DIRECT' as granted
  from user_tab_privs
 where owner = 'MFCS_RDS'
   and table_name in ('RDS_WV_GROUPS', 'RDS_WV_DEPS', 'RDS_WV_CLASS', 'RDS_WV_SUBCLASS')
union all
select table_name, privilege, 'VIA ROLE ' || role
  from role_tab_privs
 where owner = 'MFCS_RDS'
   and table_name in ('RDS_WV_GROUPS', 'RDS_WV_DEPS', 'RDS_WV_CLASS', 'RDS_WV_SUBCLASS')
 order by 1, 3;

-- 5. The columns the install reads. Expect no MISSING.
with expected (table_name, column_name) as (
    select 'RDS_WV_GROUPS', 'GROUP_NO' from dual union all
    select 'RDS_WV_GROUPS', 'GROUP_NAME' from dual union all
    select 'RDS_WV_GROUPS', 'DIVISION' from dual union all
    select 'RDS_WV_GROUPS', 'LAST_DML_TYPE' from dual union all
    select 'RDS_WV_DEPS', 'DEPT' from dual union all
    select 'RDS_WV_DEPS', 'DEPT_NAME' from dual union all
    select 'RDS_WV_DEPS', 'GROUP_NO' from dual union all
    select 'RDS_WV_DEPS', 'LAST_DML_TYPE' from dual union all
    select 'RDS_WV_CLASS', 'DEPT' from dual union all
    select 'RDS_WV_CLASS', 'CLASS' from dual union all
    select 'RDS_WV_CLASS', 'CLASS_NAME' from dual union all
    select 'RDS_WV_CLASS', 'CLASS_ID' from dual union all
    select 'RDS_WV_CLASS', 'LAST_DML_TYPE' from dual union all
    select 'RDS_WV_SUBCLASS', 'DEPT' from dual union all
    select 'RDS_WV_SUBCLASS', 'CLASS' from dual union all
    select 'RDS_WV_SUBCLASS', 'SUBCLASS' from dual union all
    select 'RDS_WV_SUBCLASS', 'SUB_NAME' from dual union all
    select 'RDS_WV_SUBCLASS', 'SUBCLASS_ID' from dual union all
    select 'RDS_WV_SUBCLASS', 'LAST_DML_TYPE' from dual
)
select e.table_name, e.column_name,
       nvl(c.data_type, 'MISSING') as data_type
  from expected e
  left join all_tab_columns c
    on c.owner = 'MFCS_RDS'
   and c.table_name = e.table_name
   and c.column_name = e.column_name
 order by e.table_name, e.column_name;

-- 6. What is in them. Expect around 21 departments on STG.
select 'GROUPS' as view_name, count(*) as total_rows,
       sum(case when last_dml_type = 'D' then 1 else 0 end) as deleted_rows
  from mfcs_rds.rds_wv_groups
union all
select 'DEPS', count(*), sum(case when last_dml_type = 'D' then 1 else 0 end)
  from mfcs_rds.rds_wv_deps
union all
select 'CLASS', count(*), sum(case when last_dml_type = 'D' then 1 else 0 end)
  from mfcs_rds.rds_wv_class
union all
select 'SUBCLASS', count(*), sum(case when last_dml_type = 'D' then 1 else 0 end)
  from mfcs_rds.rds_wv_subclass;

-- 7. Every schema the workspace may use. Expect MFCS_RDS_CUSTOM among them,
--    under MFCS. The web credential is looked up in the workspace named in
--    MFCS_APEX_WORKSPACE, so this is also the check that "MFCS" is right.
select workspace_name, schema
  from apex_workspace_schemas
 order by workspace_name, schema;

-- 8. The MFCS web credential, if it has been created yet. Expect one row,
--    static id MFCS_OAUTH, once step 1 of rds/README.md is done.
select workspace, name, static_id, credential_type, scope, valid_for_urls
  from apex_workspace_credentials
 where static_id = 'MFCS_OAUTH';

-- 9. Network ACEs granted to this schema. Expect rows for the MFCS host
--    (rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com) and the IDCS token
--    host (idcs-...identity.oraclecloud.com). The APEX engine schema needs its
--    own ACEs for both as well - this query cannot see those, only a call can.
select host, lower_port, upper_port, privilege, status
  from user_host_aces
 order by host, privilege;

-- 10. Canary for the install scripts' own syntax. The packages contain blank
--     lines inside PL/SQL and an ampersand in string literals. If this block
--     reports an error, or prompts for a substitution value, SQL Scripts is
--     reading those differently and the install will fail - stop and say so.
declare
    l_url varchar2(100) := '?limit=1&offsetkey=x';

    l_len number;
begin

    l_len := length(l_url);
end;
/

select 'Preflight complete' as status from dual;

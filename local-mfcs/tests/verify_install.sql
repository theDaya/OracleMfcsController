set define off
set feedback off
set pagesize 100
set linesize 220
set serveroutput on

prompt Local MFCS install verification

select sys_context('USERENV', 'CON_NAME') as container_name,
       sys_context('USERENV', 'CURRENT_SCHEMA') as current_schema
  from dual;

select object_name, object_type, status
  from user_objects
 where object_name in (
           'LOCAL_MFCS_SERVICE_PKG',
           'OFFICE_MFCS_API_PKG',
           'ITEM_MASTER',
           'DIFF_GROUPS',
           'ORDHEAD',
           'ORDSKU',
           'ORDLOC'
       )
 order by object_name, object_type;

select name, type, line, position, text
  from user_errors
 where name in ('LOCAL_MFCS_SERVICE_PKG', 'OFFICE_MFCS_API_PKG')
 order by name, sequence;

select config_key, dbms_lob.substr(config_value, 200, 1) as config_value
  from office_mfcs_config
 where environment = 'DEFAULT'
   and config_key in ('MFCS_CLIENT_MODE', 'MFCS_SCHEMA_READY_YN', 'MFCS_BASE_URL')
 order by config_key;

select object_name, object_type, status
  from user_objects
 where status <> 'VALID'
 order by object_type, object_name;

exit

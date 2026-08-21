-- Run as MFCS_INTEGRATION. Post-install verification.

set lines 200 pages 200 feedback off
set serveroutput on

col object_name for a40
col object_type for a20
col status for a10

prompt === Invalid objects (expect none) ===
select object_name, object_type, status
  from user_objects
 where status <> 'VALID'
 order by object_type, object_name;

prompt
prompt === Object counts by type ===
select object_type, count(*) cnt
  from user_objects
 group by object_type
 order by object_type;

prompt
prompt === Compilation errors (expect none) ===
col name for a40
col text for a90
select name, line, text
  from user_errors
 order by name, sequence;

prompt
prompt === ORDS module and handlers ===
col uri_prefix for a24
col uri_template for a44
col method for a8
select m.uri_prefix, t.uri_template, h.method, h.source_type
  from user_ords_modules m
  join user_ords_templates t on t.module_id = m.id
  join user_ords_handlers h on h.template_id = t.id
 order by t.uri_template, h.method;

prompt
prompt === Runtime configuration ===
col config_key for a34
col config_value for a90
select config_key, config_value
  from config
 where config_key in (
        'MFCS_AUTH_MODE', 'MFCS_BASE_URL', 'MFCS_TOKEN_URL',
        'MFCS_BEARER_TOKEN_REF',
        'FEATURE_ITEM_LOCATIONS_YN', 'FEATURE_INITIAL_RETAIL_YN')
 order by config_key;

prompt
prompt === Config row count ===
select count(*) config_rows from config;

prompt
prompt === Bearer token loaded? ===
select case when count(*) = 0
            then 'NO - load MFCS_BEARER_TOKEN before any live call'
            else 'YES - ' || count(*) || ' secret row(s) present'
       end bearer_token_status
  from secret
 where secret_ref = 'MFCS_BEARER_TOKEN';

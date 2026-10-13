-- After the three install scripts. Changes nothing and calls nothing outside
-- the database. Run in APEX: SQL Workshop > SQL Scripts.

-- 1. Expect no rows.
select object_name, object_type, status
  from user_objects
 where object_name like 'IE\_MFCS\_%' escape '\'
   and status <> 'VALID'
 order by object_type, object_name;

-- 2. Expect no rows. If there are any, these are the lines to send back.
select name, type, line, position, text
  from user_errors
 where name like 'IE\_MFCS\_%' escape '\'
 order by name, type, sequence;

-- 3. Expect INDEX 15, PACKAGE 15, PACKAGE BODY 15, SEQUENCE 2, TABLE 8, VIEW 4.
select object_type, count(*) as objects
  from user_objects
 where object_name like 'IE\_MFCS\_%' escape '\'
 group by object_type
 order by object_type;

-- 4. Expect 84 settings, workspace MFCS, mode OAUTH_CLIENT_CREDENTIALS.
select count(*) as settings,
       max(case when config_key = 'MFCS_APEX_WORKSPACE' then dbms_lob.substr(config_value, 100, 1) end) as workspace,
       max(case when config_key = 'MFCS_AUTH_MODE' then dbms_lob.substr(config_value, 100, 1) end) as auth_mode,
       max(case when config_key = 'MFCS_BASE_URL' then dbms_lob.substr(config_value, 200, 1) end) as base_url
  from ie_mfcs_cfg_setting;

-- 5. The hierarchy as the controller sees it, through its own views.
--    Expect the same counts as preflight step 6, less the deleted rows.
select 'MERCH_GROUP' as level_name, count(*) as live_rows from ie_mfcs_vw_merch_group
union all
select 'DEPARTMENT', count(*) from ie_mfcs_vw_department
union all
select 'CLASS', count(*) from ie_mfcs_vw_class
union all
select 'SUBCLASS', count(*) from ie_mfcs_vw_subclass;

-- 6. The credential, as the controller reports it. Expect "present":true.
--    This only says the credential is registered - 05 is what proves it works.
select ie_mfcs_client.token_status as token_status from dual;

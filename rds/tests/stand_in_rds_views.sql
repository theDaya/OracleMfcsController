-- Stand-ins for rds/database/15_views, for a database that has no MFCS_RDS.
-- NEVER RUN THIS IN RDS - it would replace the real views.
--
-- Used on mdutils to compile and preview the RDS layer before it goes anywhere
-- near RDS. Same names and columns as the real views, built from the hierarchy
-- the original layer already holds in MASTER_DATA (loaded there from an RDS
-- extract), so a preview sees the same departments it would see in RDS.

create or replace view ie_mfcs_vw_merch_group as
select data_code group_no, description group_name,
       json_value(attributes, '$.division') division
  from master_data
 where data_type = 'MERCH_GROUP';

create or replace view ie_mfcs_vw_department as
select data_code dept, description dept_name,
       json_value(attributes, '$.groupNo') group_no
  from master_data
 where data_type = 'DEPARTMENT';

create or replace view ie_mfcs_vw_class as
select parent_code dept, data_code class, description class_name,
       json_value(attributes, '$.classId') class_id
  from master_data
 where data_type = 'CLASS';

create or replace view ie_mfcs_vw_subclass as
select regexp_substr(parent_code, '[^.]+', 1, 1) dept,
       regexp_substr(parent_code, '[^.]+', 1, 2) class,
       data_code subclass, description sub_name,
       json_value(attributes, '$.subclassId') subclass_id
  from master_data
 where data_type = 'SUBCLASS';

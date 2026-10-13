-- The merchandise hierarchy, read from the tenant's own tables as RDS
-- replicates them into MFCS_RDS.
--
-- Every read of MFCS_RDS goes through a view of ours rather than naming the
-- RDS view in a package, for three reasons:
--
--   - RDS keeps a row after it is deleted in MFCS, marked LAST_DML_TYPE = 'D'.
--     Filtering it out here means no reader can forget to.
--   - The packages then depend only on objects in this schema, which can be
--     stood in for on a database without RDS (rds/tests/stand_in_rds_views.sql)
--     so the whole layer still compiles and previews there.
--   - When the rest of master data moves onto RDS, this is where it goes.
--
-- Creating a view over another schema's object needs SELECT granted to this
-- schema directly - a grant through a role is not enough. 00_preflight.sql
-- checks which kind this schema holds.

create or replace view ie_mfcs_vw_merch_group as
select group_no, group_name, division
  from mfcs_rds.rds_wv_groups
 where nvl(last_dml_type, 'I') <> 'D';

create or replace view ie_mfcs_vw_department as
select dept, dept_name, group_no
  from mfcs_rds.rds_wv_deps
 where nvl(last_dml_type, 'I') <> 'D';

create or replace view ie_mfcs_vw_class as
select dept, class, class_name, class_id
  from mfcs_rds.rds_wv_class
 where nvl(last_dml_type, 'I') <> 'D';

create or replace view ie_mfcs_vw_subclass as
select dept, class, subclass, sub_name, subclass_id
  from mfcs_rds.rds_wv_subclass
 where nvl(last_dml_type, 'I') <> 'D';

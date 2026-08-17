set define off
set serveroutput on
whenever sqlerror exit failure rollback

@@001_workflow_tables.sql
@@002_workflow_logging_upgrade.sql
@@003_workflow_log_package.sql
@@010_workflow_package_spec.sql
@@011_workflow_package_body.sql
@@012_state_viewer_package_spec.sql
@@013_state_viewer_package_body.sql
@@020_workflow_ords.sql

prompt Office MFCS UI workflow backend installed

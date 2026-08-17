set define off
set serveroutput on
whenever sqlerror exit failure rollback

@@002_workflow_logging_upgrade.sql
@@003_workflow_log_package.sql
@@012_state_viewer_package_spec.sql
@@013_state_viewer_package_body.sql
@@020_workflow_ords.sql

prompt Office MFCS state viewer backend installed

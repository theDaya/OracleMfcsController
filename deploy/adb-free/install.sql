-- Installs the MFCS integration layer into the current schema.
--
-- Everything targets the real MFCS tenant; there are no simulators or client modes.
--
-- Order is dependency-driven, not arbitrary. Each package is a single file holding
-- its spec and body, so a package must be preceded by everything its body calls.
-- The numbering in 20_packages/ encodes that order.

set define off
set echo off
set feedback on
whenever sqlerror exit failure

prompt ==========================================
prompt  MFCS integration layer
prompt ==========================================

prompt
prompt -- Tables and seed data
@@../../database/10_tables/01_core.sql
@@../../database/10_tables/02_constraints.sql
@@../../database/10_tables/03_config_seed.sql
@@../../database/10_tables/04_event_log.sql
@@../../database/10_tables/05_master_data.sql

prompt
prompt -- Packages
@@../../database/20_packages/01_config_pkg.sql
@@../../database/20_packages/02_event_pkg.sql
@@../../database/20_packages/03_request_pkg.sql
@@../../database/20_packages/04_step_pkg.sql
@@../../database/20_packages/05_validation_pkg.sql
@@../../database/20_packages/06_payload_pkg.sql
@@../../database/20_packages/07_client_pkg.sql
@@../../database/20_packages/08_recovery_pkg.sql
@@../../database/20_packages/09_orchestrator_pkg.sql
@@../../database/20_packages/10_preview_pkg.sql
@@../../database/20_packages/11_master_pkg.sql
@@../../database/20_packages/12_browse_pkg.sql
@@../../database/20_packages/14_sku_pkg.sql
@@../../database/20_packages/15_api_pkg.sql
@@../../database/20_packages/16_ords_util_pkg.sql

prompt
prompt -- ORDS
@@../../database/30_ords/01_transactions.sql
@@../../database/30_ords/02_preview.sql
@@../../database/30_ords/03_console.sql

prompt ==========================================
prompt  Install complete
prompt ==========================================

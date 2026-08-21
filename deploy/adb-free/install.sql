-- Run as OFFICE_MFCS. Installs the Office MFCS integration layer in order.
-- Every call goes to the real MFCS tenant; there are no simulators or client modes.

set define off
set echo off
set feedback on
whenever sqlerror exit failure

prompt ==========================================
prompt Office MFCS integration layer install
prompt ==========================================

@@../../database/001_office_mfcs_tables.sql
@@../../database/002_office_mfcs_constraints.sql
@@../../database/003_office_mfcs_config.sql
@@../../database/004_office_mfcs_event_log.sql
@@../../database/005_office_mfcs_master_data.sql
@@../../database/010_office_mfcs_package_specs.sql

-- The payload mapper must load before the package bodies: office_mfcs_mapping_pkg
-- now calls office_mfcs_payload_pkg.build_request statically, so the dependency is
-- checked at compile time. It needs only the specs from 010, so this order is safe.
@@../../database/013_office_mfcs_payload_pkg.sql

@@../../database/011_office_mfcs_package_bodies.sql
@@../../database/012_office_mfcs_preview_pkg.sql
@@../../database/014_office_mfcs_master_pkg.sql

@@../../database/020_office_mfcs_ords.sql
@@../../database/021_office_mfcs_preview_ords.sql
@@../../database/022_office_mfcs_browse_ords.sql

prompt ==========================================
prompt Install complete
prompt ==========================================

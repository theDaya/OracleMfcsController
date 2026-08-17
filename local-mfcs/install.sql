set define off
set serveroutput on
whenever sqlerror exit failure rollback

prompt Installing Office MFCS controller
@@../database/001_office_mfcs_tables.sql
@@../database/002_office_mfcs_constraints.sql
@@../database/003_office_mfcs_config.sql
@@../database/004_office_mfcs_logging_upgrade.sql
@@../database/005_office_mfcs_log_package.sql
@@../database/010_office_mfcs_package_specs.sql
@@../database/011_office_mfcs_package_bodies.sql
@@../tests/office_mfcs_public_contract_pkg.sql
@@../database/020_office_mfcs_ords.sql

prompt Installing Local MFCS RMS simulator
@@database/001_local_mfcs_tables.sql
@@database/002_local_mfcs_constraints.sql
@@database/003_local_mfcs_seed.sql
@@database/004_local_mfcs_compatibility_views.sql
@@database/005_local_mfcs_log_package.sql
@@database/010_local_mfcs_package_spec.sql
@@database/011_local_mfcs_package_body.sql
@@database/020_local_mfcs_ords.sql
@@database/030_local_mfcs_config.sql
@@database/040_local_mfcs_demo_seed.sql

prompt Local MFCS installation complete

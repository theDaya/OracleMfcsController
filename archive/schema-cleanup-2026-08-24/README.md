# MFCS_INTEGRATION Legacy Cleanup

Archived on 2026-08-24 after the backend was simplified from the old `OFFICE_MFCS_*`
object names to the current package/table names.

Files:

- `legacy-mfcs-objects-ddl.sql` - DBMS_METADATA DDL for the legacy objects only.
  Table data, request payloads, logs, and secret values were intentionally not exported.
- `drop-legacy-mfcs-objects.sql` - the cleanup script run against `MFCS_INTEGRATION`.

Before cleanup, the old `OFFICE_MFCS_SECRET.MFCS_BEARER_TOKEN` row was migrated into
the current `SECRET.MFCS_BEARER_TOKEN` row.

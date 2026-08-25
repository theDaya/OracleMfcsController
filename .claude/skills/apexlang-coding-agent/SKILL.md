---
name: apexlang-coding-agent
description: Work on checked-in Oracle APEX APEXlang exports, especially validating/importing apps and avoiding common APEXlang schema and UI-report pitfalls.
metadata:
  short-description: Maintain APEXlang app exports safely
---

# APEXlang Coding Agent

Use this when editing an Oracle APEX application stored as APEXlang files.

## Workflow

- Treat the checked-in APEXlang export as source of truth. Edit files, validate with SQLcl, then import to the target APEX workspace.
- Prefer existing exported files as syntax donors. APEXlang property names are precise and sometimes differ from APEX Builder labels.
- Use SQLcl thin connections explicitly on this Windows host:

```powershell
& 'C:\oracleTools\sqlcl\bin\sql.exe' -thin -L 'USER/PASSWORD@//host:1521/service'
```

- Validate before import:

```sql
apex validate -input "C:\path\to\apexlang\app-folder" -workspace WORKSPACE_NAME
apex import -input "C:\path\to\apexlang\app-folder" -workspace WORKSPACE_NAME -id 102 -schema PARSING_SCHEMA -name "App Name"
```

The installed SQLcl 26.2 validates/imports successfully here, but `apex export` and `apex generate` have thrown a Java `Path.of(null)` error in this shell. Do not rely on those commands until SQLcl is upgraded or the issue is retested.

## Page And Component Pitfalls

- For page-load JavaScript, prefer the page-level block:

```apex
javaScript {
    executeWhenPageLoads:
        ```javascript-browser
        // code
        ```
}
```

- Dynamic actions require a valid APEXlang event token and a selection. `pageLoad` is not valid; `ready` and `load` are valid event names, but page-level `executeWhenPageLoads` is often simpler for defaulting.
- Interactive reports can require manual "Synchronize Columns" in APEX Builder when their SQL changes but the export lacks column definitions. For fixed diagnostic/status screens where every column should always show, prefer `classicReport` with explicit columns.
- `classicReport` regions need `componentAppearance { template: @standard }` and explicit `column` entries. Classic report columns do not take `source { dataType: ... }`.
- Interactive grids need primary-key columns marked with `queryOnly: true` and `primaryKey: true`; default child foreign keys from the parent page item where appropriate.
- When adding buttons that run PL/SQL, keep long-running real work out of the page submit. Enqueue a scheduler job or call a package designed for quick validation/preview.

## MFCS Controller Conventions

- Do not copy StyleMan behaviour blindly. StyleMan is visual inspiration only; MFCS flow rules come from this repo's backend packages.
- The APEX screen should offer source/display values that the backend accepts. When validation checks `MAP.*` config, use `CONFIG`-backed LOVs rather than raw `MASTER_DATA` rows.
- `SKU_SIZE` is a source/display size and must come from `MAP.SIZE.*`; the backend maps it to MFCS `diff2`.
- `COLOUR` is style/colourway-level for the current request. Do not add SKU-level colour unless the backend contract changes to support multiple colourways per request.
- For order creates, expose/default the date fields used by the payload: `NOT_BEFORE_DATE`, `NOT_AFTER_DATE`, `OTB_EOW_DATE`, `EARLIEST_SHIP_DATE`, and `LATEST_SHIP_DATE`. `OTB_EOW_DATE` must fall on the configured retail week-ending day.
- Scheduler job actions can only call procedures visible in the package specification. A private package-body helper cannot be invoked from a `DBMS_SCHEDULER` anonymous PL/SQL block.

## Verification

After import, check:

```sql
apex list
select object_type, object_name from user_objects where status <> 'VALID';
```

For submit/debug status, the local truth is:

- `UI_DRAFT`: APEX draft and generated payloads.
- `REQUEST`: registered integration request.
- `STEP`: ordered step graph and statuses.
- `ATTEMPT`: endpoint, method, request payload, response payload, and HTTP status per MFCS call.
- `EVENT_LOG`: autonomous log trail.

MFCS list/browse endpoints can lag newly created records, so do not use them as the only success signal.

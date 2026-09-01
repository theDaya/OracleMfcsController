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

## Donor exports

Oracle's **UX Pattern Catalog** (app 103 here) is checked out separately at
<https://github.com/theDaya/apexlangExports> - 21 pages of Oracle's own APEXlang, and the best source
of syntax that this repo's own export does not contain.

What it does carry: `facetedSearch`, `chart`, `themeTemplateComponent` (cards, media lists),
`classicReport`, drawer forms, dashboards, master-detail, and a `staticValues` donor.

The same repo carries **`sample-interactive-grids`**, a second app of 49 pages that is the better donor
for anything grid-shaped: `p00030-basic-editing`, `p00031-validation`, `p00034-form-with-grid`,
`p00035-master-detail`, `p00036-other-column-types`, `p00054/55-editing-in-a-dialog`,
`p00058-dynamic-actions`. 39 interactive grids and 18 auto-row-processing donors between them.

**A grid-column cascading LOV has no donor in either app.** `cascadingLov` and `parentColumns` appear
only on page items, never on a grid column. Do not spend time hunting for one; label the list so a
value is unambiguous on its own, and let validation reject a bad pairing.

**Popup LOV, for a list too long to be a select list** (a colour picker over 48,000 diffs, say). From
`sample-interactive-grids/pages/p00036-other-column-types.apx`:

```apex
column MGR (
    type: popupLov
    heading { heading: Manager }
    settings {
        displayAs: modalDialog
    }
    lov {
        type: sqlQuery
        sqlQuery: select ENAME as d, EMPNO as r from EBA_DEMO_IG_EMP order by 1
    }
    source {
        databaseColumn: MGR
        dataType: number
    }
    columnFilter {
        lovType: useLov
    }
)
```

`switch` is also available as a column type, which suits a Y/N flag better than a two-entry select
list.

## Page And Component Pitfalls

- **`staticValues` is a string, not an array.** Writing it as a list of pairs fails validation with
  `Property: staticValues, does not support Arrays`. The correct form, from the pattern catalog:

```apex
lov {
    type: staticValues
    staticValues: STATIC:Manager A;A,Manager B;B
}
```

  Display first, then `;`, then the return value; pairs separated by commas. A `sqlQuery` selecting
  literals from dual also works and is what this repo currently uses in p00003, but the static form is
  what Oracle writes.


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

---
name: apexlang-coding-agent
description: Work on checked-in Oracle APEX APEXlang exports, especially validating/importing apps and avoiding common APEXlang schema and UI-report pitfalls.
metadata:
  short-description: Maintain APEXlang app exports safely
---

# APEXlang Coding Agent

Everything here was learned by doing it wrong first. Read the whole thing before
editing an `.apx` file; most of it is not discoverable from the files themselves.

## The loop

Edit the checked-in export, validate, import, then **check the dictionary**. Never skip
the last step: validation and import both pass on several mistakes that break the page
at render.

```powershell
# SQLcl on this Windows host. -thin avoids needing an Oracle client.
& 'C:\oracleTools\sqlcl\bin\sql.exe' -thin -L 'USER/PASSWORD@//host:1521/service'
```

```sql
apex validate -input "<abs path>\apexlang\<app-folder>" -workspace TW_TEST
apex import   -input "<abs path>\apexlang\<app-folder>" -workspace TW_TEST -id 102 \
              -schema MFCS_INTEGRATION -name "MFCS Controller"
```

For this repo the connection is `deploy/mdutils/sql.sh` and the app is 102 `MFCS Controller`
in workspace `TW_TEST`, parsing schema `MFCS_INTEGRATION`.

`apex export` and `apex generate` throw a Java `Path.of(null)` in this shell. Do not rely
on them; treat the checked-in files as the source of truth and edit them directly.

**Validation is a good oracle for syntax and a poor one for behaviour.** It caught every
invalid property listed below on the first try. It caught none of the four render-time
traps in the next section.

## The four traps that cost real time

These all validate, import and then misbehave. Each one is worth checking for explicitly.

### An LOV query must not start with a comment

APEX decides whether a source is SQL or PL/SQL from how the text begins. A leading `--`
makes it guess PL/SQL, wrap the query in `declare function x return varchar2 is begin …`
and fail at render with `PLS-00428: an INTO clause is expected in this SELECT statement`.
The error names the *parent* region, not the column at fault, so it reads like a container
problem. Put comments after the `select`.

```sql
select region_name, name,
       case when substr(ltrim(lov_source), 1, 2) = '--' then 'STARTS WITH COMMENT' else 'ok' end
  from apex_appl_page_ig_columns
 where application_id = :app and lov_source is not null;
```

### A form's primary key item must be `hidden`, not `displayOnly`

Display-only items are not posted on submit, so their value is gone by the time page
processes run. Anything binding that item — a region query, an LOV, a DML target — sees
an undefined bind. The debug log says `Access to undefined Per Request (Memory Only)
variable`. APEXlang exposes no property for "Maintain Session State", so the item type is
the lever you have.

### Interactive grid DML targets the region query, not the table

With `target_type: REGION_SOURCE` (the default), the generated update is:

```sql
update (select … from t where draft_id = :P3_DRAFT_ID) set … where "PK" = :APEX$PK2
```

If that bind is undefined the inline view filters to nothing and **the update silently
changes zero rows**. Inserts are unaffected, because an insert through an inline view is
not filtered by its `where`. That asymmetry — inserts fine, updates ignored — is the
signature of this problem, and it is not caused by having several grids on a page.

### `returnPksAfterInsert` must be true

Left false, a newly inserted row is written but the grid has no key for it, drops it from
its model, and it reappears only after a full page reload. Looks like "my changes were
lost".

```apex
target {
    returnPksAfterInsert: true
}
```

## Syntax that has no donor, or a misleading one

### staticValues is a string, not an array

```apex
lov {
    type: staticValues
    staticValues: STATIC:Manager A;A,Manager B;B
}
```

Display, `;`, return value; pairs comma-separated. Writing it as a list of pairs fails
with `Property: staticValues, does not support Arrays`. A `sqlQuery` selecting literals
from `dual` also works.

### A grid column can cascade on another column

Neither donor app contains an example, so searching for one is a dead end. `parentColumns`
takes the parent *column* name and the child's LOV binds it like a page item. The parent
needs nothing special.

```apex
column MGR (
    type: popupLov
    settings { displayAs: modalDialog }
    lov {
        type: sqlQuery
        sqlQuery: select ENAME as d, EMPNO as r from EMP where JOB = :JOB order by 1
    }
    cascadingLov {
        parentColumns: JOB
    }
)
```

### Popup LOV, for a list too long to be a select list

Same shape as above minus the cascade, plus `columnFilter { lovType: useLov }`. Use it for
anything in the thousands — a colour picker over 48,000 differentiators is not a select
list.

### Template references differ between exports

This repo's export uses `template: @standard`. The donor apps use `template: @/standard`.
**Use the form the file you are editing already uses**; the other resolves as
`REFERENCE_NOT_FOUND`. Template names are the kebab-case of the file in
`shared-components/themes/universal-theme/region-templates/`.

### Tabs

A `regionDisplaySelector` region stacks its sub-regions with a switcher above them. For
actual tabs, use a `staticContent` region with the Tabs Container template and parent the
detail regions to it:

```apex
region details (
    type: staticContent
    appearance {
        template: @tabs-container
    }
)
```

Sub-regions join it with `layout { parentRegion: @details, slot: subRegions }`. Note
`templateOptions` is rejected on this region.

### Properties rejected where you would expect them

| On | Rejected |
| --- | --- |
| `pageItem type: hidden` | `label`, `alignment` |
| `pageItem` select list | `nullText`, `width` |
| `pageItem` not bound to a form region | the whole `source { }` block |
| `button` | an `icon { }` block |
| `interactiveGrid` region | `pageItemsToSubmit` (valid on `themeTemplateComponent`) |
| Tabs Container region | `templateOptions` |

A button with **no** `behavior { action: … }` defaults to submitting the page. That is the
simplest way to get a submit button.

### Dynamic actions

`when { selectionType: columns, interactiveGrid: @region, columns: COL }` for grid columns.
There is no donor for an item-change dynamic action; a submit button is usually simpler
and has one.

## Checking your work after an import

The dictionary view column names are not what you would guess, and guessing them costs
round trips. These are correct:

```sql
-- pages and regions
select page_id, page_name from apex_application_pages where application_id = 102;
select region_name, source_type, template, region_source, parent_region_id
  from apex_application_page_regions where application_id = 102 and page_id = :p;

-- grid columns: the column is NAME, not COLUMN_NAME
select region_name, name, item_type, lov_type, lov_source, lov_cascade_parent_items,
       is_primary_key, is_query_only, default_type, default_expression, source_type
  from apex_appl_page_ig_columns where application_id = 102 and page_id = :p;

-- processes: settings are JSON in ATTRIBUTES, not the ATTRIBUTE_nn columns
select process_name, process_type, attributes
  from apex_application_page_proc where application_id = 102 and page_id = :p;

-- items: MAINTAIN_SESSION_STATE shows the storage trap
select item_name, display_as, maintain_session_state
  from apex_application_page_items where application_id = 102 and page_id = :p;

-- available region templates
select template_name from apex_application_temp_region where application_id = 102;
```

Also worth running: `select object_name, object_type from user_objects where status <> 'VALID'`.

**These views are filtered by parsing schema.** Connected as one schema you cannot see
another schema's app at all — pages and regions come back as zero rows rather than an
error.

## Donor exports

<https://github.com/theDaya/apexlangExports> holds two Oracle sample apps in APEXlang, and
they are the best source of syntax that a small export does not contain.

**UX Pattern Catalog** (21 pages): `facetedSearch`, `chart`, `themeTemplateComponent`
(cards, media lists), `classicReport`, drawer forms, dashboards, master-detail,
`staticValues`. No `popupLov`, no `interactiveGrid`.

**sample-interactive-grids** (49 pages): the better donor for anything grid-shaped —
`p00030-basic-editing`, `p00031-validation`, `p00034-form-with-grid`, `p00035-master-detail`,
`p00036-other-column-types` (has the `popupLov`), `p00054/55-editing-in-a-dialog`,
`p00058-dynamic-actions`. 39 grids and 18 auto-row-processing donors.

Neither has a grid-column cascading LOV; the syntax above came from a working example
built by hand.

## Deriving a page from an existing one

Copying a proven page and reworking it beats writing a second one from scratch. Page 3
here is 2,754 lines whose form region, tabs, six grids and save processes are all proven
live. To derive:

1. Copy the file, change `page N (`, `name:` and `title:`
2. Rename every `PN_` item prefix to the new page number — item names are page-scoped, region
   and button ids are too, so nothing else needs renaming
3. Repoint any cross-page links
4. Then make the layout changes you actually wanted

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

- Interactive reports can require a manual "Synchronize Columns" in Builder when their SQL
  changes but the export lacks column definitions. For fixed diagnostic or status screens
  where every column should always show, prefer `classicReport` with explicit columns.
- `classicReport` regions need `componentAppearance { template: @standard }` and explicit
  `column` entries. Classic report columns do not take `source { dataType: … }`.
- Interactive grids need primary-key columns marked `queryOnly: true` and `primaryKey: true`;
  default child foreign keys from the parent page item.
- `switch` is a column type and imports as `NATIVE_YES_NO`. It renders poorly in a narrow
  grid column; a two-value select list is usually better.
- When adding buttons that run PL/SQL, keep long-running work out of the page submit.
  Enqueue a scheduler job or call a package designed for quick validation or preview.

## MFCS Controller Conventions

- Do not copy StyleMan behaviour blindly. StyleMan is visual inspiration only; MFCS flow
  rules come from this repo's backend packages.
- **Lists of values read `MASTER_DATA`, which is what the tenant holds.** `MAP.*` config was
  retired on 2026-09-01: it was a whitelist maintained alongside master data and free to
  disagree with it, which is how a colour the tenant would reject came to be offered.
  Validation checks the same master data the lists read, so the console cannot offer a
  choice the backend then refuses.
- `SKU_SIZE` is a differentiator ID, not a display size. The list shows `7 - 070` and returns
  `070`. Sending a description would be ambiguous - eight size descriptions on this tenant
  map to more than one differentiator.
- `COLOUR` is style/colourway level. Do not add SKU-level colour unless the backend contract
  changes to support several colourways per request.
- The delivery-location list offers **virtual** warehouses only. MFCS refuses ranging against
  a physical location at hierarchy level W, so offering one offers a choice that fails
  several steps later.
- For order creates, expose and default `NOT_BEFORE_DATE`, `NOT_AFTER_DATE`, `OTB_EOW_DATE`,
  `EARLIEST_SHIP_DATE` and `LATEST_SHIP_DATE`. `OTB_EOW_DATE` must fall on the configured
  retail week-ending day.
- Style-level detail is captured once and written to the style and every SKU by the backend:
  UDAs, seasons, tariff codes. Images are the exception - MFCS cascades those itself and
  rejects the child's copy. There is no SKU-level capture for any of them.
- Scheduler job actions can only call procedures visible in the package specification. A
  private package-body helper cannot be invoked from a `DBMS_SCHEDULER` anonymous block.

## Where state lives

- `UI_DRAFT` and its children (`UI_DRAFT_SKU`, `UI_DRAFT_SKU_UPC`, `UI_DRAFT_UDA`,
  `UI_DRAFT_SEASON`, `UI_DRAFT_IMAGE`, `UI_DRAFT_HTS`) - what the console captured
- `REQUEST` - the registered integration request and its stored document
- `STEP` - the ordered step graph and each status
- `ATTEMPT` - endpoint, method, request and response payloads, HTTP status per MFCS call
- `EVENT_LOG` - an autonomous trail that survives a failure

Page 20 (Style Explorer) reads the last four and is the quickest way to see what a request
actually did.

MFCS list and browse endpoints lag newly created records, and `foundation/item` is served
from a cache that can be a minute behind. Do not use them as the only success signal.

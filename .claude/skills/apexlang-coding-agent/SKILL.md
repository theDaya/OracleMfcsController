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

Edit the checked-in export, validate, import, **check the dictionary**, then **run every region's
SQL**. Never skip the last two: validation and import both pass on several mistakes that break the
page at render.

Running the SQL is the step most easily talked out of, and it is the one that catches a whole class
of error the other three cannot see. On 2026-09-10 a card report's outer select named four columns
its own inner subquery did not provide. APEXlang validated it, APEX imported it, the dictionary
showed the region and all nine of its columns, and the page would have failed with `ORA-00904` on
open. Pull the query out of the `.apx` and run it:

```bash
sed -n '/^                select card_title/,/^                 order by seq$/p' pages/p00001-home.apx > /tmp/q.sql
```

Bind variables are the catch. `execute immediate` does **not** bind APEX page items, so a harness
that wraps the query reports `ORA-01008` for every region and tells you nothing. Either substitute
real values into the text before running it, or create a session first and let APEX bind:

```sql
apex_session.create_session(p_app_id => <APP ID>, p_page_id => <PAGE>, p_username => '<PARSING SCHEMA>');
```

```powershell
# SQLcl on this Windows host. -thin avoids needing an Oracle client.
& 'C:\oracleTools\sqlcl\bin\sql.exe' -thin -L 'USER/PASSWORD@//host:1521/service'
```

```sql
apex validate -input "<abs path>\apexlang\<app-folder>" -workspace <WORKSPACE>
apex import   -input "<abs path>\apexlang\<app-folder>" -workspace <WORKSPACE> -id <APP ID> \
              -schema <PARSING SCHEMA> -name "<App Name>"
```

The app ids, workspace, schema and connection wrapper for a given repository belong in that
repository's own documentation, not here.

**`apex export` works. This file said it did not, and that was wrong.** It is the fastest way to
settle any question about a block's shape, and it is how the tabs entry below finally got its right
answer. The flag is `-exptype APEXLANG`:

```sql
apex export -applicationid <APP ID> -exptype APEXLANG -dir "<abs path>\_export_<APP ID>"
```

The `Path.of(null)` this file used to warn about comes from a **mangled path argument**, not from the
command. `printf` in Git Bash eats backslashes - `\U` and `\a` become escapes - and hands SQLcl a path
with characters missing, which it reports as `InvalidPathException: Illegal char`. Write the script
with a quoted heredoc so backslashes survive:

```bash
cat > /tmp/exp.sql <<'EOF'
apex export -applicationid 1234 -exptype APEXLANG -dir "C:\full\path\_export_1234"
exit
EOF
```

Export lands under `<dir>/<app alias><id>/`. Diffing a fresh export against the checked-in copy is
also how you pick up changes someone made in Builder:

```bash
diff -rq apexlang/<checked-in-app> <export dir>/<app alias><id>
```

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
update (select … from t where parent_id = :P3_PARENT_ID) set … where "PK" = :APEX$PK2
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
anything in the thousands — a picker over 48,000 rows is not a select
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

**`slot: tabs` is the whole fix.** Sub-regions join the container with
`layout { parentRegion: @details, slot: tabs }` and that is what turns them into tabs. The container
also takes template options, `t-TabsRegion-mod--pill` being the look worth having. Confirmed by
exporting an app whose tabs had been fixed by hand in Builder and reading what APEX wrote:

```apex
region detail-tabs (
    name: Detail
    type: staticContent
    appearance {
        template: @tabs-container
        templateOptions: [
            #DEFAULT#
            t-TabsRegion-mod--pill
        ]
    }
)
```

**This entry was wrong twice.** It said `slot: subRegions`, which the validator rejects; corrected to
`regionBody`, which validates and imports and then stacks the regions down the page instead of
making them tabs. The right answer is `tabs`. Note the failure mode: `regionBody` produced **no
error at all**, so nothing told you it was wrong except looking at the page.

The general lesson is worth more than the specific one. **When you are unsure of a block's shape,
stop guessing and ask APEX.** Make the change in Builder, export, and read what it wrote - that is
the canonical form by definition, and it costs one round trip instead of five.

### Blocks must be multi-line

`heading { heading: Item }` on one line is rejected with `Invalid token`. Every block needs
its own lines, however short:

```apex
heading {
    heading: Item
}
```

### A process that runs on a button

`serverSideCondition { type: requestIsContainedInValue, value: FETCH }`, where `FETCH` is the
button's `buttonName`. `type: request` is not valid.

### Testing an APEX collection outside a session

`apex_collection` raises `ORA-06501` from a plain SQLcl connection. Create a session first,
then the collection and any `json_table` over `apex_collections` behave exactly as they do on
the page:

```sql
apex_session.create_session(p_app_id => <APP ID>, p_page_id => <PAGE>, p_username => '<PARSING SCHEMA>');
```

That is the fastest way to prove a region's query before importing it.

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

## Block shapes that validate

Building three pages from scratch on 2026-09-10 took roughly a dozen validate rounds, almost all of
them rediscovering the exact shape of a block. Copy these instead. Every one is from a build that
validated, imported and rendered.

**There are no comments in `.apx`.** A `--` line outside a fenced code block is a syntax error, and
the parser reports it as a cascade of "token recognition error" on each fragment of the sentence,
which reads like a corrupt file. Inside ` ```sql ` and ` ```plsql ` fences they are ordinary
comments. Put the reasoning in the PL/SQL package or the docs.

**The app identifier must be upper case**: `app MY_APP_NAME (`, not `app myAppName (`
(`INVALID_EXTERNAL_IDENTIFIER`).

**Numbers are `numberField`**, never `number` - as a page item type and as a grid column type.

```apex
    pageItem P2_CHILD_ID (
        type: selectList
        label {
            label: Child
            alignment: left
        }
        lov {
            type: sqlQuery
            sqlQuery:
                ```sql
                select child_code as d, child_id as r
                  from child_lookup
                 where parent_id = :P2_PARENT_ID
                 order by child_code
                ```
        }
        cascadingLov {
            parentItems: [
                P2_PARENT_ID
            ]
        }
        layout {
            sequence: 40
            region: @grp-identity
            slot: regionBody
            alignment: left
            startNewRow: false
            columnSpan: 3
        }
        appearance {
            template: @required
            templateOptions: #DEFAULT#
        }
        validation {
            valueRequired: true
        }
        source {
            formRegion: @form
            column: CHILD_ID
            dataType: number
        }
    )
```

`parentItems` is a list, and more than one is fine - a subclass cascading on department *and* class
takes both. Use `@required` / `@optional`, not the `-above` variants: floating labels read better on
recent APEX. `default { }` is the block name, not `defaultValue { }`. A page item slot is
`regionBody`; `aboveRegionContent` is rejected.

**A `staticContent` region with HTML takes no `location`:**

```apex
        source {
            htmlCode:
                ```html
                <p>Anything.</p>
                ```
        }
```

**Interactive grid columns** carry their database binding in `source`, not as bare properties, and
every grid needs a `savedReport` child or the import fails with `MINIMUM_COMPONENTS_ERROR`:

```apex
        savedReport primary (
            visibility: primary
            view {
                default: grid
            }
            singleRowView {
                displayedColumns: true
            }

            displayColumn (
                column: @APEX$ROW_ACTION
                layout {
                    sequence: 0
                }
            )

            displayColumn (
                column: @LINE_SIZE
                layout {
                    sequence: 1
                }
            )
        )

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout {
                sequence: 5
            }
        )

        column LINE_ID (
            type: hidden
            layout {
                sequence: 10
            }
            source {
                databaseColumn: LINE_ID
                dataType: number
                queryOnly: true
                primaryKey: true
            }
        )
```

Grid columns reject `settings { displayNullValue }` and `settings { displayExtraValues }`.

**Classic report columns** need a type and a sequence, and there is no way to hide one:

```apex
        column CARD_TITLE (
            type: plainText
            heading {
                heading: Title
            }
            layout {
                sequence: 10
            }
        )
```

`appearance { displayAs: hidden }` is rejected. To order by a column you do not want to show, wrap
the query and order the outer select - `select a, b from ( select a, b, seq from … ) order by seq`.

**A classic report column can be a drill-in link.** Neither donor app has one, so this was written by
hand and validated on 2026-09-10 - `type: link`, with `linkText` deciding what the cell shows:

```apex
        column COMPOSED_ITEM_NO (
            type: link
            heading {
                heading: Item number
            }
            layout {
                sequence: 20
            }
            link {
                target: {
                    page: 4
                    itemNames: [
                        P4_ITEM
                    ]
                    itemValues: [
                        &COMPOSED_ITEM_NO.
                    ]
                }
                linkText: &COMPOSED_ITEM_NO.
            }
        )
```

**A report template's substitutions must all be columns.** The Cards template names `#CARD_TITLE#`,
`#CARD_SUBTITLE#`, `#CARD_TEXT#`, `#CARD_ICON#`, `#CARD_COLOR#`, `#CARD_SUBTEXT#`,
`#CARD_INITIALS#`, `#CARD_LINK#` and `#CARD_MODIFIERS#`. Any one you do not select is printed on the
page **literally**, as the string `#CARD_SUBTEXT#`. Select them all, `null as card_initials` where
you have nothing to say. Check the template file for the list:

```bash
grep -oE "#[A-Z_]+#" shared-components/themes/universal-theme/classic-report-templates/cards.apx | sort -u
```

**Auto row processing takes no table.** `target { }` accepts `returnPksAfterInsert` and nothing
else - no `type: table`, no `tableName` - so grid DML is always `REGION_SOURCE` and always runs
through the region query as an inline view. Keep those queries plain projections. A scalar subquery
in the select list (`(select count(*) …) as code_count`) makes the view unreliable to update
through; move the count somewhere else.

## Showing live data from an API on a page

Read once into an APEX collection in a **before header** process, then let every region query the
collection. The alternative - each region calling the API in its own query - makes one HTTP round
trip per region on every page view, and the regions can disagree with each other because each one
read the remote system at a different moment.

```plsql
l_json := my_api_pkg.get_thing(:P4_ID);
apex_collection.create_or_truncate_collection('THING');
apex_collection.add_member(p_collection_name => 'THING', p_clob001 => l_json);
```

```sql
select t.child_id, t.child_desc
  from apex_collections c,
       json_table(c.clob001, '$.items[0].children[*]'
           columns child_id   varchar2(30)  path '$.id',
                   child_desc varchar2(250) path '$.description') t
 where c.collection_name = 'THING'
```

**Guard every `json_table` branch with `is not null`.** A path that matches nothing still yields one
all-null row, so a document with no seasons renders a blank season row. This bites on top-level paths
over a collection as readily as on nested ones.

Header fields read better as `displayOnly` page items than as another report - a viewer never posts,
so the fact that display-only items are not submitted costs nothing there. Set them with a single
`select … into :P4_A, :P4_B …  from dual` of `json_value` calls in the same process that fetches.

If the API reports *how* it resolved something - which of two endpoints answered, whether a list came
from a live read or a cached feed - put that on the page. It is usually the difference between "there
is no data" and "the data has not published yet".

## Layout that looks right

Two settings, applied consistently, do most of the work:

- **`columnSpan: 3` on every item of a capture screen.** The grid is twelve columns, so threes
  divide evenly into four per row and nothing is stranded. Mixing 2, 3 and 6 - which is what
  "whatever suits each field" produces - leaves ragged rows and items that collide.
- **`@required-floating` / `@optional-floating`.** Floating labels are the current Universal Theme
  look and read better than `@required-above`, which stacks a label over every field and doubles the
  vertical space a form takes.

## Modal dialog pages

A modal page is not `pageTemplate: @modal-dialog` - that fails with
`Conditions not met for reference: @modal-dialog`, because the template requires the page itself to
be a dialog. Declare the mode, and then the template property changes name:

```apex
    appearance {
        pageMode: modalDialog
        dialogTemplate: @modal-dialog
    }
```

`pageMode` lives inside `appearance`, not at page level, and with it set `pageTemplate` becomes
invalid while `dialogTemplate` becomes required. The validator says so in as many words - it named
`dialogTemplate` as the missing required parameter - which is the fastest route through this kind of
question: make the change it complains about and read the next complaint.

**A modal's buttons cannot sit in `slot: edit` or `slot: close` of an `@alert` region.** Alert regions
have neither. Put them in `regionBody`.

## Conditional regions on an item's value

The condition type is `itemIsInColonDelimitedList`, and its property is `list`, not `value`:

```apex
        serverSideCondition {
            type: itemIsInColonDelimitedList
            item: P2_OPERATION_NAME
            list: CREATE_ALL:MODIFY_ORDER
        }
```

`itemInList` is not a type. When a `type:` is rejected the validator prints every valid one, which is
worth reading in full - the list includes `item=value`, `item!=value`, `currentPageInList` and a dozen
others that are hard to guess.

## Navigation that carries context

A **button** passes items as a map:

```apex
        behavior {
            action: redirectThisApp
            target: {
                page: 6
                items: {
                    P6_PARENT_ID: &P2_PARENT_ID.
                }
            }
        }
```

A **classic report column link** uses parallel arrays instead, `itemNames` and `itemValues`. Both
validate; they are not interchangeable, and the button form is the one APEX's own export writes.


## Identity primary keys need `on null`

`generated by default as identity` is not enough. Form and grid automatic row processing sends the
primary key **explicitly as NULL** on insert, and Oracle rejects that rather than generating a
value:

```
ORA-01400: cannot insert NULL into ("SCHEMA"."TABLE"."ID")
```

The page looks completely correct and fails the moment you press Create. Declare every identity
column the console inserts into as:

```sql
parent_id number generated by default on null as identity
```

## Creating a new app

Derive it, the same way you derive a page. Copy the whole export folder, then change exactly four
things: the `app` identifier in `application.apx` (upper case), its `name` / logo `text` /
`APP_NAME` substitution, the `id` in `deployments/default.json`, and the navigation list in
`shared-components/lists.apx`. Delete the pages you do not want and add your own. Everything else -
theme, templates, authentication, plugins - comes across working, which is most of the app.

## Checking your work after an import

The dictionary view column names are not what you would guess, and guessing them costs
round trips. These are correct:

```sql
-- pages and regions
select page_id, page_name from apex_application_pages where application_id = :app;
select region_name, source_type, template, region_source, parent_region_id
  from apex_application_page_regions where application_id = :app and page_id = :p;

-- grid columns: the column is NAME, not COLUMN_NAME
select region_name, name, item_type, lov_type, lov_source, lov_cascade_parent_items,
       is_primary_key, is_query_only, default_type, default_expression, source_type
  from apex_appl_page_ig_columns where application_id = :app and page_id = :p;

-- processes: settings are JSON in ATTRIBUTES, not the ATTRIBUTE_nn columns
select process_name, process_type, attributes
  from apex_application_page_proc where application_id = :app and page_id = :p;

-- items: MAINTAIN_SESSION_STATE shows the storage trap, and the layout columns
-- are ITEM_LABEL_TEMPLATE and GRID_COLUMN_SPAN - not FIELD_TEMPLATE or COLUMN_SPAN,
-- both of which exist on other views and cost a round trip each to guess
select item_name, display_as, maintain_session_state,
       grid_column_span, item_label_template, lov_cascade_parent_items
  from apex_application_page_items where application_id = :app and page_id = :p;

-- available region templates
select template_name from apex_application_temp_region where application_id = :app;
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

Copying a proven page and reworking it beats writing a second one from scratch - a large page whose
form region, tabs, grids and save processes already work is worth far more as a starting point than
as a reference. To derive:

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
- Scheduler job actions can only call procedures visible in the package specification. A
  private package-body helper cannot be invoked from a `DBMS_SCHEDULER` anonymous block.

## What does not belong in this file

This skill is about APEXlang and Oracle APEX, and nothing else. Application ids, workspace and schema
names, table names, business rules, which list of values reads what - all of that belongs in the
repository being worked on, not here. If you learn something while building one app that would only
ever be true for that app, write it in that repository's documentation and leave this file generic.

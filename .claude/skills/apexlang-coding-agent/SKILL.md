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

## The traps that cost real time

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

### An interactive grid's savedReport must list its displayColumn entries

Defining `column` blocks on the region is not enough. The *report* decides what is
displayed, and a `savedReport` without `displayColumn` entries registers **zero** report
columns - which the dictionary will confirm:

```sql
select rc.page_id, c.name, rc.display_seq, rc.is_visible
  from apex_appl_page_ig_rpt_columns rc
  join apex_appl_page_ig_columns c on c.column_id = rc.column_id
 where rc.application_id = :app
 order by rc.page_id, rc.display_seq;
```

The page then fails at render, in the browser, with:

```
TypeError: Cannot read properties of undefined (reading 'nodeType')
    at Object._selectRows (widget.grid.min.js)
    at Object._setSelection (desktop_all.min.js)
```

The grid has a control break and aggregates but no row structure to hang them on, so the
selection code walks into nothing. Nothing server-side complains: it validates, it
imports, the region and all its columns appear in `apex_appl_page_ig_columns`, and only
the report-columns view shows the hole.

Every column the report should show needs an entry, **including the control-break
column**:

```apex
        savedReport Main (
            visibility: primary
            name: Main
            view {
                default: grid
                stretchColumns: false
            }

            displayColumn (
                column: @PLAN_MONTH
                layout {
                    sequence: 20
                }
            )

            sort (
                column: @PLAN_MONTH
                sort {
                    direction: asc
                    nulls: last
                    sequence: 1
                }
            )

            controlBreak (
                column: @PLAN_MONTH
                sort {
                    direction: asc
                    nulls: last
                }
                layout {
                    sequence: 1
                }
            )
        )
```

Columns with no `displayColumn` entry still exist and stay available to the user through
Actions - they are simply not in the default report.

### A read-only grid must not declare editable column types

`edit { enabled: false }` with columns typed `numberField`, `textField` or `selectList` is
contradictory: the column type is what renders an input. Use `displayOnly` (or `link`, or
`hidden`) throughout, and drop `queryOnly: true` with them - there is nothing to mark
query-only on a column that was never going to be written.

```sql
select name, item_type from apex_appl_page_ig_columns
 where application_id = :app and page_id = :p
   and item_type not in ('NATIVE_DISPLAY_ONLY','NATIVE_HIDDEN','NATIVE_LINK');
```

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
| `interactiveGrid` region | `pageItemsToSubmit` - see below, it is a feature gate rather than a flat prohibition |
| Tabs Container region | `templateOptions` |

A button with **no** `behavior { action: … }` defaults to submitting the page. That is the
simplest way to get a submit button.

`pageItemsToSubmit` is the one in that table worth stating precisely, because the flat
reading is wrong. The compiler says:

```
- conditional pageItemsToSubmit (when (type FEATURES [AJAX_ITEMS_TO_SUBMIT]))
```

So it is gated on the region type declaring that feature, not forbidden outright. It is
rejected on an interactive grid because a grid does not declare it; it is accepted on a
`themeTemplateComponent` because that does. Worth remembering as a shape: several
"rejected" properties are really conditional ones whose condition is unmet, and the
rejection message does not say so. The property query above does.

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

## Starting a new app, and the theme decision that follows you everywhere

**A subscribed theme is what makes `@/` references resolve.** This is the single most
expensive thing to get wrong when scaffolding a new app, because every symptom it causes
looks like something else.

```apex
theme universal-theme (
    themeNumber: 42
    baseTheme: ut-26.1        <- subscribed: templates come from the base theme
)
theme universal-theme (
    themeNumber: 42
    version: 1.3              <- a local copy: every template must be in the export
)
```

There are two reference forms and the theme decides which one works:

| Form | Means | Works when |
| --- | --- | --- |
| `@/standard` | a template in the base theme | the theme declares `baseTheme:` |
| `@standard` | a component defined in this export | the export ships `themes/.../region-templates/standard.apx` |

Copying an older app's scaffolding gets you the second kind: a `version:`-style theme plus
several dozen local template files. Everything validates until you reference a template
that app never used - `@cards-container`, say - and then it is `REFERENCE_NOT_FOUND` with
no hint that the fix is a different theme entirely. Switching to `baseTheme:` lets you
delete the whole local subset and reference anything the theme offers.

Oracle's own failure map states the diagnosis as a lookup, and it is worth memorising in
that form: **widespread `REFERENCE_NOT_FOUND` across page templates, region templates,
labels, lists or theme defaults - `@/standard`, `@/title-bar`, `@/breadcrumb`, `@/text`,
`@/side-navigation-menu` - means look at `theme.apx` first**, for a missing Universal Theme
`baseTheme` binding or a stale `version` field. The individual missing references are
downstream symptoms. Chasing them one at a time is the expensive path, and the breadth of
the failure is the clue: one wrong reference is a typo, forty is the theme.

**Scaffold from an app that validates, and validate it first to prove it does.** Validating
the donor is a two-minute experiment that tells you whether a pattern is sound before you
spend an hour deciding your copy of it is broken.

**`currentTheme:` and `currentThemeStyle:` keep the bare `@`.** They name components declared
in the export, not templates. So does `list: @desktop-navigation-menu`, and so does an item's
`region: @some-region`. A blanket search-and-replace of `@x` to `@/x` will break all three -
`region:` is especially easy to miss, because theme.apx also has a `region:` property and
there it *is* a template.

## Slot names are scoped to their container

`slot:` is not one vocabulary. The valid values depend on what the thing sits inside:

| The thing | Its slots come from | Typical values |
| --- | --- | --- |
| a region | the **page** template | `body`, `breadcrumbBar`, `banner`, `footer` |
| an item | its **region** template | `regionBody` |
| a button | its **region** template | `rightOfTitle`, `top`, `next`, `belowBox` |
| a sub-region | its **parent region** template | `subRegions`, `tabs`, `regionBody` |

So `slot: contentBody` is right for a region on the Login page template and wrong for one
on Standard, which wants `body`. Never sed `slot:` across a whole app - fix them per
container. Validation names the valid set for the exact context, so one round trip per
slot is enough.

## Buttons are page-level, positioned into a region

A `button` nested inside a `region` block fails with `COMPONENT_NOT_FOUND: button x not
found`. Declare it at page level and point it at the region:

```apex
    button new-pot (
        buttonName: NEW_POT
        label: New Pot
        layout {
            sequence: 10
            region: @intro
            slot: rightOfTitle
        }
        appearance {
            buttonTemplate: @/text-with-icon
            hot: true
            icon: fa-plus
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 100
                clearCache: 100
            }
        }
    )
```

**A button's behavior takes `action:`; a card action's takes `type:`.** Same idea, two
property names, and the error for using the wrong one names the property rather than the
mistake.

## Passing item values in a target

`items:` with a colon, and the block is a map:

```apex
            target: {
                page: 10
                clearCache: 10
                items: {
                    P10_POT_ID: &POT_ID.
                }
            }
```

`items {` without the colon is `Invalid token: items {`, and the three closing braces that
follow all report as errors too, which makes it look like a much deeper structural problem
than a missing character.

## Cards are a native region type

Do not build cards from a `classicReport` with the Cards template and `#CARD_SUBTEXT#`
substitutions. Those substitution strings print literally when a template names one you did
not populate. `type: cards` binds real columns:

```apex
    region pots (
        type: cards
        source { location: localDatabase, type: sqlQuery, sqlQuery: ... }
        appearance {
            template: @/cards-container
            templateOptions: [ #DEFAULT#, t-CardsRegion--styleA ]
        }
        card       { primaryKeyColumn1: POT_ID }
        title      { column: POT_NAME }
        subtitle   { advancedFormatting: true
                     htmlExpression: &POT_CODE. &middot; &SEASON_NAME. }
        body       { column: DEPARTMENT_NAME }
        secondaryBody { advancedFormatting: true
                        htmlExpression: &STYLE_COUNT. styles }
        iconAndBadge  { iconSource: iconClassColumn
                        iconColumn: ICON_CLASS
                        iconCssClasses: fa
                        badgeColumn: POT_STATUS
                        badgeCssClasses: &STATUS_CSS. }

        action open ( ... )
    )
```

`templateOptions` values are validated against the template, and the valid strings are not
always what they look like: it is `t-CardsRegion--hideHeader js-addHiddenHeadingRoleDesc`,
one string including the js- class, not `t-CardsRegion--hideHeader`.

## staticContent holds its markup in source

```apex
        type: staticContent
        source {
            htmlCode:
                ```html
                <p>...</p>
                ```
        }
```

Not `staticContent { html: ... }`.

## `&` in a SQLcl argument hangs the command

```sql
apex import ... -name "Office UK Range & Buy Control"
```

SQLcl reads `&` as a substitution variable, prompts for it, and blocks on stdin that never
arrives. The command does not fail - it hangs until something kills it, and nothing is
created, so it reads exactly like a slow import of a large app. A 149K app timing out after
five minutes is this, not size. Put `set define off` at the top of every script that runs an
`apex` command, and prefer a `-name` without an ampersand.

## Plugins referenced by component-settings must be present

Copying `shared-components/component-settings.apx` from another app brings its
`componentSetting` blocks with it, including ones naming plugins you did not copy:

```
Type: PLUGIN_NOT_FOUND
Error: Plugin not found for componentSetting component: plugin/select2
```

Drop any `componentSetting` block whose `name:` starts `plugin/` unless you copied the
plugin too. The error helpfully lists every valid built-in item type, which is a useful
reference in its own right.

## Item names are unique across the application, not per page

Declaring `P10_POT_NAME` on page 10 and again on page 30 - so a breadcrumb on page 30 can
show the pot it belongs to - fails with `DUPLICATED_COMPONENT`. Page prefixes are a naming
convention, not a namespace.

An ancestor's items are set into session state instead, from the descendant's own
before-header process:

```plsql
apex_util.set_session_state('P10_POT_ID', l_pot_id);
apex_util.set_session_state('P10_POT_NAME', l_pot_name);
```

This is what makes a deep breadcrumb work when the page is reached from a bookmark rather
than by clicking down through the hierarchy - otherwise the trail renders with blank crumbs
linking nowhere.

## label is a block on an item and a scalar on a button

```apex
    pageItem P120_COLOUR_NAME (
        label {
            label: Colourway name
            alignment: left
        }
    )

    button create (
        label: Create Colourway
    )
```

Worth knowing before a search-and-replace: converting every `label:` to a block breaks
every button on the page, and the error - `Invalid property: label` - names the same
property in both cases.

Two more of this shape:

- An item's field template is `appearance { template: @/required-floating }`, not
  `fieldTemplate:`.
- `maximumLength` is not a `settings` property on a page item.

## Form regions and the items bound to them

```apex
    region commercial (
        type: form
        source {
            location: localDatabase
            tableName: RBC_COLOURWAY
        }
    )

    pageItem P30_SUPPLIER_NO (
        source {
            formRegion: @commercial
            column: SUPPLIER_NO
            dataType: varchar2
        }
    )
```

Not `type: table` / `table:` on the region, and not `type: databaseColumn` /
`databaseColumn:` on the item. The region's `source.type` accepts only `functionBody`,
`propertyGraph`, `sqlQuery` and `tableView` - a plain table is named with `tableName` and
no `type` at all.

## Breadcrumb blocks

An entry's parent goes inside `appearance`, and a breadcrumb *region* must name its
template in `componentAppearance`:

```apex
    entry style (
        name: &P20_STYLE_DESC.
        pageNumber: 20
        appearance {
            parentEntry: @pot
        }
        link {
            target: {
                page: 20
                items: {
                    P20_STYLE_NO: &P20_STYLE_NO.
                }
            }
        }
    )
```

```apex
    region breadcrumb (
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        appearance {
            template: @/title-bar
        }
        componentAppearance {
            breadcrumbTemplate: @/breadcrumb
        }
    )
```

## Classic report columns take no display condition

There is no `appearance { displayCondition { } }` on a `column`. A column that exists only
to order a `union all` cannot be hidden that way - leave it out of the column list
entirely, or drop it from the query.

## Proving a region's SQL: substitute, do not bind

`dbms_sql` does not bind APEX page items even inside an `apex_session.create_session`, so a
harness that parses each region's query reports `ORA-01008: value for bind variable
placeholder was not provided` for every one of them and proves nothing. Substitute the
values into the text first:

```plsql
    function bound(p_sql in varchar2) return varchar2 is
        l_s varchar2(32767) := p_sql;
        procedure sub(p_item in varchar2) is
        begin
            l_s := replace(l_s, ':' || p_item, '''' || v(p_item) || '''');
        end;
    begin
        sub('P10_POT_ID');
        sub('P20_STYLE_NO');
        return l_s;
    end;
```

Then `dbms_sql.parse` each one wrapped in `select count(*) from ( ... )`. Keep it as a test
file rather than a scratch script: it is the only check that catches a column the query
does not actually provide, and it is worth re-running after every import.

## Ask the compiler what a block takes; do not infer it

This is the single biggest time-waster in APEXlang work, and it is a process mistake
rather than a knowledge one. Writing a block from what its properties *ought* to be
called, then letting validation correct them one at a time, costs a round trip per
property. `savedReport` took three: `type: primary` (wrong), a missing `visibility`, then
a missing `name`.

**There is an oracle for this, and it is not guesswork or a donor.** Oracle's own APEXlang
skill ships a tool that reads the *compiler's* property metadata out of SQLcl. It is
vendored at `tools/oracle-apexlang/` and needs nothing but `node` and SQLcl on PATH:

```bash
node .claude/skills/apexlang-coding-agent/tools/oracle-apexlang/query-valid-props.mjs      --component savedReport --component-type-id 7050
```

```
Using compiler metadata from SQLcl/Oracle runtime (build=26.1.0+3102, source=path_sqlcl)
savedReport [componentTypeId=7050]   propertyCount: 12

[identification]
- active      visibility (required; lovType=STATIC)
  value: primaryDefault | value: alternativeDefault | value: public | value: private
- conditional name (required; when (visibility NOT_EQUALS PRIMARY_DEFAULT))
- active      staticId (required)
```

Exact properties, requiredness, valid values and the conditions that gate them, for the
build actually installed. Useful flags: `--group <name>` to narrow to one block,
`--parent <name>` and `--component-type-id <id>` to disambiguate (component names repeat -
`savedReport` is 7050 for an interactive report and 7950 for a grid), `--list` to
enumerate candidates, `--json` for machine output.

Run it **before** writing any block you have not written before. Donors drop to what they
always were - worked examples showing a shape in context - and validation goes back to
catching what you changed rather than discovering the schema.

When the tool cannot answer (it is ambiguous about a nested child, or SQLcl is not
reachable), fall back to the donor: `grep -A20` the block out and start from that text.

```apex
        savedReport Main (
            visibility: primary
            name: Main
            view {
                default: grid
                stretchColumns: false
            }
        )
```

```apex
        savedReport Main (
            visibility: primary
            name: Main
            view {
                default: grid
                stretchColumns: false
            }
        )
```

Before writing any block you have not written before, `grep -A20` it out of a donor and
start from that text. Validation is for catching what you then changed, not for
discovering the schema.

The same applies to whole features. A grid column that links to another page:

```apex
        column PLAN_LINE_REF (
            type: link
            link {
                target: {
                    page: 50
                    clearCache: 50
                    items: {
                        P50_PLAN_LINE_ID: &PLAN_LINE_ID.
                    }
                }
            }
            source {
                databaseColumn: PLAN_LINE_REF
                dataType: varchar2
            }
        )
```

## Control breaks and aggregates live in the savedReport

Not on the region, and not on the column:

```apex
            controlBreak (
                column: @PLAN_MONTH
                sort {
                    direction: asc
                    nulls: last
                }
                layout {
                    sequence: 1
                }
            )

            aggregate units-total (
                column: @UNITS
                function: sum
                showGrandTotal: true
                tooltip: Units
            )
```

## More of the slot vocabulary

The rule keeps costing round trips, so the values worth memorising:

| Container | Item slot | Button slot |
| --- | --- | --- |
| Standard region | `regionBody` | `rightOfTitle`, `edit`, `create`, `next`, `previous` |
| Interactive grid | `regionBody` | `edit`, `create`, `copy`, `close`, `next` |
| Standard page template | region: `body` | |
| Modal dialog page | region: `contentBody` | |
| Login page | region: `contentBody` | |

An item and a button in the *same* region can need different slot names, because the two
lists are separate. `searchFieldAndSmartFilters` is an interactive *report* slot and is
not valid on a grid.

## A grid cannot compose an identifier, and should not be asked to

Where a table has a derived key column, the honest options are a trigger or a process that
runs straight after row processing. Without `CREATE TRIGGER`, the second:

```apex
    process save-curve (
        type: interactiveGridAutoRowProcessing
        editableRegion: @curve
        execution { sequence: 10 }
    )

    process sync-curve (
        type: executeCode
        source {
            plsqlCode:
                ```plsql
                begin
                    my_pkg.sync(:P50_PARENT_ID);
                end;
                ```
        }
        execution { sequence: 20 }
    )
```

Make the derived column nullable and `queryOnly: true` so the grid displays it and never
writes it. The window where a row has no key value lasts one request, inside one
transaction. Put the real validation in that same procedure: a grid enforces what its own
list of values offers and nothing else, so rules about what a row must satisfy belong
behind it.

## Rules Oracle states up front that we learned from the crash

From Oracle's own APEXlang contracts. Each of these is a MUST there, and each corresponds
to something in this file discovered by breaking it. Prefer them as preventive rules:

- **Every interactive grid needs at least one `savedReport`, and every `savedReport` needs
  explicit `displayColumn` children.** This is the rule whose violation produces the
  `nodeType` crash documented above. Never `column (...)` children inside a grid's saved
  report - that is interactive *report* syntax.
- **`keyColumn` is required on an interactive grid.**
- **One source mode only.** Query-backed means `source.type: sqlQuery` plus
  `source.sqlQuery`, and then no `tableName`, no `whereClause`, no `orderByClause` - put
  the ordering inside the query. Table-backed means `source.tableName`, and `orderByClause`
  is allowed but every identifier in it must match a declared `column` in the same region
  (hidden columns count).
- **`.apx` files must be LF.** Git on this Windows host will happily convert them; watch
  for `LF will be replaced by CRLF` warnings on `.apx` paths.
- **Do not copy classic or interactive report column-link syntax into a grid column.**

## When validation fails with a code, look it up before reasoning about it

`tools/oracle-apexlang/validator-fix-recipes.json` maps 119 validator error codes to a
cause and a deterministic fix:

```bash
node -e "const r=require('./.claude/skills/apexlang-coding-agent/tools/oracle-apexlang/validator-fix-recipes.json').recipes; console.log(JSON.stringify(r['<CODE>'],null,2))"
```

## What Oracle's APEXlang skill is, and what it is not

<https://github.com/oracle/skills/tree/main/apex> - 826 files, UPL licensed, targeting
APEX 26.1, the same build as here.

**Take from it:** the property query and the fix recipes above, both vendored under
`tools/oracle-apexlang/`, and its component contracts under
`apex/apexlang/templates/region-components/` when you want a canonical shape.

**Do not treat it as a replacement for this file.** It documents syntax and structure
thoroughly and says almost nothing about what misbehaves after a clean import. Verified
absent from the entire tree: `returnPksAfterInsert` (missing from its grammar *and* its
auto-row-processing template), the `REGION_SOURCE` silent zero-row update, `PLS-00428`
from an LOV starting with a comment, the `hidden` vs `displayOnly` session-state trap, and
the `&`-in-a-SQLcl-argument hang. Its grammar is also thinnest exactly where this project
lives: `interactiveGrid` appears five times in 1.1MB and there is no interactive-grid
reference domain at all.

It is also Oracle's *internal* APEX-development skill, published. Its failure map's
confirming checks name `wwv_flow_imp*`, `gen_api_pkg.plb` and `pe_data_checks.sql`, which
need the APEX source tree. Read those rows for the diagnosis, not the instruction.

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

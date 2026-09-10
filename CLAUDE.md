# Working on this repository

A PL/SQL + ORDS integration layer that turns a legacy PLM/Office document into the sequence of Oracle
MFCS REST calls needed to create and modify styles and purchase orders, plus a React console for
driving and inspecting it.

## Read these first

- `docs/status-and-next-steps.md` — what is proven, what has never run live, what is outstanding
- `docs/database-objects.md` — what every table and package does, and why the non-obvious ones exist
- `docs/mfcs-actual-call-flow.md` — real payloads from runs that actually succeeded
- `docs/apex-console.md` — the two APEX apps, their ids and commands, the conventions both
  follow, and where console state lives. Everything MFCS-specific about the consoles is here
- `.claude/skills/apexlang-coding-agent/SKILL.md` — how to edit APEXlang itself: the
  validate/import/export loop, the traps that pass validation and break at render, the block
  shapes that actually compile, and the dictionary views for checking an import. **Deliberately
  generic** - it knows nothing about MFCS, and anything learned that is only true of this
  repository belongs in `docs/apex-console.md` instead. Loads automatically when you work on
  `apexlang/`, but read it first if you are touching a console at all.

Keep those four current. If you change behaviour they describe, update them in the same commit.

## Ground rules

**This project only ever talks to the real MFCS dev tenant.** There are no simulators and no client-mode
switch. `MOCK`, `PUBLIC_MOCK`, `LOCAL_MFCS` and `MFCS_CLIENT_MODE` were deliberately removed — any
reference you find is stale and should go.

**Ground claims in the tenant, not in general knowledge.** `docs/mfcs-openapi/openapi.json` is the
tenant's own contract (26.1.201.0) and beats Oracle's public documentation for what *this* instance
serves. But it is not exhaustive: the tenant also serves `RmsReSTServices/services/private/Item/itemDetail`,
which is absent from the spec and is the only way to read a style with its children in one call.
"Not in the spec" is not "not available" — probe.

**Every operation sends its whole write set, every time.** `MODIFY_STYLE`, `CREATE_ORDER` and
`MODIFY_ORDER` all run the same seven-step style sequence — SKU check, hierarchy, sourcing, country of
manufacture, UDAs, ranging, approval — and the order operations then place the order on top of it.
Nothing is skipped because it "looks unchanged". This layer receives a document saying what the style
should now be, not a diff, so the only safe reading is that all of it may have changed; and MFCS
answers a write that changes nothing with SUCCESS, so an omission would never announce itself. Do not
add "only send X if X differs" logic. An order implies style-level writes: ordering is a statement
about the style's cost, country and supplier, not only about the order.

The one conditional step is `ENSURE_STYLE_SKUS`, and it conditions on the *tenant*, not on this
database — a colour or size the style lacks has to become a new child before anything can reference
it. Resume is also not an exception: skipping completed steps continues one interrupted request,
which is not the same as a fresh request deciding to do less.

**Verify writes by reading back.** MFCS returns HTTP 200 `SUCCESS` for an `items/update` that changes a
differentiator and silently does nothing. A success response is not evidence that anything happened. This
is why `ENSURE_STYLE_SKUS` re-reads the style after creating children rather than trusting four 200s.

**Do not let the test suite's result arrive after the commit.** Run it, read it, then commit.

## Before you suspect the code

Bearer tokens last one hour. A stale token makes every MFCS step fail with `-20950`, and
`tests/resume_coverage_tests.sql` then reports roughly half its assertions failed. That is not a
regression.

```bash
curl -s http://localhost:5173/api/token-status     # decodes the JWT's own exp claim
```

**A token is scoped to one tenant, and `token-status` cannot tell you which.** It decodes `exp`, not
the audience, so a perfectly valid UAT token against `MFCS_BASE_URL` pointing at STG reports VALID and
then every call returns **HTTP 403** - verified 2026-09-10. Swapping environments means changing both.
A 403 here means the wrong tenant, where a 401 means the token itself; and a hostname for a tenant that
does not exist (`tst3`, `dev3`) also answers 401, from the edge rather than from MFCS.

The token is issued in Postman (`postman/`) and loaded with `deploy/adb-free/set_token.sql`. The user
sometimes updates the row by hand, so do not trust `SECRET.UPDATED_AT` — trust the decoded claim.

## Layout

```
database/10_tables/     tables, constraints, config seed
database/20_packages/   one file per package, numbered in DEPENDENCY order
database/30_ords/       ORDS module and handlers
deploy/adb-free/        install, schema/ACL setup, probes, token loader
tests/                  live tests - they create real tenant records
ui/                     React console (Vite, proxies /api to ORDS)
docs/                   the three documents above, plus the tenant OpenAPI spec
```

The numbering in `20_packages/` is load order, not decoration. Each file holds a package's spec **and**
body, so anything a body calls must already exist. `payload_pkg` is called statically by
`orchestrator_pkg`, which is deliberate: a missing mapper should be a compile error, not a runtime one.

## Running things

```bash
# Install from zero, as the schema owner (MFCS_INTEGRATION)
@deploy/adb-free/install.sql          # directory name is legacy; run it against mdutils
@deploy/adb-free/99_verify.sql        # expect zero invalid objects

# Fault-injected failure and resume coverage - CREATES REAL TENANT RECORDS
@tests/resume_coverage_tests.sql      # expect 20 passed, 0 failed

cd ui && npm install && npm run dev   # http://localhost:5173
```

**The database is `mdutilstst01`, not a local container.** Oracle 23.26.2.0.0, PDB `FREEPDB1`, schema
`MFCS_INTEGRATION`. It is a normal Oracle server: plain TCP on a service name, no wallet, no TCPS, and
`TNS_ADMIN` is irrelevant. This is where the console deploys and where live requests actually run.

```bash
deploy/mdutils/sql.sh script.sql                        # run a file
echo "select count(*) from request;" | deploy/mdutils/sql.sh
deploy/mdutils/sql.sh deploy/mdutils/token_status.sql   # check the token first, always
```

Credentials live in `deploy/mdutils/connect.env`, which is gitignored and must stay that way - this
repository has a public remote. `deploy/mdutils/README.md` says how to recreate it.

Use the **service-name** form, `//host:1521/FREEPDB1`. The colon form `host:1521:FREEPDB1` is SID
syntax and will not connect. The wrapper appends `exit`, because SQLcl otherwise sits in its REPL until
it is killed, and strips the JVM warnings it prints before every result.

**The coverage suite needs `set sqlblanklines on` and `sql.sh` does not set it.** Run through the
wrapper as-is, `tests/resume_coverage_tests.sql` produces no output at all - just
`exit *  ERROR at line 1: ORA-00900`, which reads like a broken connection and is not one. SQLcl
treats a blank line inside a PL/SQL block as the end of the statement, the suite's one large block is
full of them, so nothing is ever executed and the appended `exit` is what reaches the server. Prepend
the setting:

```bash
source deploy/mdutils/connect.env
{ printf 'set sqlblanklines on\n'; cat tests/resume_coverage_tests.sql; printf '\nexit\n'; } > /tmp/rct.sql
"$SQLCL" -thin -S -L "$DB_CONN" "@/tmp/rct.sql"
```

**Never run two coverage suites at once.** Each scenario injects its fault by rewriting a shared
`CONFIG` row and restores it afterwards, so overlapping runs correct each other's faults and report
failures that are not real. Piping a run into `head` does not stop it either - the server keeps going
after the pipe closes.

The `adb-free` container in older notes is not running and is not the deployment target.

## Tenant behaviour that will cost you a day

All verified live. Most are silent failures, which is why they are worth memorising.

- **A colour change cannot be applied to an existing SKU.** A diff combination *defines* the item, so a
  new colour means new children. `items/update` accepts the change and ignores it.
- **Unknown query parameters are silently ignored**, returning an unfiltered feed that looks like a
  working filter. It is `deptId`, not `dept`. There is no `itemParent` filter.
- **List endpoints are publish/delta feeds**, not queries — approved and published records only, with a
  few seconds of lag. Empty does not mean absent.
- **STG and UAT do not carry the same UDAs, and STG is the smaller.** Verified live 2026-09-10: STG
  publishes 23, UAT publishes 27, and UAT is a strict superset. The four STG lacks are `66040` Style
  (`LV`, 13,693 values, every one a distinct five-digit number with a model name), `56038` Supplier
  Colour and `61038` Supplier Colour Code (both `FF`, free-form, no value list) and `56039` Launch Date
  (`DT`). Nothing here can create them - `foundation/uda` is GET only and `item/uda/*` only associates
  an existing UDA with an item - so they have to be loaded inside MFCS. Note the size: UAT's UDA feed
  is 2.2MB against STG's 112KB, nearly all of it Style's values, and `master_pkg.load_udas` stores each
  UDA's raw JSON in `MASTER_DATA.ATTRIBUTES`.
- **Which foundation services publish depends on the tenant, and it changed.** Verified 2026-09-01.
  On STG `uda` (23), `supplier`, `store` and `warehouse` now return data; `diffid`, `diffgroup`,
  `difftype` and `merchhier/*` are still HTTP 200 with zero rows. On UAT **everything** publishes -
  `diffid` 380, `diffgroup` 13 (with a `details` array naming each group's member diffs), `difftype` 4,
  and all three `merchhier` levels. Deriving hierarchy, differentiator and supplier values from the item
  and order feeds is therefore a STG workaround, not a permanent necessity - the `SOURCE` column on
  every master-data row exists so the two origins stay distinguishable. Paths are case-sensitive and
  easy to get wrong: it is `diffid`, not `diffId`, and `merchhier/deps`, not `merchhier/department`;
  both wrong forms 404 rather than returning empty.
- **`OTB_EOW_DATE` must fall on a Sunday** (the retail week end). MFCS only enforces it at order create,
  by which point a style exists and an order number is burned, so validation checks it up front.
- **Item ranging needs the virtual warehouse** (19271), not the physical location (1927). Both mappers
  translate through `MAP.ORDER_LOCATION.*` so they cannot disagree.
- **A purchase order ranges its own items**, so `CREATE_ITEM_LOCATIONS` only matters for style-only creates.
- **Approval requires sourcing and country of manufacture first.**
- **Parent styles carry differentiator *groups*** (`RMS_ALL_C`/`ALL`); children carry *concrete* diff IDs.
  That is how *we* create them, not a tenant law: a real UAT style carries a concrete colour (`100`,
  Black) with a size *group* (`ADULT_NUM`). The authoritative discriminator is `diff1Level` /
  `diff2Level`, which reads `ID` or `GROUP`. We do not read it anywhere yet.
- **Order read and write disagree on names**: read gives `physicalQuantityOrdered` / `originCountryId`,
  write wants `quantityOrdered` / `originCountry`.
- **`purchaseOrders/update` is header-only in practice.** It answers SUCCESS while ignoring the
  `details` array entirely — even a quantity change on the order's own lines. Lines have their own
  services: `purchaseOrder/details/create|update|delete`, and `details/update` is proven live.
- **`quantityCancelled` is cumulative-absolute; never send it.** A repeat of a line's existing
  cancelled quantity is a silent no-op. `quantityOrdered` is authoritative: full cancellation is
  `quantityOrdered:0` + `cancelInd` + `cancelCode` (ORCA codes: `S` switch, `B` reduction).
- **A child's colour diff must belong to the parent's diff group** (`RMS_ALL_C` here). A colour
  outside it is rejected loudly at items/create - one of the few loud failures.
- **Order line changes take ~30 seconds to appear** in the procurement read — far longer than the
  few seconds of feed lag elsewhere. A read-back that concludes too early reports a silent failure
  that did not happen.
- **Resume replays the *stored* payload.** A request that failed on a bad value in that payload cannot be
  rescued by resuming; it needs a fresh request. The console's Retry button handles this: it rebuilds
  the document from the draft and, if that no longer matches what was stored, gives the draft a new
  ACTION_REQUEST_ID so the corrected version goes in as a fresh request rather than a 409.
- **`FAILED_NO_SIDE_EFFECT` is always resumable, and the name is the reason** - nothing was created, so
  re-running cannot duplicate anything. It used to resume only when the stored response mentioned
  `MFCS_BATCH_WINDOW_ACTIVE`, which meant a request that failed on a stale-token 401 replayed its own
  failure for ever and could never be retried, even once the token was good again.
- **`foundation/item/{item}` is a feed read** and 404s on a style created minutes ago. `itemDetail`
  returns it in full. Never build on the feed anything that must see a fresh record.
- **`foundation/item` is served from a cache and lags roughly a minute.** The document carries its own
  `cacheTimestamp` and `cacheCreateTimestamp`. A read-back inside that window shows the record without
  the write you just made, which reads exactly like one of this tenant's silent failures and is not one.
  Check `cacheTimestamp` before concluding a write was ignored.
- **`foundation/item` cannot see level 3 at all.** `itemLevel=3` returns zero rows and a direct read of
  a barcode 404s, on both STG and UAT. Reference items are visible in two other places: `itemDetail`,
  and the parent SKU's own `referenceItem` array.
- **`itemDetail` uses a third set of field names**, neither the feed's nor the write services':
  `classAttribute`, `itemDesc`/`shortDesc`, `primarySuppInd`, `originCountryId`, `suppPackSize`.
  The same concept keeps being renamed. Item number type is `itemNumberType` on write, and `itemNoType`
  inside `referenceItem` on read. The primary-reference flag is `primaryReferenceItemInd` on write and
  `primaryRefItemInd` on read. Assume a rename until you have checked.
- **An image is written to the style only, never to its SKUs.** MFCS cascades it down, and the child's
  own copy then comes back as `Same file name already exists for this item`. UDAs and seasons are the
  opposite - they are written to the parent and every child. There is no rule here to infer; each
  service had to be tried.
- **An HTS row's `originCountry` must be a country the item already holds as a country of
  manufacture**, or MFCS answers `This item does not have a Country Of Manufacture. Field:
  ORIGIN_COUNTRY_ID`. That makes `CREATE_ITEM_HTS` dependent on `CREATE_ITEM_COUNTRIES_OF_MANUFACTURE`
  having run, which is why it sits after it in the graph and defaults to `MFCS_MANUFACTURER_COUNTRY`.
- **`primaryImageUrl` is derived, not sent.** MFCS concatenates `imageAddress` and `imageName`, so the
  address wants its trailing slash and the name is the file.
- **UDA writes need `displayType`, and it selects the value field.** `item/uda/create` requires
  `udaId` and `displayType` per row; `LV` then uses `udaValue`, `FF` uses `udaText`, `DT` uses
  `udaDate`. Sending an empty `uda` array is accepted and does nothing. `item/uda/update` is not
  symmetric with create: it identifies the existing row by its current value and carries the change in
  `newUdaValue` / `newUdaText` / `newUdaDate`. `items/create` also accepts a nested `uda` array, so
  UDAs can ride along at create time instead of needing their own call.
- **A barcode cannot be created until its parent SKU is out of worksheet status.** MFCS answers
  `This item's parent must be in submitted status before the item can be submitted`. This is why
  `CREATE_REFERENCE_ITEMS` runs *after* `APPROVE_ITEMS` rather than next to the child create, where it
  looks like it belongs. Proven both ways live: it failed at sequence 45 against freshly created
  worksheet SKUs, and succeeded at 85 against the same style once approved.
- **An item is briefly locked after a create/approve run.** `items/update` against a style whose
  approval has just completed returns `The record is currently locked by another user`. It is transient
  and not a payload problem, so do not treat it as one.
- **Barcodes are items at level 3, not a separate service.** There is no reference-item endpoint in the
  323-path spec. A UPC is `items/create` with `itemLevel: 3`, `itemParent` set to the SKU,
  `itemGrandparent` to the style, and `primaryReferenceItemInd`. Three things it costs a dozen attempts
  to learn: `itemNumberType` must be `EAN13` (`ITEM` and an absent type both demand a 9-character
  number, `UPC-A` demands 12); `costZoneGroupId` must be sent and must equal the parent's, or MFCS
  answers `Field cannot be modified. Field: COST_ZONE_GROUP_ID` - an error naming a field you did not
  send; and `status` and `itemSupplier` are inherited from the parent, so do not send them. A SKU
  carries several barcodes with exactly one `primaryInd: Y`. All verified live on STG 2026-09-01.
- **`itemNumberType: MANL` lets the caller choose the item number, and no reservation is needed.**
  Verified live on STG 2026-09-10. `MANL` ("Manual", one of the 16 codes in the tenant's `UPCT` code
  type) accepts any string up to 25 characters - letters, digits, hyphens, slashes - at level 1 and
  level 2, and `itemDetail` reads the record back intact. `ITEM` is the opposite and is effectively
  unusable for a chosen number: it demands exactly 9 characters *and* a valid Oracle check digit, so
  an invented 9-digit number fails with `Invalid Check Digit`, and a 9-character alphanumeric does not
  even fail cleanly - it returns `ORA-06502 ... buffer too small`. That check digit is why
  `itemNumbers/reserve` exists; it generates numbers that satisfy it.
  Reservation is a separate axis and does not help. `itemNumbers/manage` (note: *not* `/reserve` -
  it reserves a number you name, rather than generating one) accepted a chosen number, but a `MANL`
  create succeeded without any reservation and an `ITEM` create still failed the check digit *with*
  one. Oracle's own text says reserved numbers are honoured by the Item spreadsheet upload, not by
  `items/create`, which is exactly what the tenant does. `ENDPOINT.ITEM_NUMBERS_MANAGE` in `CONFIG`
  currently points at `/itemNumbers/reserve`, which was harmless while `manage` was unused.
  **A `MANL`-numbered item is a normal item in every way that was tested**, all live on STG
  2026-09-10 against style `TWA10134116` and SKU `TWL10134402`: sourcing and country of manufacture
  attach, both items **approve** (read back `status: A`), the SKU **ranges** to warehouse 19271, it
  **takes a level-3 EAN13 barcode**, and it **can be ordered** - purchase order `40003` was created
  against it and the procurement read shows the line carrying the alphanumeric item. A **duplicate
  number is refused loudly**: `Item already exists.Field: ITEM`, HTTP 400, which is what makes a
  derived numbering scheme safe to collide on. Nothing about alphanumerics was a special case.
- **The update services want the whole record, not a patch.** `items/update` refuses without
  `STORE_ORD_MULT` even for a description-only change; `suppliers/update` refuses without
  `DIRECT_SHIP_IND`, then `INNER_NAME`. All are now sent on both paths. Valid packaging names come
  from the tenant's own code types `INRN`, `CASN`, `PALN`, in master data.
- **Country of manufacture cannot be re-created.** `countriesOfManufacture/create` answers an existing
  row with "already exists"; use the `update` service on any style that already exists.
- **A transport error is not a failure, it is an unknown outcome.** `ORA-29273` was once classified
  FAILED while MFCS had in fact created the purchase order. `client_pkg` now classifies on SQLCODE,
  and recovery resolves by correlation ID.
- **The tenant refuses writes during its nightly batch**, as a plain HTTP 400 whose body says
  "Batch Running Indicator is ON". `client_pkg` raises `-20951` for it, so it does not read as a bad
  payload. If the coverage suite fails on that message, wait, do not debug.

## The inbound document

The contract is upper snake case throughout, and names nothing after the system that happens to send
it. `SIZE_CURVE_DETAIL` used to be `PLMSizeCurveDtl` - the one camelCase key, naming its source system
in a document that already carries `SOURCE_SYSTEM` as a field.

`request_pkg.normalise_payload` accepts either spelling and settles `DEPARTMENT`, `CLASS` and
`SUBCLASS` as numbers. **It runs at intake, before the payload is hashed, stored or validated, and that
ordering is the point.** Resume replays the *stored* payload, so a document normalised on the way in is
canonical for the rest of its life. Normalising on the way out would leave both shapes in the system
forever and every reader would have to know about both. Validation errors name the canonical field, so
a caller sending the legacy key sees `SIZE_CURVE_DETAIL.SKU_QTY` in the response.

Optional additions, absent from documents written earlier and behaving exactly as before when absent:

- `STYLE_SEASONS`, `STYLE_IMAGES` and `STYLE_HTS` at the root, all style-level for the same reason as
  UDAs. Seasons carry `SEASON_ID` / `PHASE_ID` / `SEQUENCE_NO`; images carry a file name, address,
  type and a primary flag; tariff codes carry the code with its import and origin countries and an
  effective range. **HTS assessments are not sent** - the tenant's own rows carry `componentId`
  `DTY7AGB` against `computationValueBase` `VFDGB` with duty and expense flags, and nobody here knows
  what those should be for a new style. The code itself is useful without them.
- `STYLE_UDAS` at the root. Style-level only - **SKUs inherit their style's UDAs**, so there is
  deliberately no SKU-level slot. The mapper writes the same set to the parent and to every child,
  because MFCS is not known to cascade and a real item carries copies at both levels. Office sends the
  tenant's own `UDA_ID` and value; `displayType` is not asked for, because `foundation/uda` already
  publishes it.
- `SKU_UPCS` inside each `SIZE_CURVE_DETAIL` row. Exactly one `PRIMARY_YN: "Y"` per SKU. `UPC_TYPE`
  defaults to `EAN13`; a real Office SKU carries one `EAN13` and one `MANL`.
- `BRAND`, sent as `brandName` - the tenant's brand *code*, which is what `master_pkg` stores.
- `ITEM_DESCRIPTION` at the root and in every `SIZE_CURVE_DETAIL` row, travelling for the same reason
  as `ITEM_NUMBER` and validated the same way: optional, 250 characters or fewer. A caller that
  composes "MODEL Colour Size" from its own data sends the result rather than having this layer guess
  at it. Absent, the style falls back to `SOURCE_STYLE_REF` and a SKU to the style description with
  its size differentiator appended, which is what every document written before this field relied on.
  `payload_pkg.style_description` and `sku_description` resolve it in one place, so the parent create,
  the child create, the barcode create and the approve step cannot disagree about what an item is
  called. **`APPROVE_ITEMS` used to send `SOURCE_STYLE_REF` for every item**, which silently
  overwrote every SKU description with the style's at the last step of a run - a size that had been
  captured, sent and stored was lost. Fixed 2026-09-10 and proven by read-back.
- `ITEM_NUMBER` at the root and in every `SIZE_CURVE_DETAIL` row, with `ITEM_NUMBER_TYPE` at the
  root, for a caller that numbers its own items. **This layer does not compose item numbers and
  should not start.** A caller that wants a number derived from its own data - a model plus a
  supplier colour, say - composes it there and sends the result, because a composition rule living
  here would have to know every caller's scheme, and that is the mistake `MAP.*` already was. What
  this layer owes is the shape, the validation and the writes.

  `ITEM_NUMBER` and `ITEM_NUMBER_TYPE` travel together or not at all: a type without a number means
  the caller believes it is choosing and something upstream dropped it, which is worth refusing
  loudly rather than quietly reserving a number nobody expects. `ITEM_NUMBER_TYPE` must be `MANL` -
  see the tenant-behaviour note above for why `ITEM` cannot work. Numbering is all-or-nothing per
  request, unique within the document, 25 characters or fewer, and accepted only on `CREATE_STYLE`
  and `CREATE_ALL`; on a modify the items already exist and are addressed by `STYLE` and `SKU_ID`.

  `ITEM_NUMBER` is not `SKU_ID`. `SKU_ID` names a SKU MFCS already holds and is a reference on a
  modify; `ITEM_NUMBER` is an assignment on a create. Validation already forces `SKU_ID` null on
  the create operations, so the two can never arrive together.

  When the document carries numbers, `RESERVE_ITEM_NUMBERS` makes no call: it records them against
  the request and the run continues identically. That is the *only* place the two numbering paths
  differ - the numbers land in `ENTITY_MAP` by the same call either way, so no mapper downstream
  knows or cares which way they were arrived at. Absent `ITEM_NUMBER` everything behaves exactly as
  it did, reserving `ITEM` numbers as before.

`SKU_WIDTH` is no longer required. It reached no MFCS field: it was validated against `MAP.WIDTH.*` and
then used only to build a description string. It is still accepted and still recorded in `ENTITY_MAP`
where a caller sends it, but nothing depends on it.

One colourway per style, by design. `COLOUR` is style-level and singular, and a style needing two
colourways is two requests.

## Conventions

- Keep business logic in PL/SQL. The console builds only the inbound document; everything downstream —
  validation, step graph, endpoint resolution, payload construction — comes from the database.
- `client_pkg` is the only package that resolves credentials or makes an outbound call. Do not add a
  second HTTP path; a duplicate is what previously let a stale token survive in one code path and not
  another.
- Never cache a credential in a package global. ORDS pools sessions and the cache outlives the request.
- Emit ORDS responses through `ords_util_pkg.emit_json`. `htp.prn` takes a VARCHAR2, and the item feed
  crosses 32KB after about seven rows.
- Do not pass an upstream failure through as HTTP 200. An expired token served as a 200 with an HTML
  body reads as "endpoint fine, no data", which is the wrong diagnosis.
- Three things are deliberately defined once - do not add a second copy: the size-curve projection
  (`payload_pkg.c_size_curve`), step-to-endpoint/method/mapper resolution
  (`orchestrator_pkg.resolve_step`), and the generated-children plan (`payload_pkg.t_child_plan`).
- The step graph is code, not data, on purpose. Hardcode structure (which steps, their order, which
  endpoint key); configure values (paths, defaults, tenant constants). Do not build a table-driven
  step engine.
- Comments should explain why, especially where the code looks odd because MFCS is odd.

## Not our bugs

`ENDPOINT.INITIAL_RETAIL` is a placeholder because no matching write service exists.

## Known defects in what we create

**Items we create have no retail price.** A style created by this layer reads back `unitRetail: 0`
against a real UAT item's `85`, even though we send `originalRetail`. `unitRetail` is where the tenant
keeps the effective price, and nothing we send reaches it. Consistent with `ENDPOINT.INITIAL_RETAIL`
being a placeholder, but worth confirming against what Office expects rather than assuming it is
cosmetic.

**Brand does not stick.** `items/create` accepts `brandName` with the tenant's own brand code, answers
SUCCESS, and the item reads back with `brandName` empty. Verified end to end on 2026-09-01: the stored
request payload shows `"brandName":"02"` was sent, and `foundation/item` returned the style with no
brand once its cache had refreshed and the UDAs written in the same run *were* visible. Trying
`items/update` instead hit the post-approval record lock and settled nothing. The mapper still sends it
and validation still checks it against master data, because both are correct as far as we know - but
nothing reaches the tenant, so do not report brand as working.

**We create nothing Office would call complete.** Seasons, HTS codes and images are still absent -
see `docs/status-and-next-steps.md`. UDAs and barcodes are done and proven live.

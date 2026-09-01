# Status and next steps

Written so work can stop and resume without losing the thread. Current as of **2026-09-01**.

## Where things stand

The integration runs against the **real MFCS dev tenant** and nothing else. Simulators, mock modes and
the `MFCS_CLIENT_MODE` switch were removed — if you find a reference to them, it is stale.

| Area | State |
| --- | --- |
| `CREATE_STYLE`, `CREATE_ALL` | Proven end to end against the tenant |
| `MODIFY_STYLE` | **Completed live 2026-08-22**, all seven steps |
| `CREATE_ORDER` | **Completed live 2026-08-22**, all eleven steps, order 25012 created and verified |
| `MODIFY_ORDER` | **Proven live 2026-08-22 both directions**: quantities, colour switch with line creation + cancellation, and switch-back, all verified by read-back |
| Missing-SKU generation | **Proven live 2026-08-22**: created two children under an existing style, verified by read-back |
| Failure / resume paths | 20 of 20 passing, fault-injected against the real tenant (re-verified 2026-08-22 after the batch window closed) |
| Console (`ui/`) | Build, Activity, Styles & orders, Master data, MFCS spec, **How it works** (clickable end-to-end flows) |
| APEX console | App 102 `MFCS Controller` installed in workspace `TW_TEST`, parsing schema `MFCS_INTEGRATION` |
| Item ranging | On, using virtual warehouse 19271 |
| Non-merchandise costs | `NON_MERCH_COSTS` → order `expenses`, validated and previewing; not yet sent live |

| UDAs | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| Barcodes (level-3 UPCs) | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| `BRAND` | Sent and silently dropped by the tenant. **Does not work** |
| Seasons, images, tariff codes | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| Console end to end | **Proven live 2026-09-01.** APEX draft through to MFCS, style 100150356 |
| `MAP.*` config | **Retired 2026-09-01.** Lists and validation read `MASTER_DATA` |
| APEX pages | 1 Home, 3 Create/Edit, 4 Activity, 5 Browse, **10 Style Capture**, **20 Style Explorer** |

Environment: MFCS STG `https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs`
and UAT `.../rgbu-rex-truw-uat3-mfcs`; the IDCS token host is different again. The database is
**mdutilstst01**, Oracle 23.26.2.0.0, PDB `FREEPDB1`, schema `MFCS_INTEGRATION` — *not* the `adb-free`
container older notes describe. Connect with `deploy/mdutils/sql.sh`.

**If the coverage suite is failing, check the token before suspecting the code.** A stale token makes
every MFCS step fail with `-20950` and the suite reports roughly half its assertions failed. That is
not a regression. `GET /token-status` says so in one line.

**Bearer tokens last one hour.** Most "nothing is working" moments are an expired token — the console
header shows remaining validity, and `GET /token-status` decodes it.

## Session of 2026-09-01 — what changed

Fifteen commits, all pushed. Ordered by how much each alters the picture.

**The inbound contract settled.** `PLMSizeCurveDtl` became `SIZE_CURVE_DETAIL`, and
`request_pkg.normalise_payload` accepts either spelling at intake — before the payload is
hashed, stored or validated, so resume replays a canonical document. `DEPARTMENT`, `CLASS` and
`SUBCLASS` are numbers. New optional keys: `STYLE_UDAS`, `SKU_UPCS` (inside each size-curve
row), `STYLE_SEASONS`, `STYLE_IMAGES`, `STYLE_HTS`, `BRAND`. `SKU_WIDTH` is no longer required.

**`MAP.*` is retired.** It was two things wearing one name: a translation table and a whitelist
maintained alongside master data and free to disagree with it — which is how `MAP.COLOUR.BLACK`
came to offer a colour the tenant rejects, after an item number had been burned. Every front end
now sends the tenant's own identifiers, so the translations had nothing left to do, and the
whitelists moved to `MASTER_DATA`. 340 config rows deleted. One translation survives because it
is not a naming difference: `payload_pkg.virtual_location` maps a physical warehouse to its
virtual one, derived from the warehouse feed rather than a hand-maintained row.

**Five attribute types now reach MFCS, all proven live**: UDAs, barcodes (level-3 reference
items), seasons, images and tariff codes. Style `100150305` carries all five, verified by
read-back.

**The console path is proven end to end.** Request `APEX-20260901212130632` completed from an
APEX draft through to MFCS — style `100150356`, 17 steps, 20 calls.

**Master data is populated and is now the single source.** 23 UDA definitions with 750 values,
244 brands, 60 suppliers, 250 countries, 12 warehouses, 215 colours and 29 sizes with
descriptions from the front-end exports. `master_pkg.load_udas` and the fixed warehouse loader
were both storing nothing before today.

**Two new APEX pages**, leaving 3, 4 and 5 untouched: **10 Style Capture** and **20 Style
Explorer**.

## Outstanding, in the order I would take it

### A. Items are created with no price
Everything we create reads back `unitRetail: 0`; a real UAT item reads `85`. We send
`originalRetail` and it does not reach the field the tenant treats as the price. Consistent with
`ENDPOINT.INITIAL_RETAIL` being a placeholder with no matching write service. **This is the
largest functional gap** — a style in MFCS priced at zero is not a usable style. Needs a decision
on what Office expects before it can be built.

### B. The differentiator group is not selectable
The parent's `diff1`/`diff2` groups come from `MFCS_PARENT_DIFF1_GROUP` and
`MFCS_PARENT_DIFF2_GROUP` config, hardcoded to `RMS_ALL_C` and `ALL`. Nobody chooses them per
style. The group is what says which children are legal — CLAUDE.md already records that a colour
outside the parent's group is rejected loudly at `items/create`, and sizes are no different. So
today a style can be given sizes from two different curves and nothing stops it.

Blocked on data: `foundation/diffgroup` returns 13 groups with a `details` array naming each
group's member diffs, **but only on UAT**. STG's is empty. One front-end export of Differentiator
Groups, or one read against UAT, closes it. Then: `SIZE_GROUP` and `COLOUR_GROUP` on the document
defaulting to the config values, a picker on the header, and validation that every SKU's diff
belongs to the chosen group.

### C. Non-merchandise costs have no capture
`NON_MERCH_COSTS` is validated and previewed by the backend and maps to the order's `expenses`,
but neither console has a field for it, and it has never been sent live.

### D. `BRAND` is accepted and silently dropped
`items/create` takes `brandName`, answers SUCCESS, and the item reads back with no brand while
UDAs written in the same call are present. The brand code was checked against the tenant's own
246, so it is not a bad value. `items/update` as a second attempt hit post-approval record
locking and settled nothing. Parked by agreement; not exposed in either console, because offering
a field that does nothing is worse than not having it.

### E. Only `CREATE_ALL` has run from the console
The console offers all five operations. `CREATE_STYLE`, `CREATE_ORDER`, `MODIFY_STYLE` and
`MODIFY_ORDER` have never been driven from it. Related and unproven: on the modify paths
`CREATE_REFERENCE_ITEMS` resolves to `items/update`, and whether that service accepts a level-3
item has never been tested.

### F. HTS assessments are not sent
The tenant's own rows carry `componentId DTY7AGB` against `computationValueBase VFDGB` with duty,
expense and ALC flags. The tariff code is useful without them; the assessments need someone who
knows the customs side.

### G. The capture page is reorganised, not redesigned
Page 10 groups 27 header fields into four titled sections and is derived from page 3. Real polish
— a summary card, a wizard flow, a popup colour picker over the 48,624 differentiators rather
than a select list — is a deliberate piece of design work still to do. The `popupLov` donor and
the syntax are recorded in the APEXlang skill.

### H. Two directories are untracked pending a decision
`docs/dataSamples/` (includes 60 real suppliers with addresses) and `docs/foundationExports/`
(2.3 MB, with exact duplicates: `Differentiators` twice, `HTS Definition` twice, `Phases` three
times). Neither is in git.

## Older outstanding work

### 1. Exercise the remaining edges of order-line sync

The line services are wired and proven. `SYNC_ORDER_LINES` (MODIFY_ORDER, seq 105) reads the
order, updates/creates/cancels this style's lines, and verifies by read-back — quantities,
a full colour switch with cancellation (`S`), a reduction (`B`), and resurrection of a cancelled
line have all run live on order 25012. Semantics worth re-reading before touching it:
`quantityCancelled` is cumulative-absolute and is deliberately never sent; `quantityOrdered` is
authoritative and `quantityOrdered:0` + `cancelInd` + `cancelCode` is a cancellation.

What has not been exercised: an order carrying lines from more than one style (the scoping is
coded — only the document's style's lines are candidates for cancellation — but never run),
`MFCS_ORDER_LINE_ABSENT_ACTION='LEAVE'`, and a colour switch where the new colour is not in the
parent's diff group (rejected loudly by MFCS: the diff must be a member of the parent's group —
`BLACK` failed, `08621` worked; adding members to a diff group is untested territory).

### 1a. Every operation now sends its whole write set

Worth stating because it is a design rule, not an implementation detail. `MODIFY_STYLE`,
`CREATE_ORDER` and `MODIFY_ORDER` share one seven-step style sequence — SKU check, hierarchy,
sourcing, country of manufacture, UDAs, ranging, approval — and the order operations place the order
on top of it. Nothing is skipped for looking unchanged: the inbound document states what the style
should be, not what changed, and MFCS answers a no-op write with SUCCESS, so an omission would be
silent. Do not reintroduce conditional sending.

Getting there fixed four things, each found by running it:

- `items/update` refuses without `STORE_ORD_MULT`, even for a description-only change.
- `suppliers/update` refuses without `DIRECT_SHIP_IND`, then `INNER_NAME`. All three packaging names
  are now sent; the valid values are the tenant's own code types `INRN`, `CASN`, `PALN`.
- `countriesOfManufacture/create` cannot be replayed — it answers an existing row with "already
  exists". Existing styles use the `update` service.
- `ORA-29273` was classified as a failure while MFCS had actually created the purchase order. A
  transport error is an *unknown* outcome; `client_pkg` now classifies on SQLCODE and lets
  `recovery_pkg` resolve it by correlation ID.

### 2. Point the console's dropdowns at the code details (loading done)

`master_pkg.refresh_all` now loads `administration/operations/codes` — **797 code types, 7,049 rows** —
plus banners and channels. Each value is stored as `CODE_<codeType>` with the code type as
`parent_code`, and `CODE_TYPE` lists the types themselves.

What remains is using them: the console's fixed-value fields (order type, status, freight terms, cost
basis, expense components) still read from `CONFIG` or free text. Point them at `CODE_*` instead.

### 3. Exercise the remaining untested operations

`MODIFY_ORDER` and `CREATE_ORDER` have never run live. The console's browse tab loads a real record
straight into the modify form, which is the intended way to try them. Both now carry
`ENSURE_STYLE_SKUS` at sequence 85, so a colour the style does not have will be created before the
order is built rather than producing an order against nothing.

Still untested, and the question the user raised: when a colour changes on an existing order, does
the old colour's line need explicit cancellation, or is replacing the detail lines enough?

### 4. Non-merchandise costs, end to end

The mapping is in and previews correctly. It has not been sent to MFCS, so the component codes
(`FREIGHT`, `DUTY`, …) have not been validated against what the tenant actually accepts. Expect the
first live attempt to reveal the valid component list.

## What Office items actually look like, and what we do not build — 2026-09-01

Three real item documents (a style, a SKU and its barcodes) were compared against a style this layer
created. Samples are cached in `docs/dataSamples/`.

**The shapes match.** `foundation/item` returns 118 keys on UAT and 125 on STG, and every UAT key exists
on STG — STG is a superset, adding the company/division/group hierarchy. `itemDetail` rows are byte-for-
byte the same shape at all three levels, 25 keys each. Nothing about what we create is structurally
wrong.

**What a real item carries that ours does not:**

| | ours | theirs |
| --- | --- | --- |
| `itemUda` | 3 (written by hand in a probe) | 13 |
| `referenceItem` | 1 (written by hand in a probe) | 2, one primary |
| `itemSeason` | null | `seasonId 1, phaseId 1, sequenceNo 1` |
| `itemImage` / `primaryImageUrl` | null | Amplience CDN, `imageType T` |
| `hts` | null | `6402993900` GB←DE, with `assessments` |
| `brandName` / `brandDescription` | null | `18` / `Birkenstock` |

Both mechanisms behind the first two rows are now proven live — see
`docs/mfcs-actual-call-flow.md`. Neither has a step in the graph yet.

**One defect, not a gap.** Our SKU reads back `unitRetail: 0` where the real one reads `85`. We send
`originalRetail` and it does not reach `unitRetail`, which is where the tenant keeps the effective
price. Everything this layer has created is priced at zero. Confirm what Office expects before deciding
whether that matters.

**Foundation data is no longer the blocker it was.** STG now publishes `uda` (23 definitions with their
values), `supplier`, `store` and `warehouse`. UAT publishes all of those plus `diffid` (380),
`diffgroup` (13, each naming its member diffs), `difftype` and all three `merchhier` levels. The
`MAP.*`-and-derive-from-item-feed approach was a workaround for empty feeds; on UAT it is no longer
needed.

**The bottleneck is now inbound.** We cannot send UDA values, barcodes, seasons or HTS codes that the
Office document has no room for. The MFCS-side work is mapper work in shapes we already run; agreeing
the inbound contract is the critical path.

## Known gaps that are not our bugs

**UDAs do not work because the tenant has none.** `foundation/uda` returns zero rows and `itemUda` is
null on every item. The integration sends an empty array, which succeeds trivially. Wiring capture →
master data → integration would build a pipe with nothing at either end. Resolve tenant-side first.

**Most foundation services are empty publish queues.** `merchhier/*`, `diffid`, `difftype`,
`diffgroup`, `supplier`, `store`, `warehouse`, `uda` all return HTTP 200 with zero rows, and
`since`/`before` does not change it. Only `item/brands`, `item/foundation/seasons`, `orghier`,
`banners`, `channels`, `codes` and `item/location` return foundation rows directly. This is why the
master-data cache derives hierarchy, differentiator and supplier values from the item and order feeds.

**`ENDPOINT.INITIAL_RETAIL` is a placeholder.** No matching write service exists in the tenant spec, so
`FEATURE_INITIAL_RETAIL_YN` stays `N`.

**No offline test coverage.** The suites that ran without a tenant were removed with the simulators.
Everything now requires a live token, and the coverage suite creates real records by design. Rebuilding
offline coverage against recorded fixtures is unstarted.

## Things that will mislead you if you forget them

- **The tenant serves more than its OpenAPI document lists.** `RmsReSTServices/services/private/Item/itemDetail`
  is not in the spec but is the only way to get a style's children in one call. "Not in the spec" is not
  the same as "not available".
- **Unknown query parameters are silently ignored**, returning an unfiltered feed that looks like a
  working filter. It is `deptId`, not `dept`. There is no `itemParent` filter.
- **MFCS can return `SUCCESS` and do nothing** — proven with the diff change. Verify writes by reading
  back, not by trusting the response.
- **List endpoints are publish/delta feeds**, not queries. They show approved and published records
  only, and lag by a few seconds.
- **Resume replays the *stored* payload.** A request that failed because of a bad value in that payload
  cannot be rescued by resuming; it needs a fresh request.
- **`ENSURE_STYLE_SKUS` is the exception to that**, deliberately. It stores no payload: it re-reads the
  style on every entry and acts on what it finds, so a resume creates only what is still missing.
- **`foundation/item/{item}` is a feed read.** It answered 404 for a style created and approved minutes
  earlier, while `itemDetail` returned it in full. Anything that has to work on a freshly created
  record must not be built on the feed.
- **`itemDetail` is a third vocabulary.** Not the item feed's names and not the write services': it says
  `classAttribute`, `itemDesc`/`shortDesc`, `primarySuppInd`, `originCountryId`, `suppPackSize`.
  `sku_pkg.style_attributes` translates so callers see one set of names.
- **The update services want the whole record.** `items/update` demands `STORE_ORD_MULT` even when only
  a description changed; `suppliers/update` demands `DIRECT_SHIP_IND`, then `INNER_NAME`. The create
  services default all three.

## Running things

```bash
# Install from zero (schema owner)
@deploy/adb-free/install.sql

# Fault-injected failure and resume coverage - creates real tenant records
@tests/resume_coverage_tests.sql

# Console
cd ui && npm install && npm run dev      # http://localhost:5173
```

`deploy/adb-free/` also holds the schema/ACL setup, a connectivity probe, endpoint sweeps and
`set_token.sql` for loading a Postman-issued bearer token.

```bash
# Seed APEX LOV foundation data after setting/updating the token
@deploy/adb-free/09_refresh_master_data.sql
```

APEX source lives in `apexlang/mfcs-controller`. `apex validate` and `apex import` work with the
installed SQLcl, but `apex export` / `apex generate` currently throw a SQLcl Java
`Path.of(null)` error in this Windows shell. Upgrading SQLcl is convenience work, not a blocker for
deploying the checked-in APEXlang source.

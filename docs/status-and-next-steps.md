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

Seven commits, all pushed. Ordered by how much they alter the picture.

**The inbound contract changed shape.** `PLMSizeCurveDtl` is now `SIZE_CURVE_DETAIL`, and
`request_pkg.normalise_payload` accepts either spelling at intake — before the payload is hashed,
stored or validated, so resume replays a canonical document. `DEPARTMENT`, `CLASS` and `SUBCLASS` are
settled as numbers. Two optional additions: `STYLE_UDAS` at the root and `SKU_UPCS` inside each
size-curve row. `SKU_WIDTH` is no longer required — it reached no MFCS field. `BRAND` is accepted but
does not work (below).

**UDAs and barcodes are built, proven live, and capturable.** Request `LIVE-UPC-184508` created style
`100150161` with two SKUs and three barcodes, all eleven steps, read back through `itemDetail`. The
APEX console gained two grids for them.

**Two claims in CLAUDE.md were wrong and both discouraged looking further.** UDAs do work — the empty
`foundation/uda` was a publish queue, not an empty definition set. And parents do not have to carry
diff *groups*; `diff1Level` / `diff2Level` says which you have.

**Foundation feeds now publish, per tenant.** STG serves `uda`, `supplier`, `store`, `warehouse`;
`diffid`, `diffgroup`, `difftype` and `merchhier/*` are still empty there. UAT serves everything.

**Master data and the console's lists are populated.** `master_pkg.load_udas` loaded 23 definitions and
750 values; `seed_map_config` derived 316 `MAP.*` rows (5 departments, 10 classes, 10 subclasses, 61
suppliers, 217 colours, 29 sizes). Diff descriptions came from the front-end exports, so lists read
"BLACK LEATHER" rather than "00078".

## Outstanding, in the order I would take it

### A. Drive a draft through the console end to end
Everything below the console is proven, and the console can now capture UDAs and barcodes, but
**nothing has gone from an APEX draft through to MFCS with them**. Capture a style with both, submit,
confirm the read-back. This is the shortest path to knowing the whole chain holds.

### B. `BRAND` silently fails
`items/create` takes `brandName`, answers SUCCESS, and the item reads back with no brand — while UDAs
written in the same call are present. The stored attempt payload proves it was sent, and the brand code
was checked against the tenant's own 246 brands, so it is not a bad value. `items/update` as a second
attempt hit post-approval record locking and settled nothing. Not exposed in the console on purpose:
offering a field that does nothing is worse than not having it.

### C. `unitRetail` is 0 on everything we create
A real UAT item reads `unitRetail: 85`; ours read `0`. We send `originalRetail` and it does not reach
the field the tenant treats as the price. Consistent with `ENDPOINT.INITIAL_RETAIL` being a
placeholder. Confirm what Office expects before deciding whether it matters.

### D. The APEX value list does not cascade
The UDA value list labels every entry with its attribute ("Gender: Boy") rather than filtering on the
chosen attribute, because a grid-column cascade has no syntax donor in this export. Wrong combinations
are rejected by `validation_pkg` before any MFCS call, so it is safe — just more scrolling.

### E. Seasons, HTS and images
Still absent from what we create. Services exist for all three (`item/seasons/create`,
`item/hts/create` plus assessments, `item/images/create`), and the front-end exports carry the
reference data. HTS needs domain input on assessment components; the other two do not.

### F. The `CREATE_REFERENCE_ITEMS` update path is unproven
On `MODIFY_STYLE` and the order operations the step resolves to `items/update`. Whether that service
accepts a level-3 item has never been tested.

### G. Two directories are untracked pending a decision
`docs/dataSamples/` (includes 60 real suppliers with addresses) and `docs/foundationExports/` (2.3MB,
with exact duplicates: `Differentiators` twice, `HTS Definition` twice, `Phases` three times). Neither
is in git.

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

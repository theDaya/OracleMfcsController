# Status and next steps

Written so work can stop and resume without losing the thread. Current as of 2026-08-22.

## Where things stand

The integration runs against the **real MFCS dev tenant** and nothing else. Simulators, mock modes and
the `MFCS_CLIENT_MODE` switch were removed — if you find a reference to them, it is stale.

| Area | State |
| --- | --- |
| `CREATE_STYLE`, `CREATE_ALL` | Proven end to end against the tenant |
| `MODIFY_STYLE` | **Completed live 2026-08-22**, all seven steps |
| `CREATE_ORDER` | **Completed live 2026-08-22**, all eleven steps, order 25012 created and verified |
| `MODIFY_ORDER` | Same graph as `CREATE_ORDER` minus the number reservation; not yet completed live |
| Missing-SKU generation | **Proven live 2026-08-22**: created two children under an existing style, verified by read-back |
| Failure / resume paths | 20 of 20 passing, fault-injected against the real tenant (re-verified 2026-08-22 after the batch window closed) |
| Console (`ui/`) | Build, Activity, Styles & orders, Master data, MFCS spec |
| Item ranging | On, using virtual warehouse 19271 |
| Non-merchandise costs | `NON_MERCH_COSTS` → order `expenses`, validated and previewing; not yet sent live |

Environment: MFCS `https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs`,
IDCS token host is different. Local install in `MFCS_INTEGRATION` on the `adb-free` container.

**If the coverage suite is failing, check the token before suspecting the code.** A stale token makes
every MFCS step fail with `-20950` and the suite reports roughly half its assertions failed. That is
not a regression. `GET /token-status` says so in one line.

**Bearer tokens last one hour.** Most "nothing is working" moments are an expired token — the console
header shows remaining validity, and `GET /token-status` decodes it.

## Outstanding work, in the order I would take it

### 1. Complete `MODIFY_ORDER` live

`MODIFY_STYLE` and `CREATE_ORDER` both complete end to end. `MODIFY_ORDER` runs the same graph as
`CREATE_ORDER` without the number reservation, and its one live attempt stopped on the tenant's
nightly batch window rather than on anything in the payload — so it is untested, not known-broken.

The batch window has since closed and the coverage suite runs 20/20 again, so this is ready to run. The open question is still the one you raised: when a colour
changes on an existing order, does the old colour's line need explicit cancellation, or is replacing
the detail lines enough?

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

# Working on this repository

A PL/SQL + ORDS integration layer that turns a legacy PLM/Office document into the sequence of Oracle
MFCS REST calls needed to create and modify styles and purchase orders, plus a React console for
driving and inspecting it.

## Read these first

- `docs/status-and-next-steps.md` — what is proven, what has never run live, what is outstanding
- `docs/database-objects.md` — what every table and package does, and why the non-obvious ones exist
- `docs/mfcs-actual-call-flow.md` — real payloads from runs that actually succeeded

Keep those three current. If you change behaviour they describe, update them in the same commit.

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
@deploy/adb-free/install.sql
@deploy/adb-free/99_verify.sql        # expect zero invalid objects

# Fault-injected failure and resume coverage - CREATES REAL TENANT RECORDS
@tests/resume_coverage_tests.sql      # expect 20 passed, 0 failed

cd ui && npm install && npm run dev   # http://localhost:5173
```

Local database is the `adb-free` container. It is Autonomous, so connections are TCPS with service
names, not a SID. The reliable route is sqlplus inside the container:

```bash
docker exec adb-free bash -lc 'export TNS_ADMIN=/u01/app/oracle/wallets/tls_wallet && \
  sqlplus -s -L mfcs_integration/CsidbaLocal2026@myatp_low'
```

Copy scripts in with `docker cp` to a **fresh** directory (`docker cp` nests into an existing one), then
`cd` inside `bash -lc`. Do not use `docker exec -w` — Git Bash rewrites the path and it fails.

## Tenant behaviour that will cost you a day

All verified live. Most are silent failures, which is why they are worth memorising.

- **A colour change cannot be applied to an existing SKU.** A diff combination *defines* the item, so a
  new colour means new children. `items/update` accepts the change and ignores it.
- **Unknown query parameters are silently ignored**, returning an unfiltered feed that looks like a
  working filter. It is `deptId`, not `dept`. There is no `itemParent` filter.
- **List endpoints are publish/delta feeds**, not queries — approved and published records only, with a
  few seconds of lag. Empty does not mean absent.
- **Most foundation services are empty publish queues** on this tenant (`merchhier/*`, `diffid`,
  `supplier`, `store`, `warehouse`, `uda`). That is why master data derives hierarchy, differentiator
  and supplier values from the item and order feeds, and records `SOURCE` on every row.
- **`OTB_EOW_DATE` must fall on a Sunday** (the retail week end). MFCS only enforces it at order create,
  by which point a style exists and an order number is burned, so validation checks it up front.
- **Item ranging needs the virtual warehouse** (19271), not the physical location (1927). Both mappers
  translate through `MAP.ORDER_LOCATION.*` so they cannot disagree.
- **A purchase order ranges its own items**, so `CREATE_ITEM_LOCATIONS` only matters for style-only creates.
- **Approval requires sourcing and country of manufacture first.**
- **Parent styles carry differentiator *groups*** (`RMS_ALL_C`/`ALL`); children carry *concrete* diff IDs.
- **Order read and write disagree on names**: read gives `physicalQuantityOrdered` / `originCountryId`,
  write wants `quantityOrdered` / `originCountry`.
- **Resume replays the *stored* payload.** A request that failed on a bad value in that payload cannot be
  rescued by resuming; it needs a fresh request.
- **`foundation/item/{item}` is a feed read** and 404s on a style created minutes ago. `itemDetail`
  returns it in full. Never build on the feed anything that must see a fresh record.
- **`itemDetail` uses a third set of field names**, neither the feed's nor the write services':
  `classAttribute`, `itemDesc`/`shortDesc`, `primarySuppInd`, `originCountryId`, `suppPackSize`.
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

UDAs do not work because the tenant has no UDA definitions — `foundation/uda` is empty and `itemUda` is
null on every item. `ENDPOINT.INITIAL_RETAIL` is a placeholder because no matching write service exists.
Neither is worth "fixing" in code.

# Database objects

Everything lives in one schema, `MFCS_INTEGRATION`. Objects inside it carry no prefix — the schema
name already says what they are.

Source layout mirrors this: `database/10_tables/`, `database/20_packages/` (one file per package,
numbered in dependency order), `database/30_ords/`.

---

## Tables

### Request journal

The integration commits as it goes — there is no distributed transaction across MFCS calls — so these
four tables *are* the recovery mechanism, not just an audit trail.

| Table | Grain | What it is for |
| --- | --- | --- |
| `REQUEST` | one row per `ACTION_REQUEST_ID` | The inbound document, its canonical hash, current status and the response returned to the caller |
| `STEP` | one row per step of a request | The step graph: which steps this operation needs, and where each one got to |
| `ATTEMPT` | one row per HTTP call | Endpoint, method, correlation ID, HTTP status, and the full request and response bodies |
| `EVENT_LOG` | one row per logged event | Written in an autonomous transaction, so progress survives a rollback of the work it describes |

`REQUEST.PAYLOAD_HASH` is what makes retries safe. Resending the same `ACTION_REQUEST_ID` with the
same business payload replays the stored response; resending it with a *different* payload is a
conflict, not an update. Volatile fields are excluded from the hash so a timestamp does not look like
a changed order.

`STEP.STEP_STATUS` drives resume. A step that already succeeded is skipped, which is why a resume
cannot double-create an item. `ATTEMPT` keeps every try rather than overwriting, so an ambiguous
timeout leaves evidence of what was sent.

`EVENT_LOG` is autonomous on purpose. When a step fails and its work rolls back, the log of what
happened must not roll back with it.

### Identity and configuration

| Table | What it is for |
| --- | --- |
| `ENTITY_MAP` | Office source references to MFCS identifiers — style, SKU, order. Keyed by source reference, **not** by request, so identifiers outlive the request that created them and a later resume or replay reuses them |
| `CONFIG` | Non-secret configuration: endpoints, feature flags, foundation mappings. Environment-scoped |
| `SECRET` | Credential values, looked up by reference. In `STATIC_BEARER` mode this holds only the short-lived bearer token — never the client secret |

### Master-data cache

| Table | What it is for |
| --- | --- |
| `MASTER_DATA` | Foundation values for the console's dropdowns, with a `SOURCE` column recording where each row came from |
| `MASTER_REFRESH` | Per-source outcome of the last refresh: HTTP status, row count, message |

`SOURCE` matters. `ENDPOINT:` means the value was read from a foundation service. `DERIVED:` means it
was harvested out of the item or order feed, because the matching foundation service returns HTTP 200
with zero rows on this tenant. Derived values are real but only as complete as the items that exist,
and the console says so rather than presenting them as authoritative.

---

## Packages

Numbered by dependency order. A package's body may only call packages above it.

| # | Package | Responsibility |
| --- | --- | --- |
| 01 | `config_pkg` | Configuration lookup with defaults |
| 02 | `event_pkg` | Autonomous event logging |
| 03 | `request_pkg` | Request registration, idempotency hashing, status, generated identifiers |
| 04 | `step_pkg` | Step graph state and attempt journalling |
| 05 | `validation_pkg` | Field-level validation of the inbound document |
| 06 | `payload_pkg` | Reads the Office document; builds every MFCS request body |
| 07 | `client_pkg` | **Sole owner of credentials and outbound HTTP** |
| 08 | `recovery_pkg` | Resolves ambiguous outcomes by correlation ID |
| 09 | `orchestrator_pkg` | Step graph, endpoint resolution, execution |
| 10 | `preview_pkg` | Builds the call plan without sending anything |
| 11 | `master_pkg` | Foundation-data cache and refresh |
| 12 | `browse_pkg` | Live style and order reads; order enrichment |
| 14 | `sku_pkg` | Reconciles required SKUs against a style's actual children; reads the parent's attributes |
| 15 | `api_pkg` | Public entry points behind the ORDS handlers |
| 16 | `ords_util_pkg` | Chunked ORDS response output |

### The ones with non-obvious jobs

**`client_pkg`** is deliberately the only place that resolves a token or makes an outbound call.
`master_pkg` and `browse_pkg` call `client_pkg.get_json` rather than keeping their own copies. An
earlier duplicate is exactly what let a stale cached token survive in one code path and not another.
It also does *not* cache the token in a package global: ORDS pools sessions, so a cached credential
outlives the request that read it.

**`payload_pkg`** is the whole MFCS contract in one place. `orchestrator_pkg.payload_for_step` maps a
step code to a mapper name and calls `payload_pkg.build_request` — statically, so a missing mapper is
a compile error rather than a runtime surprise.

**`preview_pkg`** reuses the orchestrator's own step graph and endpoint resolution instead of
reimplementing them, so a preview cannot drift from what execution would really do. It registers a
throwaway `PREVIEW-` request so the real mappers can run, then deletes it.

**`sku_pkg`** exists because PLM does not know about SKUs, and because a colour change cannot be
applied to an existing SKU — see *Behaviour worth knowing* below. It stays read-only: it reports
what a style has and what a request needs, and `orchestrator_pkg` decides what to do about it.
`style_attributes` reads through `itemDetail` rather than `foundation/item`, because the latter is
fed by the publish queue and answers 404 for a style created minutes ago.

**`ENSURE_STYLE_SKUS` is one step that makes up to *n*+4 MFCS calls**, which is unlike every other
step in the graph. Two reasons. Which children are missing is only known after reading the tenant,
so a graph fixed at request registration cannot express it; and doing the work inline makes the step
re-entrant for nothing, because a resume re-derives the gap and creates only what is still absent.
Steps that replay a stored payload could not — they would re-send item numbers already used.
`FEATURE_GENERATE_MISSING_SKUS_YN=N` restores the earlier behaviour, where the step stops the
request and names what is missing.

The step also records the SKU behind every requested combination in `ENTITY_MAP`, whether it created
it or merely found it. `entity_map` is this database's memory, not the tenant's, so a style created
by an earlier install had no rows and could not be ordered against. That is also why
`validation_pkg` no longer rejects an unresolvable `SKU_ID` while generation is on: the check could
only ever consult local memory, and the step consults the tenant.

**`ords_util_pkg`** looks trivial and is not. `htp.prn` takes a `VARCHAR2`, so emitting a CLOB over
32,767 bytes raises ORA-06502 which ORDS reports as an opaque HTTP 555. The item feed returns roughly
4.6KB per item, so any listing beyond about seven rows crosses that line. Every handler streams
through this package.

---

## ORDS endpoints

Module `mfcs-v1`, base path `/mfcs/v1/`.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/transactions` | Submit |
| `POST` | `/transactions/validate` | Validate without executing |
| `POST` | `/transactions/preview` | Full call plan, nothing sent |
| `GET` | `/transactions/{id}` | Status |
| `POST` | `/transactions/{id}/resume` | Resume a partial request |
| `GET` | `/requests` | Recent requests with step progress |
| `GET` | `/requests/{id}` | Steps, attempts with payloads, event log |
| `GET` | `/styles`, `/styles/{item}` | Live style reads (`?withSkus=Y` attaches children) |
| `GET` | `/orders`, `/orders/{orderNo}` | Live order reads (enriched by default) |
| `GET` `POST` | `/master-data` | Read / refresh the cache |
| `GET` | `/reference-data` | Config-driven values for the console |
| `GET` | `/token-status` | Decoded JWT claims; never returns the token |

---

## Behaviour worth knowing

These were established against the live tenant and are easy to get wrong.

**A colour change cannot be applied to an existing SKU.** `PUT items/update` with a changed `diff1`
returns HTTP 200 `SUCCESS` and leaves the item untouched — verified through both API families. MFCS
does not reject it, it ignores it. A diff combination *defines* the item, so a new colour means new
children. An integration that simply forwards a colour change reports success while nothing happens.

**A purchase order ranges its own items.** Item-location rows exist only for items whose order
succeeded. `CREATE_ITEM_LOCATIONS` therefore matters for style-only creates, not for `CREATE_ALL`.

**Item ranging needs the virtual warehouse.** `DELIVERY_LOC` is an Office *physical* location (1927);
at `hierarchyLevel: W` MFCS wants the *virtual* warehouse (19271) and rejects the physical one. Both
the order mapper and the item-location mapper translate through `MAP.ORDER_LOCATION.*` so they cannot
disagree about where the same item goes.

**`OTB_EOW_DATE` must be a retail week-ending date.** The tenant calendar starts every retail month on
a Monday, so weeks end Sunday. MFCS enforces this only at order create — step 100 — by which point a
style exists and an order number is burned, so `validation_pkg` checks it up front.
Configurable via `MFCS_OTB_EOW_DAY`.

**Approval needs sourcing and country of manufacture first.** Items cannot be approved without both.

**Parent styles carry differentiator *groups*** (`RMS_ALL_C` / `ALL`); children carry *concrete* diff
IDs. Reversing these is the most common create failure.

**Non-merchandise costs ride inside the order.** The `NON_MERCH_COSTS` array on the inbound document
becomes the `expenses` collection in `purchaseOrders/create` — the `ORDLOC_EXP` equivalent. Unit cost
covers merchandise; these cover freight, duty and handling; together they give landed cost. The
`IN_DUTY` / `IN_EXPENSE` / `IN_ALC` flags decide what each component counts towards and are defaulted
rather than omitted, because omitting them changes the answer.

**Read and write field names differ.** An order read returns `physicalQuantityOrdered` and
`originCountryId`; a write expects `quantityOrdered` and `originCountry`.

**Unknown query parameters are silently ignored.** Passing `dept` instead of `deptId`, or an
`itemParent` filter that does not exist, returns an unfiltered feed that looks like a working filter.

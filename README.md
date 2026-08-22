# Oracle MFCS Office Integration Layer

A PL/SQL and ORDS integration layer for approved Office style and order transactions. It accepts the
legacy PLM-shaped payload, validates it locally, journals every logical step, calls Oracle MFCS through
`APEX_WEB_SERVICE`, and supports idempotent retries after partial completion or ambiguous HTTP timeouts.

**This project always talks to the real MFCS tenant.** There is no client-mode switch and there are no
simulators — the former `MOCK`, `PUBLIC_MOCK` and `LOCAL_MFCS` modes and their mock/local services have
been removed. Ground new work in `docs/mfcs-openapi/openapi.json`, the tenant's own contract.

The approval workflow and APEX user interface are out of scope.

## Layout

Everything lives in one schema, `MFCS_INTEGRATION`. Objects inside it carry no
prefix — the schema name already says what they are.

| Path | What it is |
| --- | --- |
| `database/10_tables/` | Tables, constraints, config seed |
| `database/20_packages/` | One file per package, numbered in dependency order |
| `database/30_ords/` | ORDS module and handlers |
| `deploy/adb-free/` | Scripts to install and verify against a local adb-free container |
| `docs/` | The live call flow, plus the tenant OpenAPI spec |
| `postman/` | Collection for calling MFCS by hand and issuing bearer tokens |
| `tests/` | Live smoke tests against the real tenant |
| `ui/` | React console for entering data and inspecting both payload sets |

## Installation

Run as the schema owner that will expose the ORDS module:

```sql
@deploy/adb-free/install.sql
```

That script encodes the correct order. Each package is a single file holding its
spec and body, so a package must be preceded by everything its body calls — the
numbering in `20_packages/` is that dependency order, not decoration.

For a local adb-free container, run `deploy/adb-free/00_create_schema.sql` and
`01_network_acl.sql` as `ADMIN` first. See `deploy/adb-free/` for the full sequence including
connectivity checks and endpoint sweeps.

## Required privileges

- `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, `CREATE VIEW`, `CREATE TYPE`
- `EXECUTE` on `SYS.DBMS_CRYPTO` for canonical request hashing
- ORDS metadata access for `ORDS.DEFINE_MODULE` / `DEFINE_TEMPLATE` / `DEFINE_HANDLER` / `DEFINE_PRIVILEGE`
- `APEX_WEB_SERVICE` execute access
- Network ACLs allowing `APEX_WEB_SERVICE` to reach **both** the MFCS service host and the IDCS token host

Do not grant or use `UTL_HTTP`; this implementation uses `APEX_WEB_SERVICE`.

## ORDS endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/mfcs/v1/transactions` | Submit a transaction |
| `POST` | `/mfcs/v1/transactions/validate` | Validate without executing |
| `POST` | `/mfcs/v1/transactions/preview` | Build the full MFCS call plan without sending |
| `GET` | `/mfcs/v1/transactions/{actionRequestId}` | Request status |
| `POST` | `/mfcs/v1/transactions/{actionRequestId}/resume` | Resume a partial request |
| `GET` | `/mfcs/v1/reference-data` | Config-driven reference data for the UI |
| `GET` | `/mfcs/v1/requests` | Recent requests, with step progress |
| `GET` | `/mfcs/v1/requests/{id}` | One request: steps, attempts with payloads, event log |
| `GET` | `/mfcs/v1/styles` | List styles live from MFCS |
| `GET` | `/mfcs/v1/styles/{item}` | One item |
| `GET` | `/mfcs/v1/orders` | List orders live from MFCS |
| `GET` | `/mfcs/v1/orders/{orderNo}` | One order, enriched with parent style and display sizes |
| `GET` | `/mfcs/v1/master-data` | Cached foundation data |
| `POST` | `/mfcs/v1/master-data` | Refresh the cache from MFCS |

The resume endpoint is protected by the ORDS privilege `mfcs-resume-support`, bound to role
`mfcs-integration-support`. Normal callers retry by resending the original payload with the same
`ACTION_REQUEST_ID`.

## Packages

| Package | Responsibility |
| --- | --- |
| `config_pkg` | Environment configuration lookup |
| `event_pkg` | Autonomous event log |
| `request_pkg` | Request lifecycle, idempotency hashing, generated identifiers |
| `step_pkg` | Step graph state and attempt journalling |
| `validation_pkg` | Field-level validation of the inbound document |
| `payload_pkg` | Reads the Office document, builds each MFCS request body |
| `client_pkg` | Sole owner of credentials and outbound HTTP |
| `recovery_pkg` | Resolves ambiguous outcomes by correlation ID |
| `orchestrator_pkg` | Step graph, endpoint resolution, execution |
| `preview_pkg` | Builds the call plan without sending |
| `master_pkg` | Foundation-data cache and refresh |
| `browse_pkg` | Live style and order reads, order enrichment |
| `api_pkg` | Public entry points behind the ORDS handlers |
| `ords_util_pkg` | Chunked ORDS response output |

`client_pkg` holds the only implementation of token resolution and outbound HTTP.
`master_pkg` and `browse_pkg` call `client_pkg.get_json` rather than keeping copies —
an earlier duplicate is what allowed a stale cached token to survive in one path and
not another.

## Operations

All five are implemented, with their own step graphs, endpoint resolution and HTTP methods:

| Operation | MFCS calls | Notes |
| --- | --- | --- |
| `CREATE_STYLE` | 8 | Reserve numbers → parent → sourcing → children → country of manufacture → UDAs → approve |
| `CREATE_ORDER` | 3 | Requires an existing `STYLE` |
| `CREATE_ALL` | 11 | Style through to verified purchase order |
| `MODIFY_STYLE` | 4 | All `PUT`. Requires `STYLE` and a `SKU_ID` per size row |
| `MODIFY_ORDER` | 2 | `PUT purchaseOrders/update`, then verify |

`CREATE_STYLE` and `CREATE_ALL` have been proven against the live tenant. `MODIFY_*` produce correct
payloads but have not yet been executed live.

Three rules that cost the most time when got wrong:

- The parent style carries differentiator **groups** (`RMS_ALL_C` / `ALL`); children carry **concrete**
  diff IDs (colour `08610`, sizes `070` / `080`).
- Item approval fails unless sourcing **and** country of manufacture already exist.
- `OTB_EOW_DATE` must fall on the retail week-ending day. The tenant calendar
  (`administration/operations/calendar`) starts every retail month on a Monday, so weeks end on
  **Sunday**. MFCS only enforces this at purchase-order create — step 100 — by which point a style
  exists and an order number has been burned, so `validation_pkg` now checks it up front. The day is
  configurable via `MFCS_OTB_EOW_DAY`.

## Configuration

Non-secret configuration lives in `CONFIG`. Key entries:

- `MFCS_BASE_URL` — the MFCS service host
- `MFCS_TOKEN_URL` — the IDCS identity domain (a **different** host)
- `MFCS_AUTH_MODE` — `STATIC_BEARER` (default) or `OAUTH_CLIENT_CREDENTIALS`
- `MFCS_BEARER_TOKEN_REF` — secret reference used in `STATIC_BEARER` mode
- `MFCS_CLIENT_ID`, `MFCS_SCOPE`, `MFCS_CLIENT_SECRET_REF` — only for OAuth mode
- `HTTP_TRANSFER_TIMEOUT_SECONDS`, `INTERNAL_TIME_BUDGET_SECONDS`
- `BATCH_WINDOW_ACTIVE_YN`
- `FEATURE_ITEM_LOCATIONS_YN`, `FEATURE_INITIAL_RETAIL_YN`
- `ENDPOINT.*` — one per MFCS service path
- `MAP.*` — Office-to-MFCS foundation mappings

`ENDPOINT.INITIAL_RETAIL` is still a placeholder; the tenant spec exposes no matching write service, so
`FEATURE_INITIAL_RETAIL_YN` stays `N`. `FEATURE_ITEM_LOCATIONS_YN` is `N` because no valid location
hierarchy value has been confirmed.

## Credentials

Secrets are never stored in `CONFIG`. `CLIENT_PKG.get_secret` reads
`SECRET`, falling back to `SYS_CONTEXT('MFCS_INTEGRATION_CTX', ...)`.

The intended flow keeps the client secret out of the database entirely: authenticate in Postman, then
store only the short-lived bearer token. The collection in `postman/` prints a ready-to-run `MERGE`
for exactly this. See `postman/README.md`.

## Tenant OpenAPI spec

`docs/mfcs-openapi/openapi.json` is the tenant's own contract (Merch Integration Rest Services
26.1.201.0, 323 paths). Refresh it with:

```
GET {MFCS_BASE_URL}/MerchIntegrations/services/openapi.json
```

It is authoritative for paths, methods and query parameters — prefer it over general Oracle
documentation. The UI's **MFCS spec** tab browses it and flags which paths this bridge wires up.

### Reading the list endpoints

`GET /services/foundation/item` and `GET /services/procurement/order` are **publish/delta feeds**, not
general queries. Per the spec, item publication is limited to items that qualify through the refresh and
delta flow — inserts are not queued until an item is approved, and worksheet/submitted updates are
suppressed. Orders appear only when `ORDHEAD.STATUS` is A, W, S or C with a non-null
`ORIG_APPROVAL_DATE` and type other than DSD. Drive them with `since` / `before` / `offsetkey`.

Resources are singular, and one path serves both shapes: `foundation/item/{id}` for one record,
`foundation/item?filters` for a list. Plural paths return 404.

### Foundation services that are empty on this tenant

`merchhier/deps`, `merchhier/class`, `merchhier/subclass`, `diffid`, `difftype`, `diffgroup`,
`supplier`, `store`, `warehouse` and `uda` all return HTTP 200 with zero rows — publish queues that
have never been seeded, and `since` / `before` does not change it. Only `item/brands`,
`item/foundation/seasons` and `orghier` return foundation rows directly.

`master_pkg` therefore derives hierarchy, differentiator and supplier values from the item
and order feeds instead, and records the source against every cached row so the difference stays
visible rather than being quietly presented as authoritative master data.

## Inspecting requests

```sql
select action_request_id, operation_name, request_status, style_no, order_no, last_updated_at
  from request order by last_updated_at desc;

select step_sequence, step_code, step_status, entity_identifier, last_error_code, last_error_message
  from step where action_request_id = :id order by step_sequence;

select attempt_number, step_code, correlation_id, http_status, attempt_status, started_at, completed_at
  from attempt where action_request_id = :id order by attempt_id;

select * from event_log where action_request_id = :id order by event_id;
```

`EVENT_LOG` is autonomous and records progress even when a step fails.

## Testing

Tests run against the **real tenant**. Rather than simulating failures, the coverage
suite makes MFCS itself reject a call by pointing one `MAP.*` entry at foundation data
that does not exist, so the orchestrator meets a genuine 4xx.

```sql
@tests/resume_coverage_tests.sql
```

Twenty assertions across five scenarios: validation failure with no side effects, a
mid-chain MFCS rejection, resume after correcting the configuration, idempotent replay,
and a changed payload under an existing `ACTION_REQUEST_ID`. The load-bearing assertion
is that a resume does **not** re-call steps that already succeeded.

Because failures happen for real, a failed scenario leaves items in the tenant in
Worksheet status and the resume scenario then approves them. That is deliberate — a
resume cannot be proven without something real to resume — but it means dev tenant only.

```sql
@tests/live_mfcs_create_style_smoke.sql
@tests/live_mfcs_create_all_smoke.sql
```

```powershell
.\tests\ords_operation_smoke.ps1
```

These create real records in the dev tenant. The `preview` endpoint and the UI's preview button are the
safe way to inspect behaviour without side effects.

## Constraints

- No distributed transaction exists across MFCS calls.
- Request, step, attempt, correlation ID, response and generated identifiers are committed as they happen.
- Ambiguous identifier-generating calls are not blindly repeated; recovery queries MFCS operation status
  by `X-Correlation-ID`. That lookup requires `xCorrelationId` as a **query parameter** — as a header
  alone MFCS returns HTTP 400.
- The integration does not delete successfully created MFCS entities as compensation.
- Tenant UDA definitions, differentiators, CFAS, localization, approval rules, initial-retail behaviour
  and batch dependencies remain tenant-validation gates.

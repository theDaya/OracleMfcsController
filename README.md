# Oracle MFCS Office Integration Layer

A PL/SQL and ORDS integration layer for approved Office style and order transactions. It accepts the
legacy PLM-shaped payload, validates it locally, journals every logical step, calls Oracle MFCS through
`APEX_WEB_SERVICE`, and supports idempotent retries after partial completion or ambiguous HTTP timeouts.

**This project always talks to the real MFCS tenant.** There is no client-mode switch and there are no
simulators — the former `MOCK`, `PUBLIC_MOCK` and `LOCAL_MFCS` modes and their mock/local services have
been removed. Ground new work in `docs/mfcs-openapi/openapi.json`, the tenant's own contract.

The approval workflow and APEX user interface are out of scope.

## Layout

| Path | What it is |
| --- | --- |
| `database/` | Tables, config, packages and ORDS module — the integration layer |
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

That script encodes the correct order. If you install by hand, note that
`013_office_mfcs_payload_pkg.sql` must load **after** the specs in `010` but **before** the bodies in
`011`, because `office_mfcs_mapping_pkg` calls `office_mfcs_payload_pkg.build_request` statically.

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
| `POST` | `/office-mfcs/v1/transactions` | Submit a transaction |
| `POST` | `/office-mfcs/v1/transactions/validate` | Validate without executing |
| `POST` | `/office-mfcs/v1/transactions/preview` | Build the full MFCS call plan without sending |
| `GET` | `/office-mfcs/v1/transactions/{actionRequestId}` | Request status |
| `POST` | `/office-mfcs/v1/transactions/{actionRequestId}/resume` | Resume a partial request |
| `GET` | `/office-mfcs/v1/reference-data` | Config-driven reference data for the UI |
| `GET` | `/office-mfcs/v1/requests` | Recent requests |

The resume endpoint is protected by the ORDS privilege `office-mfcs-resume-support`, bound to role
`office-mfcs-integration-support`. Normal callers retry by resending the original payload with the same
`ACTION_REQUEST_ID`.

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

Two rules that cost the most time when got wrong:

- The parent style carries differentiator **groups** (`RMS_ALL_C` / `ALL`); children carry **concrete**
  diff IDs (colour `08610`, sizes `070` / `080`).
- Item approval fails unless sourcing **and** country of manufacture already exist.

## Configuration

Non-secret configuration lives in `OFFICE_MFCS_CONFIG`. Key entries:

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

Secrets are never stored in `OFFICE_MFCS_CONFIG`. `OFFICE_MFCS_CLIENT_PKG.get_secret` reads
`OFFICE_MFCS_SECRET`, falling back to `SYS_CONTEXT('OFFICE_MFCS_CTX', ...)`.

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

## Inspecting requests

```sql
select action_request_id, operation_name, request_status, style_no, order_no, last_updated_at
  from office_mfcs_request order by last_updated_at desc;

select step_sequence, step_code, step_status, entity_identifier, last_error_code, last_error_message
  from office_mfcs_step where action_request_id = :id order by step_sequence;

select attempt_number, step_code, correlation_id, http_status, attempt_status, started_at, completed_at
  from office_mfcs_attempt where action_request_id = :id order by attempt_id;

select * from office_mfcs_event_log where action_request_id = :id order by event_id;
```

`OFFICE_MFCS_EVENT_LOG` is autonomous and records progress even when a step fails.

## Testing

Test coverage is currently **live-only**. Removing the simulators also removed the offline PL/SQL suites
that depended on `MFCS_CLIENT_MODE = MOCK`; rebuilding equivalent coverage against recorded fixtures is
outstanding work.

```sql
@tests/live_mfcs_create_style_smoke.sql
@tests/live_mfcs_create_all_smoke.sql
```

```powershell
.\tests\office_mfcs_ords_operation_smoke.ps1
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

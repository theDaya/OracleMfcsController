# Oracle MFCS Office Integration Layer

This repository contains a PL/SQL and ORDS integration layer for approved Office style/order transactions. It accepts the legacy PLM-shaped payload, validates it locally, journals every logical step, calls Oracle MFCS through `APEX_WEB_SERVICE`, and supports idempotent retries after partial completion or ambiguous HTTP timeouts.

The approval workflow and APEX user interface are intentionally out of scope.

## Deliverables

- `database/001_office_mfcs_tables.sql`
- `database/002_office_mfcs_constraints.sql`
- `database/003_office_mfcs_config.sql`
- `database/010_office_mfcs_package_specs.sql`
- `database/011_office_mfcs_package_bodies.sql`
- `database/020_office_mfcs_ords.sql`
- `tests/office_mfcs_mock_pkg.sql`
- `tests/office_mfcs_integration_tests.sql`
- `tests/office_mfcs_permutation_tests.sql`
- `tests/office_mfcs_public_contract_pkg.sql`
- `tests/office_mfcs_public_contract_e2e.sql`
- `tests/generate_local_tls.py`
- `tests/office_mfcs_ords_operation_smoke.ps1`
- `tests/sample_create_all.json`
- `mock-mfcs/server.js`
- `mock-mfcs/server.test.js`
- `local-mfcs/install.sql`
- `local-mfcs/database/*`
- `local-mfcs/tests/local_mfcs_controller_e2e.sql`
- `local-mfcs/tests/local_mfcs_ords_smoke.ps1`

## Installation Order

Run these as the schema owner that will expose the ORDS module:

```sql
@database/001_office_mfcs_tables.sql
@database/002_office_mfcs_constraints.sql
@database/003_office_mfcs_config.sql
@database/010_office_mfcs_package_specs.sql
@database/011_office_mfcs_package_bodies.sql
@database/020_office_mfcs_ords.sql
```

For local tests, install the mock package after the application packages:

```sql
@tests/office_mfcs_mock_pkg.sql
@tests/office_mfcs_integration_tests.sql
```

Install `tests/office_mfcs_public_contract_pkg.sql` only when using the public-contract simulator. It is dynamically invoked only in `PUBLIC_MOCK` mode and is not a production mapper.

For a complete local controller plus stateful RMS simulator installation, use:

```sql
@local-mfcs/install.sql
```

See `local-mfcs/README.md` for its RMS-shaped tables, public MFCS routes, seed data, tests, and deliberate scope limits.

## Required Privileges

The schema needs:

- `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, `CREATE VIEW`
- `EXECUTE` on `SYS.DBMS_CRYPTO` for canonical request hashing
- ORDS metadata access required by `ORDS.DEFINE_MODULE`, `ORDS.DEFINE_TEMPLATE`, `ORDS.DEFINE_HANDLER`, and `ORDS.DEFINE_PRIVILEGE`
- `APEX_WEB_SERVICE` execute access for outbound MFCS REST calls
- Network ACLs allowing `APEX_WEB_SERVICE` to reach the MFCS OAuth and service hosts

Do not grant or use `UTL_HTTP`; this implementation uses `APEX_WEB_SERVICE`.

## ORDS Endpoints

The ORDS script creates:

- `POST /office-mfcs/v1/transactions`
- `POST /office-mfcs/v1/transactions/validate`
- `GET /office-mfcs/v1/transactions/{actionRequestId}`
- `POST /office-mfcs/v1/transactions/{actionRequestId}/resume`

The resume endpoint is protected with the ORDS privilege `office-mfcs-resume-support`, bound to role `office-mfcs-integration-support`. Map that role to your integration-support users in your ORDS security configuration.

Normal callers should retry by resending the original payload with the same `ACTION_REQUEST_ID`.

## Environment Configuration

Non-secret configuration lives in `OFFICE_MFCS_CONFIG`.

Important keys:

- `MFCS_CLIENT_MODE`: `MOCK` for PL/SQL tests, `PUBLIC_MOCK` for the Node HTTP simulator, `LOCAL_MFCS` for the stateful Oracle simulator, or a production mode for real MFCS calls
- `MFCS_BASE_URL`
- `MFCS_TOKEN_URL`
- `MFCS_CLIENT_ID`
- `MFCS_SCOPE`
- `MFCS_CLIENT_SECRET_REF`
- `MFCS_WALLET_PATH` and `MFCS_WALLET_PASSWORD_REF` when an HTTPS endpoint needs a customer-managed wallet
- `HTTP_TRANSFER_TIMEOUT_SECONDS`
- `INTERNAL_TIME_BUDGET_SECONDS`
- `BATCH_WINDOW_ACTIVE_YN`
- `ENDPOINT.*`
- `MAP.*`

Endpoint paths are configurable because the Office tenant OpenAPI document is authoritative.

## Public-Contract Simulator

`mock-mfcs` is a stateful Node.js simulator for the complete item-to-order chain used by this controller. It covers OAuth, item-number reservation, item create/update, suppliers, UDAs, locations, approval fields, pre-issued order numbers, purchase-order create/update, order verification, and correlation-status lookup.

The routes and public mapper follow Oracle's published contracts for [items](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/items-rest.htm), [purchase orders](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/purch-ord-rest.htm), and [REST service status](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/rest-admin.htm). This is the full chain needed by this project, not an implementation of every MFCS service.

```powershell
node --test .\mock-mfcs\server.test.js
node .\mock-mfcs\server.js
```

See `mock-mfcs/README.md` for HTTPS and database E2E details.

## Local MFCS Simulator

`local-mfcs` persists the public-contract item-to-order chain in a compact RMS-shaped schema. It includes the requested `ITEM_MASTER`, `ITEM_SUPPLIER`, `ITEM_SUPP_COUNTRY`, differentiator, `ORDHEAD`, `ORDSKU`, and `ORDLOC` relationships, plus the minimum foundation, item-location, UDA, reservation, and correlation tables needed to make the chain behave coherently.

The simulator is based on Oracle's public service and functional documentation and is not represented as the complete licensed RMS 16/MFCS physical model. It stops before inventory transactions, stock ledger, receiving, invoicing, and financial posting.

## OAuth Placeholders

Secrets are not stored in `OFFICE_MFCS_CONFIG`. `MFCS_CLIENT_SECRET_REF` is only a reference.

`OFFICE_MFCS_CLIENT_PKG.get_secret` is a replaceable hook. Wire it to the approved RDS secret-storage mechanism before enabling real MFCS calls. The package caches OAuth client-credentials tokens until shortly before expiry and never logs bearer tokens or client secrets.

## OpenAPI Schemas

Use the Office tenant OpenAPI document as the source of truth:

```text
https://<office-hostname>/<namespace>/MerchIntegrations/services/openapi.yaml
```

The production mapper deliberately emits schema-pending envelopes while `MFCS_SCHEMA_READY_YN = N`. The `PUBLIC_MOCK` mapper supplies a documented subset for simulator testing. Complete the production methods after loading the tenant schemas and mapping configuration:

- `OFFICE_MFCS_MAPPING_PKG.build_item_create_request`
- `OFFICE_MFCS_MAPPING_PKG.build_item_sourcing_request`
- `OFFICE_MFCS_MAPPING_PKG.build_item_uda_request`
- `OFFICE_MFCS_MAPPING_PKG.build_item_location_request`
- `OFFICE_MFCS_MAPPING_PKG.build_item_approval_request`
- `OFFICE_MFCS_MAPPING_PKG.build_initial_retail_request`
- `OFFICE_MFCS_MAPPING_PKG.build_purchase_order_request`

For purchase-order creation, preserve `"dataLoadingDestination": "RMS"`.

## Testing

The SQL tests use `OFFICE_MFCS_MOCK_PKG` and `MFCS_CLIENT_MODE = MOCK`.

```sql
@database/001_office_mfcs_tables.sql
@database/002_office_mfcs_constraints.sql
@database/003_office_mfcs_config.sql
@database/010_office_mfcs_package_specs.sql
@database/011_office_mfcs_package_bodies.sql
@tests/office_mfcs_mock_pkg.sql
@tests/office_mfcs_integration_tests.sql
```

The tests cover successful `CREATE_ALL`, validation failure before side effects, partial completion, idempotent duplicates, changed-payload conflict, safe resume, ambiguous timeout recovery, manual review, generated ID returns, and batch-window handling.

Run the extended incomplete-payload and operation matrix after the core suite:

```sql
@tests/office_mfcs_permutation_tests.sql
```

The permutation suite covers all five operations, their expected step graphs and HTTP methods, supplied and generated identifier responses, successful and unsuccessful entity-map resolution, missing and blank fields, identifier-rule combinations, empty/duplicate/incomplete variants, quantity and price boundaries, mapping misses, date formats and relationships, feature-controlled initial retail, and volatile-field idempotency.

Run the public-contract mapper and HTTP E2E fixture after configuring a trusted HTTPS wallet for the local simulator:

```sql
@tests/office_mfcs_public_contract_pkg.sql
@tests/office_mfcs_public_contract_e2e.sql
```

With the local `adb-free` container and ORDS HTTPS listener running, exercise all five operations through ORDS:

```powershell
.\tests\office_mfcs_ords_operation_smoke.ps1
```

The ORDS smoke runner checks five completed transactions plus representative HTTP 400 and 422 cases through the live HTTPS handlers.

Run the stateful Local MFCS tests after installing `local-mfcs`:

```sql
@local-mfcs/tests/local_mfcs_controller_e2e.sql
@local-mfcs/tests/verify_install.sql
```

```powershell
.\local-mfcs\tests\local_mfcs_ords_smoke.ps1
```

## Inspecting Requests

```sql
select action_request_id, operation_name, request_status, style_no, order_no, last_updated_at
from office_mfcs_request
order by last_updated_at desc;

select step_sequence, step_code, step_status, entity_identifier, last_error_code, last_error_message
from office_mfcs_step
where action_request_id = :action_request_id
order by step_sequence;

select attempt_number, step_code, correlation_id, http_status, attempt_status, started_at, completed_at
from office_mfcs_attempt
where action_request_id = :action_request_id
order by attempt_id;
```

## Resuming Partial Requests

Use one of these:

- Normal caller: resend the original payload with the same `ACTION_REQUEST_ID`
- Support user: `POST /office-mfcs/v1/transactions/{actionRequestId}/resume`

Succeeded steps are skipped. Persisted item, SKU, and order identifiers are reused. The integration does not automatically delete successfully created MFCS entities as compensation.

## Important Constraints

- No distributed transaction exists across MFCS calls.
- The integration commits request, step, attempt, correlation ID, response, and generated identifiers as they happen.
- Ambiguous identifier-generating calls are not blindly repeated; the recovery package queries MFCS operation status by `X-Correlation-ID`.
- Final production payload schemas must come from the Office tenant OpenAPI YAML.
- Public documentation does not resolve tenant UDA definitions, differentiators, CFAS, localization, approval rules, initial-retail behavior, foundation data, or batch dependencies; these remain tenant-validation gates.

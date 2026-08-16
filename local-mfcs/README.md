# Local MFCS RMS Simulator

This package turns the Office controller into a stateful local MFCS test system. It exposes an MFCS-shaped REST chain through ORDS and persists the resulting merchandising state in a compact RMS-shaped schema.

It is intentionally an operational subset, not a copy of Oracle's proprietary full data model. Public Oracle documentation describes the service contracts and key table relationships; the complete RMS 16/MFCS physical model remains licensed documentation.

## Included Model

Foundation data:

- `SUPS`, `COUNTRY`, `STORE`, `WH`
- `DEPS`, `CLASS`, `SUBCLASS`
- `DIFF_TYPE`, `DIFF_IDS`, `DIFF_GROUP_HEAD`, `DIFF_GROUP_DETAIL`

`DIFF_GROUPS` is supplied as a convenient flattened compatibility view over the group header/detail pair.

Item data:

- `ITEM_MASTER`
- `ITEM_SUPPLIER`
- `ITEM_SUPP_COUNTRY`
- `ITEM_LOC`
- `ITEM_UDA`

Purchase-order data:

- `ORDHEAD`
- `ORDSKU`
- `ORDLOC`

Simulator support tables reserve item/order numbers and journal REST calls by correlation ID. `LOCAL_MFCS_ITEM_V` and `LOCAL_MFCS_ORDER_V` provide convenient inspection views.

## Install

Run from the repository root as the ORDS-enabled application schema:

```sql
@local-mfcs/install.sql
```

The installer includes the Office controller and public-contract mapper, creates and seeds the local RMS subset, defines both ORDS modules, and sets `MFCS_CLIENT_MODE` to `LOCAL_MFCS`.

The schema owner needs `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, and `CREATE VIEW`, plus the controller privileges listed in the root README.

To install only the simulator into an existing controller schema, run `local-mfcs/database/001` through `030` in numeric order.

## REST Surface

Base URL:

```text
https://localhost:8443/ords/office_mfcs_app/local-mfcs/
```

Implemented routes cover OAuth token issuance, item and order number reservation, item create/update, supplier-country sourcing, UDAs, item locations, PO create/update, procurement order lookup, and REST operation-status lookup. Administrative routes provide health, state, and transactional reset for local tests.

This ORDS module is for local development only. Its token is synthetic and its `__admin/state` and `__admin/reset` routes are deliberately unauthenticated; do not expose it on a shared or internet-accessible ORDS deployment.

The Office-facing controller remains available at:

```text
POST /ords/office_mfcs_app/office-mfcs/v1/transactions
```

In `LOCAL_MFCS` mode, controller calls execute the same simulator package in-process while preserving the controller's request, step, attempt, and correlation journals. The simulator's public ORDS endpoints exercise the same package independently.

## Tests

Run the controller-to-database test:

```sql
@local-mfcs/tests/local_mfcs_controller_e2e.sql
@local-mfcs/tests/verify_install.sql
```

Run the public ORDS-to-database smoke test from PowerShell:

```powershell
.\local-mfcs\tests\local_mfcs_ords_smoke.ps1
```

The SQL test covers the complete `CREATE_ALL` workflow, RMS hierarchy and sourcing relationships, PO totals, idempotency, and invalid diff rejection. The HTTP smoke covers direct service create/update routes, persisted state, correlation status, and a representative validation failure.

## Deliberate Limits

- No stock ledger, inventory movements, shipments, receipts, invoices, allocations, deals, or financial posting.
- No attempt to reproduce Oracle internals, triggers, batch programs, partitioning, or every RMS column.
- Foundation seeds are test fixtures and must be adjusted to match a target tenant.
- Tenant OpenAPI, differentiator setup, UDA definitions, and validation rules remain the final authority before testing a real MFCS instance.

Public contract and relationship references:

- [Items REST services](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/items-rest.htm)
- [Item foundation and differentiators](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/ritug/item-foundation-data.htm)
- [Purchase Order REST services](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/purch-ord-rest.htm)
- [Allocation persistence table relationships](https://docs.oracle.com/en/industries/retail/retail-allocation-cloud/latest/ralog/persistence-layer-integration-including-tables-and-triggers.htm)

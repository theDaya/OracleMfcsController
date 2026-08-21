# Office MFCS Console

A single screen for entering style and order data, showing **both** payload sets side by side:

- **Inbound** — the Office/PLM-shaped document posted to *our* interface (`POST /office-mfcs/v1/transactions`)
- **Outbound** — the ordered per-endpoint payloads this layer would send to *MFCS*

## Running it

The ORDS handlers must be installed (`deploy/adb-free/install.sql`) and the adb-free container running.

```bash
cd ui
npm install
npm run dev
```

Then open <http://localhost:5173>.

Vite proxies `/api/*` to `https://localhost:8443/ords/office_mfcs/office-mfcs/v1/*`. That handles both
the CORS preflight and ORDS's self-signed certificate, so no browser exceptions are needed. Override
with `ORDS_URL` / `ORDS_SCHEMA` env vars if your container differs.

## Where the logic lives

Deliberately almost all of it is in PL/SQL. The React app holds no mapping rules:

| Concern | Lives in |
| --- | --- |
| Field validation | `office_mfcs_validation_pkg` |
| Step graph per operation | `office_mfcs_request_pkg.initialize_steps` |
| Step → endpoint / HTTP method | `office_mfcs_orchestrator_pkg` |
| MFCS payload construction | `office_mfcs_mapping_pkg` → `office_mfcs_payload_pkg` |
| Assembling the preview | `office_mfcs_preview_pkg` |
| Dropdown reference data | `GET /reference-data`, read from `OFFICE_MFCS_CONFIG` |

The browser builds only the inbound document (`buildInboundPayload` in `src/api.js`), which is just a
shape, not business logic. Everything downstream of that comes from the database.

`office_mfcs_preview_pkg` reuses the orchestrator's own step graph and endpoint resolution rather than
reimplementing them, so the preview cannot drift from what execution would really do. It registers a
throwaway `PREVIEW-` request so the existing mappers can run, then deletes it — previews leave no
trace in `OFFICE_MFCS_REQUEST` and never appear in the request list.

## Two buttons

**Preview payloads** is read-only and safe. It calls `/transactions/preview`, which sends nothing to
MFCS.

**Submit to live MFCS** actually executes against the dev tenant and creates real items and orders. It
is behind a confirmation dialog and styled as destructive for a reason.

## What the preview cannot show

Identifiers MFCS generates — item numbers and order numbers — are only known once the request really
runs. They appear as `null` in the preview. Everything else (hierarchy, sourcing, diffs, dates,
locations, costs) is the exact JSON that would go on the wire.

## Operations

All five are supported and were verified end to end against the tenant's mappers:

| Operation | Calls | Notes |
| --- | --- | --- |
| `CREATE_STYLE` | 8 | Reserve → parent → sourcing → children → COM → UDAs → approve |
| `CREATE_ORDER` | 3 | Requires an existing `STYLE` |
| `CREATE_ALL` | 11 | Full chain, style through verified PO |
| `MODIFY_STYLE` | 4 | All PUT. Requires `STYLE` and `SKU_ID` on each size row |
| `MODIFY_ORDER` | 2 | PUT `purchaseOrders/update`, then verify. Requires `ORDER_NO` |

The header pills show that you are pointed at the live tenant (hover for the base URL) and which
feature flags are off. There is no simulator mode to fall back to — every call is real.

## MFCS spec tab

Browses `docs/mfcs-openapi/openapi.json`, the tenant's own contract. Filter by path, summary or method,
and tick *Only endpoints this bridge uses* to see just the 17 wired-up services. Expanding a path shows
each operation's summary, description, parameter table and request schema.

Vite serves the spec straight from `docs/mfcs-openapi` via `publicDir`, so the 2.75MB file lives in one
place in the repo rather than being duplicated under `ui/`.

# Office MFCS Console

Four top-level tabs over the live MFCS tenant.

| Tab | What it does |
| --- | --- |
| **Transactions** | Build, preview and submit a request; shows both payload sets side by side |
| **Browse** | Existing styles and orders in MFCS; click one to load it into the modify form |
| **Master data** | Locally cached foundation data, with the origin of every value |
| **MFCS spec** | The tenant OpenAPI contract, flagging which paths this bridge uses |

The Transactions tab shows both halves of the picture:

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
| Master-data fetch and cache | `office_mfcs_master_pkg` -> `OFFICE_MFCS_MASTER_DATA` |
| Browse reads and order enrichment | `office_mfcs_master_pkg` |
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

## Browse tab

Lists styles (`GET /styles`) and orders (`GET /orders`) live from MFCS. Click a row to load the full
document, then push it into the modify form with one button.

These are publish feeds, so they show approved and published records only — a style still in worksheet
status will not appear.

**Order enrichment.** A `MODIFY_ORDER` needs a `STYLE` and a `SKU_SIZE` per line, and an order read
supplies neither: detail lines carry SKU numbers but no parent and no size. `GET /orders/:orderNo`
therefore enriches the document server-side — it looks up each line's item to recover `itemParent`, and
reverse-maps the line's size diff through `MAP.SIZE.*` back to a display size. Without that step a
browsed order fails validation on `STYLE_REQUIRED_OR_RESOLVABLE` and `MAPPING_NOT_FOUND`.

Mind the read/write asymmetry: an order read returns `physicalQuantityOrdered` and `originCountryId`,
while a write expects `quantityOrdered` and `originCountry`. `orderToForm` in `src/formState.js`
bridges both spellings.

## Master data tab

Caches foundation data into `OFFICE_MFCS_MASTER_DATA` so the entry form can offer dropdowns. Two
population routes, recorded per row:

- `ENDPOINT:` read straight from a foundation service that returns rows — brands, seasons, org hierarchy
- `DERIVED:` harvested from the item and order feeds

The derived route exists out of necessity. `merchhier/deps`, `merchhier/class`, `merchhier/subclass`,
`diffid`, `difftype`, `diffgroup`, `supplier`, `store`, `warehouse` and `uda` all return HTTP 200 with
**zero rows** on this tenant — they are publish/delta feeds and nothing has been queued into them.
Adding `since` / `before` does not change that. The item feed still carries `dept`, `deptName`, `class`,
`className`, `subclass`, `subclassName`, `diff1`, `diff2` and the supplier block, so those values are
recovered from it instead.

A 2,000-item scan produced 219 colour diffs and 26 size diffs — which is what the hardcoded
`MAP.COLOUR.*` and `MAP.SIZE.*` entries were standing in for. Derived values are real, but only as
complete as the items and orders that exist; they are not the full tenant master.

Dropdowns are datalists rather than hard selects for exactly that reason: they suggest known values
while still accepting a code the cache has not seen.

Refresh failures are logged per source rather than aborting the run, so an expired bearer token shows
as HTTP 401 against each service instead of an unexplained empty cache.

## MFCS spec tab

Browses `docs/mfcs-openapi/openapi.json`, the tenant's own contract. Filter by path, summary or method,
and tick *Only endpoints this bridge uses* to see just the 17 wired-up services. Expanding a path shows
each operation's summary, description, parameter table and request schema.

Vite serves the spec straight from `docs/mfcs-openapi` via `publicDir`, so the 2.75MB file lives in one
place in the repo rather than being duplicated under `ui/`.

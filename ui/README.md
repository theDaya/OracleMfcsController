# Office MFCS Console

Four top-level tabs over the live MFCS tenant.

A small MFCS hub: make things, watch what you made, look at what is already there, and check the
contract you are working against.

| Tab | What it does |
| --- | --- |
| **Build** | Create or modify a style or order; preview the calls, then submit |
| **Activity** | Transactions submitted from here — step graph, HTTP attempts with payloads, event log, resume |
| **Styles & orders** | What currently exists in MFCS; click one to load it into the modify form |
| **Master data** | Cached foundation data behind the dropdowns, with the origin of every value |
| **MFCS spec** | The tenant OpenAPI contract, flagging which paths this bridge uses |

## Activity tab

The point of this tab is turning a bare `PARTIALLY_COMPLETED` into an explanation. Selecting a
request shows:

- **Steps** — the graph with per-step status and any generated identifier
- **Attempts** — every HTTP call, with the exact request and response bodies; failing attempts open
  by default, so the MFCS error text is the first thing you see
- **Events** — the autonomous log, which records progress even when a step later fails
- **Payload** — the inbound document as submitted, and the response returned to the caller

Resumable requests (`PARTIALLY_COMPLETED`, `OUTCOME_UNKNOWN`, `MANUAL_REVIEW`) get a resume button.
Resume replays the **stored** payload, so a request that failed because of a bad value in that
payload cannot be rescued by resuming — it needs a fresh request with the value corrected.

The Transactions tab shows both halves of the picture:

- **Inbound** — the Office/PLM-shaped document posted to *our* interface (`POST /mfcs/v1/transactions`)
- **Outbound** — the ordered per-endpoint payloads this layer would send to *MFCS*

## Running it

The ORDS handlers must be installed (`deploy/adb-free/install.sql`) and the adb-free container running.

```bash
cd ui
npm install
npm run dev
```

Then open <http://localhost:5173>.

Vite proxies `/api/*` to `https://localhost:8443/ords/mfcs_integration/mfcs/v1/*`. That handles both
the CORS preflight and ORDS's self-signed certificate, so no browser exceptions are needed. Override
with `ORDS_URL` / `ORDS_SCHEMA` env vars if your container differs.

## Where the logic lives

Deliberately almost all of it is in PL/SQL. The React app holds no mapping rules:

| Concern | Lives in |
| --- | --- |
| Field validation | `validation_pkg` |
| Step graph per operation | `request_pkg.initialize_steps` |
| Step → endpoint / HTTP method | `orchestrator_pkg` |
| MFCS payload construction | `payload_pkg` |
| Assembling the preview | `preview_pkg` |
| Master-data fetch and cache | `master_pkg` -> `MASTER_DATA` |
| Credentials and outbound HTTP | `client_pkg` (sole owner) |
| Browse reads and order enrichment | `browse_pkg` |
| Dropdown reference data | `GET /reference-data`, read from `CONFIG` |

The browser builds only the inbound document (`buildInboundPayload` in `src/api.js`), which is just a
shape, not business logic. Everything downstream of that comes from the database.

`preview_pkg` reuses the orchestrator's own step graph and endpoint resolution rather than
reimplementing them, so the preview cannot drift from what execution would really do. It registers a
throwaway `PREVIEW-` request so the existing mappers can run, then deletes it — previews leave no
trace in `REQUEST` and never appear in the request list.

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

## How the entities hang together

MFCS does not hand you the hierarchy in one call, and two facts drive the whole browse screen:

- **A parent item read does not list its children.** `foundation/item/{id}` on a style returns the
  style and its `itemSupplier` block, nothing else.
- **There is no `itemParent` query filter.** The spec's parameters are `since`, `before`, `itemLevel`,
  `tranLevel`, `deptId`, `classId`, `subclassId`, `status`, `itemType`, `inventoryInd`, `supplier`,
  `referenceItem`, `offsetkey` and `limit`. Passing `itemParent` is silently ignored and you get an
  unfiltered feed, which looks like a filter that worked.

A third check settles it for that API: the item response **schema** carries no child collection
either. `itemParent` and `itemGrandparent` point upward, and `referenceItem` holds level-3 reference
items such as UPCs, not child SKUs. Oracle's published documentation agrees — same parameter list, no
child service.

**But the tenant serves a second, older API family that is absent from the MerchIntegrations OpenAPI
document**, and it does the job in one call:

```
GET /RmsReSTServices/services/private/Item/itemDetail?item=<style>
```

It returns the style *together with its children*. Asking for a style returns three rows (parent plus
two SKUs); asking for a SKU returns just that SKU; an unknown item returns 400. The array is not
ordered parent-first, so children are matched on `itemParent` rather than position.

`browse_pkg.get_style(item, withSkus => 'Y')` uses it to discover the child numbers, then reads each
child in full through the MerchIntegrations item service — `itemDetail` carries 24 fields where the
MerchIntegrations read carries 118, and the detail regions need the richer document.

Because `itemDetail` is undocumented for this tenant, the previous approach survives as a fallback:
page the item feed asking only for `item` and `itemParent` via the `include` parameter, which takes a
200-row page from roughly 1.1MB to 30KB. `resolved.source` records which path was taken, and
`resolved.truncated` warns when a fallback scan hit its cap.

## Browse detail view

Selecting a row gives two tabs: **Detail** and **JSON**.

Detail lays the one-to-one parts out flat — the order header, then the style — because an order maps
to exactly one style. The one-to-many parts sit in tabbed regions underneath: SKUs, order lines, item
supplier, supplier countries, countries of manufacture and UDAs. Supplier, country and UDA rows are
aggregated across the style *and* its SKUs, each tagged with the item it came from, so you can see at
a glance which SKU is missing a country of manufacture.

Selecting an **order** fills everything: order header, the style it resolved to, that style's SKUs and
all the regions. Selecting a **style** fills the style half only — no order header, no order lines.

## Master data tab

Caches foundation data into `MASTER_DATA` so the entry form can offer dropdowns. Two
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

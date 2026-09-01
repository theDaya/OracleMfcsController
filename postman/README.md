# MFCS Postman Collection

Live Oracle MFCS calls for the Office integration bridge, plus read-only calls for building a
style/order viewer.

## Files

| File | Purpose |
| --- | --- |
| `OracleMFCS.postman_collection.json` | The collection: 45 requests across 10 folders |
| `MFCS-Dev.postman_environment.json` | Environment holding the two hosts and your credentials |

Import both into Postman, select the environment, then fill in `clientId` and `clientSecret`.

## Two hosts, two variables

These are genuinely different hosts and are kept as separate variables:

| Variable | Value |
| --- | --- |
| `tokenUrl` | `https://idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com/oauth2/v1/token` |
| `baseUrl` | `https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs` |

Only the token request uses `tokenUrl`. Everything else hangs off `baseUrl`.

## Keeping credentials out of the database

The collection is built around the flow you asked for: authenticate in Postman, put only the
short-lived bearer token in the database.

1. Run **00 - Authentication & Discovery → Get OAuth Token**.
2. The test script saves the token to the `accessToken` collection variable, so every other request
   in the collection is immediately authenticated.
3. It also writes a ready-to-run `MERGE` statement to the Postman console. Copy that into SQLcl
   against the integration schema and the controller picks the token up on its next call.

The client secret never leaves Postman. The database only ever holds `MFCS_BEARER_TOKEN` in
`SECRET`, which is exactly what `MFCS_AUTH_MODE = STATIC_BEARER` expects.

The collection pre-request script warns in the console once the stored token has expired, rather
than letting you chase a confusing 401.

## Folder map

| Folder | Contents |
| --- | --- |
| `00 - Authentication & Discovery` | Token, token verification, tenant OpenAPI spec |
| `01 - Master Data (GET)` | Read-only calls for a viewer — verified against the live tenant |
| `02 - Item Number Reservation` | Reserve parent and child item numbers |
| `03 - Style / Item Hierarchy` | Create parent, create children, update, approve |
| `04 - Item Sourcing & Country of Manufacture` | Supplier, cost, origin, manufacture country |
| `05 - Item UDAs` | Currently empty arrays — tenant UDA definitions unresolved |
| `06 - Item Locations` | Feature-disabled; requests kept for hierarchy-value hunting |
| `07 - Purchase Orders` | Reserve number, create, verify, update |
| `08 - Diagnostics & Recovery` | Status lookup by correlation ID |
| `09 - Flow: Create Style with SKUs` | The whole create sequence as one runnable folder |

## What the GETs actually do (swept 2026-08-21)

Folder 01 is not guesswork — every path was swept against the live tenant with a real bearer token.
Dead paths were deleted rather than left as noise.

**Confirmed, returns data:**

| Path | Notes |
| --- | --- |
| `GET /foundation/item/{id}` | One item, ~12KB, `action: null` |
| `GET /foundation/item?dept=…` | Item list |
| `GET /procurement/order/{orderNo}` | One order, header + details |
| `GET /procurement/order?…` | Order list; works with no filters, or supplier/dept/status |
| `GET /administration/operations/restService/status` | Needs `xCorrelationId` |

**Routed but empty** — HTTP 200 with a valid paging envelope, zero rows:
`foundation/supplier`, `foundation/uda`, `foundation/store`, `foundation/warehouse`.

**Not routed on this tenant** (removed from the collection): `merchandiseHierarchy`, `department`,
`class`, `subclass`, `diff`, `diffGroup`, `location`, `itemSupplier`, `itemLocation`, and every
plural form (`items`, `stores`, `udas`, `suppliers`).

### Three things worth knowing

**Resources are singular, and one path serves both shapes.** `foundation/item/11743` returns one
record; `foundation/item?dept=1517` returns a list. Plural paths 404.

**Two different 404s.** An HTML Tomcat 404 means no route exists at all. A JSON
`{"status":"ERROR","message":"Resource not Found"}` means the route matched but the record did not.
Only the JSON form is worth iterating on.

**The list endpoints look like publish feeds.** List rows carry `"action": "INSERT"` while
single-record reads carry `"action": null`. That suggests these are integration download feeds —
records queued for publishing — not general queries over the master tables. Confirm coverage before
assuming a viewer built on them shows everything in the tenant.

`xCorrelationId` on the status endpoint must be a **query parameter**. Sending it only as a header
returns HTTP 400 `Query Parameter xCorrelationId is mandatory`. The bridge already does this
correctly in `client_pkg.correlation_status`.

## Running the full chain

Folders chain through collection variables — reserved item and order numbers are captured
automatically, so each create already knows the numbers the reservation just returned.

```
00 auth
02 reserve x3
03 create parent  →  04 parent sourcing
03 create children →  04 child sourcing  →  04 countries of manufacture
05 UDAs
03 approve
07 reserve order  →  07 create PO  →  07 verify PO
```

Folder `09` is that chain pre-assembled for the style half, so you do not have to click through
folders 02–05 in the right order. See below.

## Folder 09 — create a style with SKUs in one run

Open the Collection Runner, select **only** folder `09 - Flow: Create Style with SKUs`, and run it.
It performs the same calls, in the same order, with the same payloads as the integration's
`CREATE_STYLE` step graph:

```
00 preflight (token still valid?)
01 reserve parent          →  {{parentItem}}
02 reserve child SKU 1     →  {{childItem1}}
03 reserve child SKU 2     →  {{childItem2}}
04 create parent style         diff GROUPS   RMS_ALL_C / ALL
05 create parent supplier
06 create child SKUs           concrete diffs 08610 / 070 / 080
07 create child suppliers
08 create countries of manufacture
09 create item UDAs            empty arrays, on purpose
10 READ BACK  itemDetail   →  assert both children exist with the right diffs
11 approve parent + children
12 READ BACK  itemDetail   →  assert all three are status A
```

**It creates real records on the dev tenant and burns real item numbers.** There is no simulator
behind the collection.

Three things about it are deliberate:

**Steps 10 and 12 are the only real verification.** MFCS answers a write that changed nothing with
HTTP 200 `SUCCESS`, so asserting on `status === "SUCCESS"` only catches loud failures. Reading the
style back is what proves the children exist and the approval landed.

**The read-backs use `itemDetail`, not `foundation/item`.** The feed read 404s on a style created
minutes ago, and `itemDetail` is the only call that returns a style with its children in one go. It
answers a JSON array whose rows carry `item`, `itemParent`, `diff1`, `diff2` and `status` — a third
vocabulary, neither the feed's nor the write services'. Both read-backs retry up to three times
before failing, so feed lag is not reported as a silent failure that did not happen.

**Any failure halts the run.** A half-created style makes every following step address items that do
not exist, and the resulting errors all look like payload problems. The console line beginning
`HALTING -` names the request that actually broke.

Each run stamps `{{flowDescription}}` with a fresh timestamp, so repeated runs are distinguishable
in the tenant rather than piling up under one description.

## There is no Flows canvas file

Postman **Flows** — the visual block canvas — has no export or import file format. Flows are
authored in the Postman app against your Postman cloud workspace, and as of this writing exporting
one to a file is still an open feature request, not a capability. A hand-authored `.pmflow` would
not import, so this repo does not carry one; folder `09` is the runnable artifact.

If you want the canvas anyway, it rebuilds from folder `09` in a few minutes: start a flow, add a
**Send Request** block per row of the diagram above pointing at that folder's request, and wire each
block's output into the next block's input, mapping `body.items[0].item` out of the three
reservation blocks into the create blocks. The value of the canvas is watching the data move; the
assertions and the halt-on-failure behaviour already live in the folder.

Two ordering rules are load-bearing:

- Approval must come after sourcing **and** country of manufacture. MFCS rejects it otherwise.
- The parent style carries differentiator *groups* (`RMS_ALL_C` / `ALL`); children carry *concrete*
  diff IDs (colour `08610`, sizes `070` / `080`). Reversing these is the most common create failure.

## Tenant values baked into the variables

These come from the successful smoke runs and are current assumptions, not authoritative foundation
data — the same caveat the bridge's config carries.

| Variable | Value | Source |
| --- | --- | --- |
| `dept` / `class` / `subclass` | 1517 / 6892 / 1128 | Unisex Sports / Nike / Nike Trainers |
| `supplier` | 700087 | Validated against tenant |
| `colourDiff` | 08610 | Concrete colour diff from known-good SKU |
| `size1Diff` / `size2Diff` | 070 / 080 | Tenant size diffs for display sizes 7 / 8 |
| `costZoneGroupId` | 2000 | Observed on foundation item 11743 |
| `manufacturerCountry` | VN | Required by approval validation |
| `orderLocation` | 19271 | MFCS virtual warehouse (Office physical location 1927) |
| `lookupItem` | 11743 | Known-good item for harvesting working values |

Order dates default to sensible relative values (today, +2 days for OTB EOW, +19 days for latest
ship) via the collection pre-request script, so they never go stale.

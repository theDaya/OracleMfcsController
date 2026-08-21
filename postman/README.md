# MFCS Postman Collection

Live Oracle MFCS calls for the Office integration bridge, plus read-only calls for building a
style/order viewer.

## Files

| File | Purpose |
| --- | --- |
| `OracleMFCS.postman_collection.json` | The collection: 32 requests across 9 folders |
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

# Actual MFCS Call Flow

This document captures the current live integration path from the Office-facing payload into the actual MFCS dev tenant.

The style examples below come from successful smoke request `DAYALAN-TEST-20260817164337108`, which completed on 2026-08-17 and created:

- Parent style item `100000180`
- Child SKU items `100000198` and `100000201`

JSON examples are shown as `jsonc` so assumptions can be documented inline. The integration sends strict JSON to MFCS; comments are documentation only.

## Runtime Mode

There is no runtime switch any more — the integration only ever talks to the real tenant.

- `MFCS_AUTH_MODE = STATIC_BEARER`
- `MFCS_BASE_URL = https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs`
- Bearer token stored externally in `SECRET` under config ref `MFCS_BEARER_TOKEN_REF`
- Item locations enabled with `FEATURE_ITEM_LOCATIONS_YN = Y`, ranging to virtual warehouse 19271
- Initial retail disabled by default with `FEATURE_INITIAL_RETAIL_YN = N`
- Purchase-order verification retry enabled with `MFCS_ORDER_VERIFY_RETRY_COUNT = 12` and `MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS = 10`

Item locations now work. Every item-location row in the tenant reads location 19271 / locationType W /
physicalWarehouse 1927, so `MFCS_LOCATION_HIERARCHY_LEVEL = W` and the delivery location is mapped
through `MAP.ORDER_LOCATION.*` from the physical location to the virtual warehouse — MFCS rejects the
physical one at hierarchy level W.

Worth knowing: a purchase order ranges its own items, so only style-only creates need this step.

## Integration Payload Received

The integration layer receives the PLM/Office-style request through `api_pkg.submit_transaction` or `POST /mfcs/v1/transactions`.

```jsonc
{
  "ACTION_REQUEST_ID": "DAYALAN-TEST-20260817164337108",
  "OPERATION_NAME": "CREATE_STYLE",
  "SOURCE_SYSTEM": "OFFICE_DEV",
  "SOURCE_STYLE_REF": "Dayalan test 2026-08-17 16:43:37.108",
  "SOURCE_VERSION": "1",
  "STYLE": null,
  "DESCRIPTION": "Dayalan test x",

  // Current dev tenant foundation used for the successful smoke:
  // dept/class/subclass = Unisex Sports / Nike / Nike Trainers.
  "DEPARTMENT": "1517",
  "CLASS": "6892",
  "SUBCLASS": "1128",

  // Supplier and origin country are assumed to exist in MFCS.
  "SUPPLIER": "700087",
  "ORIGIN_COUNTRY": "GB",
  "CURRENCY_CODE": "ZAR",

  // Important: child SKU colour must be a concrete MFCS colour diff ID.
  // We observed 08610 from existing item 11743.
  // Parent style still uses configured all-colour group RMS_ALL_C.
  "COLOUR": "08610",

  "UNIT_COST": 48.49,
  "RETAIL_PRICE": 100,
  "SIZE_CURVE_DETAIL": [
    {
      "SOURCE_VARIANT_REF": "Dayalan test 2026-08-17 16:43:37.108-7",

      // Integration accepts the display size and maps it through MAP.SIZE.*.
      // For this tenant: 7 -> 070.
      "SKU_SIZE": "7",
      "SKU_WIDTH": "ALL",
      "SKU_QTY": 1,
      "SKU_ID": null
    },
    {
      "SOURCE_VARIANT_REF": "Dayalan test 2026-08-17 16:43:37.108-8",

      // For this tenant: 8 -> 080.
      "SKU_SIZE": "8",
      "SKU_WIDTH": "ALL",
      "SKU_QTY": 1,
      "SKU_ID": null
    }
  ]
}
```

## MFCS Call Sequence

The orchestrator runs these steps for `CREATE_STYLE`:

| Sequence | Step | Method | Endpoint |
| --- | --- | --- | --- |
| 10 | `VALIDATE_REQUEST` | local | local validation only |
| 20 | `RESERVE_ITEM_NUMBERS` | `POST` | `/MerchIntegrations/services/item/itemNumbers/reserve` |
| 30 | `CREATE_PARENT_ITEM_HIERARCHY` | `POST` | `/MerchIntegrations/services/items/create` |
| 35 | `CREATE_PARENT_ITEM_SOURCING` | `POST` | `/MerchIntegrations/services/item/suppliers/create` |
| 40 | `CREATE_CHILD_ITEM_HIERARCHY` | `POST` | `/MerchIntegrations/services/items/create` |
| 50 | `CREATE_ITEM_SOURCING` | `POST` | `/MerchIntegrations/services/item/suppliers/create` |
| 55 | `CREATE_ITEM_COUNTRIES_OF_MANUFACTURE` | `POST` | `/MerchIntegrations/services/item/supplier/countriesOfManufacture/create` |
| 60 | `CREATE_ITEM_UDAS` | `POST` | `/MerchIntegrations/services/item/uda/create` |
| 80 | `APPROVE_ITEMS` | `PUT` | `/MerchIntegrations/services/items/update` |

`CREATE_ITEM_LOCATIONS` is intentionally omitted while `FEATURE_ITEM_LOCATIONS_YN = N`.

## Step 20: Reserve Item Numbers

The configured reservation chunk size is `1`, so the integration calls MFCS once for the parent and once per child SKU. The response is persisted to `ENTITY_MAP`.

```jsonc
// POST /MerchIntegrations/services/item/itemNumbers/reserve
{
  "itemNumberType": "ITEM",
  "quantity": 1,
  "daysUntilExpiry": 1
}
```

Responses from the successful run:

```jsonc
// Parent style item
{
  "items": [
    {
      "item": "100000180",
      "itemNumberType": "ITEM",
      "expiryDate": "2026-08-18"
    }
  ]
}
```

```jsonc
// Child SKU for source size 7
{
  "items": [
    {
      "item": "100000198",
      "itemNumberType": "ITEM",
      "expiryDate": "2026-08-18"
    }
  ]
}
```

```jsonc
// Child SKU for source size 8
{
  "items": [
    {
      "item": "100000201",
      "itemNumberType": "ITEM",
      "expiryDate": "2026-08-18"
    }
  ]
}
```

## Step 30: Create Parent Item Hierarchy

```jsonc
// POST /MerchIntegrations/services/items/create
{
  "collectionSize": 1,
  "items": [
    {
      "item": "100000180",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "dataLoadingDestination": "RMS",
      "itemNumberType": "ITEM",
      "itemLevel": 1,
      "tranLevel": 2,
      "dept": 1517,
      "class": 6892,
      "subclass": 1128,
      "status": "W",
      "approveInd": "N",
      "standardUom": "EA",
      "merchandiseInd": "Y",
      "inventoryInd": "Y",
      "sellableInd": "Y",
      "orderableInd": "Y",
      "storeOrderMultiple": "E",
      "originalRetail": 100,
      "costZoneGroupId": 2000,

      // Parent item uses tenant-level differentiator groups.
      // These defaults are configured as MFCS_PARENT_DIFF1_GROUP and MFCS_PARENT_DIFF2_GROUP.
      "diff1": "RMS_ALL_C",
      "diff1Type": "C",
      "diff2": "ALL",
      "diff2Type": "S"
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 35: Create Parent Item Sourcing

```jsonc
// POST /MerchIntegrations/services/item/suppliers/create
{
  "collectionSize": 1,
  "items": [
    {
      "item": "100000180",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "primarySupplierInd": "Y",
          "countryOfSourcing": [
            {
              "originCountry": "GB",
              "primaryCountryInd": "Y",
              "unitCost": 48.49,

              // Required by this tenant during sourcing.
              "defaultUop": "EA",
              "costUom": "EA",
              "supplierPackSize": 1,
              "innerPackSize": 1,

              // Observed from a working item and required by MFCS.
              "purchaseType": 0
            }
          ]
        }
      ]
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 40: Create Child Item Hierarchy

```jsonc
// POST /MerchIntegrations/services/items/create
{
  "collectionSize": 2,
  "items": [
    {
      "item": "100000198",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108 7 ALL",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "dataLoadingDestination": "RMS",
      "itemParent": "100000180",
      "itemNumberType": "ITEM",
      "itemLevel": 2,
      "tranLevel": 2,
      "dept": 1517,
      "class": 6892,
      "subclass": 1128,
      "status": "W",
      "approveInd": "N",
      "standardUom": "EA",
      "merchandiseInd": "Y",
      "inventoryInd": "Y",
      "sellableInd": "Y",
      "orderableInd": "Y",
      "storeOrderMultiple": "E",
      "originalRetail": 100,
      "costZoneGroupId": 2000,

      // Child items use concrete diff IDs, not the parent's groups.
      // 08610 is the concrete colour diff ID from the request.
      // 070 is MAP.SIZE.7.
      "diff1": "08610",
      "diff1Type": "C",
      "diff2": "070",
      "diff2Type": "S"
    },
    {
      "item": "100000201",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108 8 ALL",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "dataLoadingDestination": "RMS",
      "itemParent": "100000180",
      "itemNumberType": "ITEM",
      "itemLevel": 2,
      "tranLevel": 2,
      "dept": 1517,
      "class": 6892,
      "subclass": 1128,
      "status": "W",
      "approveInd": "N",
      "standardUom": "EA",
      "merchandiseInd": "Y",
      "inventoryInd": "Y",
      "sellableInd": "Y",
      "orderableInd": "Y",
      "storeOrderMultiple": "E",
      "originalRetail": 100,
      "costZoneGroupId": 2000,

      // 080 is MAP.SIZE.8.
      "diff1": "08610",
      "diff1Type": "C",
      "diff2": "080",
      "diff2Type": "S"
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 50: Create Child Item Sourcing

```jsonc
// POST /MerchIntegrations/services/item/suppliers/create
{
  "collectionSize": 2,
  "items": [
    {
      "item": "100000198",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "primarySupplierInd": "Y",
          "countryOfSourcing": [
            {
              "originCountry": "GB",
              "primaryCountryInd": "Y",
              "unitCost": 48.49,
              "defaultUop": "EA",
              "costUom": "EA",
              "supplierPackSize": 1,
              "innerPackSize": 1,
              "purchaseType": 0
            }
          ]
        }
      ]
    },
    {
      "item": "100000201",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "primarySupplierInd": "Y",
          "countryOfSourcing": [
            {
              "originCountry": "GB",
              "primaryCountryInd": "Y",
              "unitCost": 48.49,
              "defaultUop": "EA",
              "costUom": "EA",
              "supplierPackSize": 1,
              "innerPackSize": 1,
              "purchaseType": 0
            }
          ]
        }
      ]
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 55: Create Countries of Manufacture

MFCS would not approve the created items until Country of Manufacture existed. This step is now part of the normal `CREATE_STYLE` sequence.

```jsonc
// POST /MerchIntegrations/services/item/supplier/countriesOfManufacture/create
{
  "collectionSize": 3,
  "items": [
    {
      "item": "100000180",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "countryOfManufacture": [
            {
              // Current assumption comes from the known-good SKU sample.
              // Configured as MFCS_MANUFACTURER_COUNTRY.
              "manufacturerCountry": "VN",
              "primaryManufacturerCountryInd": "Y"
            }
          ]
        }
      ]
    },
    {
      "item": "100000198",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "countryOfManufacture": [
            {
              "manufacturerCountry": "VN",
              "primaryManufacturerCountryInd": "Y"
            }
          ]
        }
      ]
    },
    {
      "item": "100000201",
      "dataLoadingDestination": "RMS",
      "supplier": [
        {
          "supplier": 700087,
          "countryOfManufacture": [
            {
              "manufacturerCountry": "VN",
              "primaryManufacturerCountryInd": "Y"
            }
          ]
        }
      ]
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 60: Create Item UDAs

The current smoke payload does not send UDA values. The mapper still emits an empty UDA array for each child SKU because the endpoint accepts it and it keeps the step explicitly logged.

```jsonc
// POST /MerchIntegrations/services/item/uda/create
{
  "collectionSize": 2,
  "items": [
    {
      "item": "100000198",
      "dataLoadingDestination": "RMS",
      "uda": []
    },
    {
      "item": "100000201",
      "dataLoadingDestination": "RMS",
      "uda": []
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## Step 80: Approve Items

Approval uses the MFCS item update endpoint with `PUT`.

```jsonc
// PUT /MerchIntegrations/services/items/update
{
  "collectionSize": 3,
  "items": [
    {
      "item": "100000180",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "status": "A",
      "approveInd": "Y",

      // Required by approval validation.
      "storeOrderMultiple": "E",
      "dataLoadingDestination": "RMS"
    },
    {
      "item": "100000198",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "status": "A",
      "approveInd": "Y",
      "storeOrderMultiple": "E",
      "dataLoadingDestination": "RMS"
    },
    {
      "item": "100000201",
      "itemDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "shortDescription": "Dayalan test 2026-08-17 16:43:37.108",
      "status": "A",
      "approveInd": "Y",
      "storeOrderMultiple": "E",
      "dataLoadingDestination": "RMS"
    }
  ]
}
```

MFCS response:

```json
{ "status": "SUCCESS" }
```

## CREATE_ALL Payload Received

`CREATE_ALL` uses the same style/SKU payload shape as `CREATE_STYLE`, then continues into order-number reservation, order create, and order verification. The example below is from live request `DAYALAN-ALL-20260821120647643`, which created parent style `100050005`, child SKUs `100050013` and `100050021`, and purchase order `25005`.

```jsonc
{
  "ACTION_REQUEST_ID": "DAYALAN-ALL-20260821120647643",
  "OPERATION_NAME": "CREATE_ALL",
  "SOURCE_SYSTEM": "OFFICE_DEV",
  "SOURCE_STYLE_REF": "Dayalan all 2026-08-21 12:06:47.643",
  "SOURCE_ORDER_REF": "Dayalan all 2026-08-21 12:06:47.643-PO",
  "SOURCE_VERSION": "1",
  "USER_ID": "office.buyer@example.com",
  "STYLE": null,
  "ORDER_NO": null,
  "DESCRIPTION": "Dayalan order test",

  // Same confirmed tenant hierarchy used by CREATE_STYLE.
  "DEPARTMENT": "1517",
  "CLASS": "6892",
  "SUBCLASS": "1128",

  // Supplier 700087, origin GB, and currency ZAR have been validated against the tenant.
  "SUPPLIER": "700087",
  "ORIGIN_COUNTRY": "GB",
  "IMPORT_COUNTRY": "GB",
  "CURRENCY_CODE": "ZAR",

  // Concrete colour diff ID; sizes are mapped through MAP.SIZE.*.
  "COLOUR": "08610",
  "UNIT_COST": 48.49,
  "RETAIL_PRICE": 100,
  "SIZE_CURVE_DETAIL": [
    {
      "SOURCE_VARIANT_REF": "Dayalan all 2026-08-21 12:06:47.643-7",
      "SKU_SIZE": "7",
      "SKU_WIDTH": "ALL",
      "SKU_QTY": 1,
      "SKU_ID": null
    },
    {
      "SOURCE_VARIANT_REF": "Dayalan all 2026-08-21 12:06:47.643-8",
      "SKU_SIZE": "8",
      "SKU_WIDTH": "ALL",
      "SKU_QTY": 1,
      "SKU_ID": null
    }
  ],

  // Dates are passed through to the purchase order header/detail.
  "NOT_BEFORE_DATE": "2026-08-21",
  "NOT_AFTER_DATE": "2026-08-21",
  "OTB_EOW_DATE": "2026-08-23",
  "EARLIEST_SHIP_DATE": "2026-08-21",
  "LATEST_SHIP_DATE": "2026-09-09",

  // Office delivery location 1927 is mapped to MFCS virtual warehouse 19271.
  "DELIVERY_LOC": 1927,
  "PO_TYPE": null,
  "ORDER_EXCHANGE_RATE": 1
}
```

## CREATE_ALL MFCS Sequence

For `CREATE_ALL`, the orchestrator runs every active `CREATE_STYLE` step first, then continues with:

| Sequence | Step | Method | Endpoint |
| --- | --- | --- | --- |
| 90 | `RESERVE_ORDER_NUMBER` | `POST` | `/MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create` |
| 100 | `CREATE_PURCHASE_ORDER` | `POST` | `/MerchIntegrations/services/purchaseOrders/create` |
| 110 | `VERIFY_PURCHASE_ORDER` | `GET` | `/MerchIntegrations/services/procurement/order/{orderNo}` |

The purchase-order endpoint names and payload fields follow Oracle's published Purchase Order Upload and Download services.

## Step 90: Reserve Order Number

The order number is reserved before the purchase-order create call, then stored in `ENTITY_MAP`.

```jsonc
// POST /MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create
{
  "quantity": 1,

  // Configured as MFCS_ORDER_RESERVATION_DAYS_UNTIL_EXPIRY.
  "daysUntilExpiry": 1
}
```

MFCS response from the live request:

```jsonc
{
  "orderNumbers": [
    {
      "orderNo": 25005,
      "expiryDate": "2026-08-22"
    }
  ]
}
```

## Step 100: Create Purchase Order

The mapper sends a strict `items` array to MFCS. The comments below document current assumptions only; comments are not sent on the wire.

```jsonc
// POST /MerchIntegrations/services/purchaseOrders/create
{
  "items": [
    {
      "orderNo": 25005,
      "supplier": 700087,
      "currencyCode": "ZAR",

      // Defaulted from MFCS_ORDER_DEFAULT_TERMS because Office did not send TERMS.
      "terms": "34",

      "notBeforeDate": "2026-08-21",
      "notAfterDate": "2026-08-21",
      "otbEowDate": "2026-08-23",
      "earliestShipDate": "2026-08-21",
      "latestShipDate": "2026-09-09",
      "dept": 1517,

      // Current order defaults are config-driven.
      "status": "A",
      "exchangeRate": 1,
      "includeOnOrderInd": "Y",
      "writtenDate": "2026-08-21",
      "origin": "2",
      "ediPoInd": "N",
      "preMarkInd": "N",
      "approvedBy": "office.buyer@example.com",
      "commentDesc": "Dayalan all 2026-08-21 12:06:47.643-PO",
      "dataLoadingDestination": "RMS",
      "importCountry": "GB",
      "orderType": "N/B",

      // DELIVERY_LOC 1927 maps to virtual warehouse 19271 through MAP.ORDER_LOCATION.1927.
      "location": 19271,
      "locationType": "W",
      "qualityControlInd": "N",
      "freightTerms": "PREPAID",

      "details": [
        {
          "item": "100050013",
          "location": 19271,
          "locationType": "W",
          "unitCost": 48.49,
          "originCountry": "GB",
          "supplierPackSize": 1,
          "quantityOrdered": 1,
          "earliestShipDate": "2026-08-21",
          "latestShipDate": "2026-09-09"
        },
        {
          "item": "100050021",
          "location": 19271,
          "locationType": "W",
          "unitCost": 48.49,
          "originCountry": "GB",
          "supplierPackSize": 1,
          "quantityOrdered": 1,
          "earliestShipDate": "2026-08-21",
          "latestShipDate": "2026-09-09"
        }
      ]
    }
  ]
}
```

MFCS response:

```json
{
  "status": "SUCCESS",
  "message": "createXOrderColDesc service call was successful."
}
```

## Step 110: Verify Purchase Order

MFCS can accept `purchaseOrders/create` before the order is immediately visible through the procurement GET. To handle that publish delay, verification retries are controlled by `MFCS_ORDER_VERIFY_RETRY_COUNT` and `MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS`. Each failed verify attempt is logged, and the autonomous event log records `VERIFY_RETRY_WAIT` before sleeping.

```jsonc
// GET /MerchIntegrations/services/procurement/order/25005
{}
```

Successful verification returns the MFCS order document. The fields below are abbreviated to the parts used for integration proofing.

```jsonc
{
  "items": [
    {
      "orderNo": 25005,
      "status": "A",
      "orderType": "N/B",
      "dept": 1517,
      "supplier": 700087,
      "currencyCode": "ZAR",
      "physicalLocationType": "W",
      "physicalLocation": 1927,
      "virtualWarehouse": 19271,
      "details": [
        {
          "item": "100050013",
          "quantityOrdered": 1,
          "originCountry": "GB",
          "supplierPackSize": 1
        },
        {
          "item": "100050021",
          "quantityOrdered": 1,
          "originCountry": "GB",
          "supplierPackSize": 1
        }
      ]
    }
  ]
}
```

## Step 25/85: Ensure Style SKUs — live, 2026-08-22

The first run of SKU generation against the tenant. Style `100050355` carried one child,
colour `08610` / size `070`. A `MODIFY_STYLE` request named sizes 7, 8 and 9, so two children
had to be created.

**Before** (`RmsReSTServices/services/private/Item/itemDetail?item=100050355`):

```json
{"available":true,"skus":[{"item":"100050363","diff1":"08610","diff2":"070","status":"A"}]}
```

**Parent attributes** used to build the children, from the same read. Note `classAttribute`,
`itemDesc`, `primarySuppInd` and `originCountryId` — itemDetail is a third vocabulary, after the
item feed's and the write services':

```json
{"available":true,"item":"100050355","itemLevel":1,"dept":1517,"class":6892,"subclass":1128,
 "status":"A","originalRetail":100,"itemDescription":"RCT-20260822184151-RESUME",
 "shortDescription":"RCT-20260822184151-RESUME","supplier":700087,"originCountry":"GB","unitCost":48.49}
```

Then, in order: one `POST /item/itemNumbers/reserve` per missing child (2), one
`POST /items/create` carrying both, one `POST /item/suppliers/create`, one
`POST /item/supplier/countriesOfManufacture/create`, one `PUT /items/update` to approve.

**After**, read back rather than inferred from the four HTTP 200s:

```json
{"available":true,"skus":[
  {"item":"100050363","diff1":"08610","diff2":"070","status":"A"},
  {"item":"100050371","diff1":"08610","diff2":"080","status":"A"},
  {"item":"100050380","diff1":"08610","diff2":"090","status":"A"}]}
```

Re-running the same request created nothing: the step read the style, found all three
combinations present, recorded the mapping and moved on. That is the whole re-entrancy
argument — a resume re-derives the gap from the tenant rather than replaying a stored payload.

## The update services: what they demand — live, 2026-08-22

Found by running `MODIFY_STYLE` and `CREATE_ORDER` live for the first time. All the same shape: the
create service defaults a column, the update service requires it, and the error names it exactly.

```json
{"status":"ERROR","message":"Field must be entered.Field: STORE_ORD_MULT, ITEM: 100050355 returned by program unit CORESVC_ITEM.PROCESS_IM."}
{"status":"ERROR","message":"This column should not be null.Field: DIRECT_SHIP_IND, ITEM: 100050363, SUPPLIER: 700087 returned by program unit CORESVC_ITEM.PROCESS_IS."}
{"status":"ERROR","message":"This column should not be null.Field: INNER_NAME, ITEM: 100050363, SUPPLIER: 700087 returned by program unit CORESVC_ITEM.PROCESS_IS."}
```

`storeOrderMultiple` and `directShipInd` are now sent on both paths, and all three packaging names go
together rather than one per failed round trip. The valid values are the tenant's own, from the code
detail load: `INRN` (EA, INR, SCS, SPACK), `CASN` (CS, CT, BX, …), `PALN` (PAL, FLA). `EA` is used
for the inner because the pack sizes here are 1.

Country of manufacture is different — it is not a missing field but a service that cannot be
replayed:

```json
{"status":"ERROR","message":"This item/supplier/manufacturing country already exists.ITEM: 100050398, SUPPLIER: 700087, COUNTRY: VN returned by program unit CORESVC_ITEM.PROCESS_ISMC."}
```

`countriesOfManufacture/update` takes the same body and is used for any style that already exists.

## A transport error is not a failure — live, 2026-08-22

`CREATE_PURCHASE_ORDER` raised `ORA-29273: HTTP request failed` and was recorded as FAILED. MFCS had
created the order. The resume replayed the create and was told:

```json
{"status":"ERROR","message":"Order number 25011 already exists.","businessError":["Order number 25011 already exists."]}
```

A reserved order number burned, and a request reporting `PARTIALLY_COMPLETED` for an order that
existed. The old classification matched the *word* "timeout" in the message, which `ORA-29273` does
not contain. `client_pkg` now classifies on SQLCODE — 29273, 29276, 29259, 12535, 12570 — raises
`-20952`, and lets `recovery_pkg` resolve the outcome by correlation ID. A call that never landed
resolves to `NO_RECORD` and the step simply runs again.

## The nightly batch window — live, 2026-08-22

Writes stop with a plain HTTP 400 whose body is a business message:

```json
{"status":"ERROR","message":"Batch Running Indicator is ON.  Cannot execute operation while nightly batch is in progress."}
```

Unclassified this reads as a rejected payload. `client_pkg` matches it and raises `-20951` with a
message saying to retry afterwards. If the coverage suite fails on that, wait — do not debug.

## Full CREATE_ORDER, live — 2026-08-22

Every step, in order, against style `100050398`:

```
VALIDATE_REQUEST, ENSURE_STYLE_SKUS, CREATE_ITEM_HIERARCHY, CREATE_ITEM_SOURCING,
CREATE_ITEM_COUNTRIES_OF_MANUFACTURE, CREATE_ITEM_UDAS, CREATE_ITEM_LOCATIONS, APPROVE_ITEMS,
RESERVE_ORDER_NUMBER, CREATE_PURCHASE_ORDER, VERIFY_PURCHASE_ORDER
```

HTTP 200, `COMPLETED`, order `25012`. The style write set runs before the order because an order is a
statement about the style — its cost, country and supplier — not only about the order.

## MODIFY_ORDER and the truth about order lines — live, 2026-08-22

`MODIFY_ORDER` ran end to end for the first time: HTTP 200, `COMPLETED`, all ten steps, including
`ENSURE_STYLE_SKUS` creating two missing children inline on the way. But reading order 25012 back
told a different story, in three acts:

1. **`purchaseOrders/update` is header-only in practice.** The run replaced the order's detail
   lines with different items and quantities; SUCCESS came back and the order was untouched. A
   second probe changed only the *quantity* of the order's own existing lines — same items, same
   everything, qty 1 → 4 — same result: `COMPLETED`, order unchanged, still unchanged many minutes
   later. The `details` array on that service is decoration on this tenant.

2. **`purchaseOrder/details/update` works.** The spec carries dedicated line services this
   integration never used: `purchaseOrder/details/create|update|delete`. A direct probe:

   ```json
   PUT /MerchIntegrations/services/purchaseOrder/details/update
   {"items":[{"orderNo":25012,"dataLoadingDestination":"RMS","details":[
     {"item":"100050401","location":19271,"locationType":"W","quantityOrdered":4}]}]}
   → {"status":"SUCCESS","message":"modifyDetail service call was successful."}
   ```

   and the read-back showed qty 4 — **after roughly 30 seconds**, not the few seconds of lag seen
   elsewhere. A verify that reads too soon concludes the write silently failed.

3. **Explicit cancellation exists.** The `details` row shape carries `cancelInd`,
   `quantityCancelled`, `cancelCode` and `reinstateInd`. So the answer to the standing question —
   does a colour change on an existing order need the old line cancelled, or is replacing the
   lines enough? — is now known: replacing is *not* enough (it is ignored); the old colour's line
   is cancelled explicitly and the new colour's line is added with `details/create`.

What follows from this is the top outstanding item: wire the order steps to the line services.

## SYNC_ORDER_LINES: order lines proven both directions — live, 2026-08-22

`MODIFY_ORDER` gained a `SYNC_ORDER_LINES` step (seq 105): read the order, then bring its lines to
what the document says — `details/update` for lines it has, `details/create` for lines it lacks,
and this style's no-longer-named lines cancelled. Scoped to the document's own style: lines of
other styles on the same order are never touched.

Proven live on order 25012, both directions:

- **Quantity change**: 4/1/1 → 2/2/2, the reduction carrying cancel code `B` (Buyer Cancelled).
- **Colour switch 08610 → 08621**: ENSURE_STYLE_SKUS created the 08621 children (after learning
  that the new colour must belong to the parent's diff group — `BLACK` was rejected loudly:
  "This differentiator ID is not part of the parent's differentiator group"), then the sync
  created three 08621 lines and cancelled the three 08610 lines with code `S`
  (Colour/Location Switched — the tenant's own ORCA code list has one for exactly this).
- **Switch back 08621 → 08610**: cancelled lines resurrect via a plain `details/update` with the
  new quantity — a zeroed line is updatable, not dead.

**`quantityCancelled` is cumulative-absolute — do not send it.** A line that had 2 cancelled
earlier ignores a fresh "quantityCancelled: 2" entirely; one of three identical cancels silently
did nothing until this was understood. `quantityOrdered` is authoritative: a full cancellation is
`quantityOrdered: 0` + `cancelInd: "Y"` + `cancelCode`, which zeroes the line regardless of its
history. Cancel reasons come from code type `ORCA`: `B` for reductions, `S` for switches.

The step verifies by read-back — every named line at its quantity AND every cancelled line at
zero — waiting out the ~30-second lag with the order-verify retry settings.

## Item UDAs, proven — live, 2026-09-01

Written against style `100150111` and SKU `100150129` on STG, using values taken from the tenant's own
`foundation/uda` feed. Both persisted.

`displayType` is required per row and decides which value field is read: `LV` uses `udaValue`, `FF`
uses `udaText`, `DT` uses `udaDate`. The empty array the mapper currently sends is accepted and does
nothing.

```jsonc
// POST /MerchIntegrations/services/item/uda/create   ->  {"status":"SUCCESS"}
{
  "collectionSize": 2,
  "items": [
    {
      "item": "100150111",
      "dataLoadingDestination": "RMS",
      "uda": [
        // udaId 239 = Gender, value 3. Definitions and their valid values come from
        // GET /MerchIntegrations/services/foundation/uda - 23 on STG, 27 on UAT.
        { "udaId": 239,   "displayType": "LV", "udaValue": "3" },
        { "udaId": 51037, "displayType": "LV", "udaValue": "1" },
        { "udaId": 225,   "displayType": "LV", "udaValue": "5" }
      ]
    },
    { "item": "100150129", "dataLoadingDestination": "RMS", "uda": [ /* same three */ ] }
  ]
}
```

The read-back needs care. `foundation/item/100150111` showed `itemUda.udaLov` empty immediately after
the write and populated about a minute later, when the document's own `cacheTimestamp` advanced. That
is cache lag, not a silent failure — see the note in CLAUDE.md.

`item/uda/update` is **not** symmetric with create: it matches the existing row on its current value and
carries the change in `newUdaValue` / `newUdaText` / `newUdaDate`.

## Barcodes as level-3 items, proven — live, 2026-09-01

There is no reference-item service anywhere in the tenant's 323 paths. A barcode is an item at level 3
hanging off the SKU, created through `items/create`, the same endpoint used for styles and SKUs.

```jsonc
// POST /MerchIntegrations/services/items/create   ->  {"status":"SUCCESS"}
{
  "collectionSize": 1,
  "items": [
    {
      "item": "2930000003016",          // EAN-13. Prefix 29 is the GS1 restricted range.
      "itemParent": "100150129",        // the SKU
      "itemGrandparent": "100150111",   // the style
      "itemLevel": 3,
      "tranLevel": 2,

      // EAN13 is the only type that accepts 13 digits. ITEM and an absent type both
      // demand 9 characters; UPC-A demands 12.
      "itemNumberType": "EAN13",
      "primaryReferenceItemInd": "Y",

      "dataLoadingDestination": "RMS",
      "itemDescription": "Flow barcode test",
      "shortDescription": "Flow barcode",
      "dept": 1517,
      "class": 6892,
      "subclass": 1128,
      "diff1": "08621",
      "diff2": "070",
      "sellableInd": "Y",
      "orderableInd": "Y",
      "merchandiseInd": "Y",
      "inventoryInd": "Y",
      "standardUom": "EA",

      // Must be sent, and must equal the parent's. Omitting it returns
      // "Field cannot be modified. Field: COST_ZONE_GROUP_ID" - an error naming a
      // field that was never in the request. This was the whole blocker.
      "costZoneGroupId": 2000
    }
  ]
}
```

`status` and `itemSupplier` are inherited from the parent and should not be sent — the record came back
`status: "A"` with the parent's supplier attached, having been sent neither.

Errors along the way were loud and useful, which is unusual for this tenant:

| sent | response |
| --- | --- |
| no `itemNumberType` | `The Item number must be 9 characters in length` |
| `UPC-A` | `The UCC12 must be 12 characters in length` |
| `EAN13`, no `costZoneGroupId` | `Field cannot be modified. Field: COST_ZONE_GROUP_ID` |
| missing `shortDescription` | `Field must be entered. Field: SHORT_DESC` |
| missing hierarchy | `Field must be entered. Field: SUBCLASS` |
| no `sellableInd`/`orderableInd` | `Regular items must be either orderable or sellable` |

Reading it back, in two places — `foundation/item/2930000003016` 404s, on both tenants:

```jsonc
// GET /RmsReSTServices/services/private/Item/itemDetail?item=100150111
{ "item": "2930000003016", "itemParent": "100150129", "itemGrandparent": "100150111",
  "itemLevel": 3, "primaryRefItemInd": "Y", "status": "A" }

// GET /MerchIntegrations/services/foundation/item/100150129  ->  referenceItem[]
{ "referenceItem": "2930000003016", "primaryInd": "Y", "itemNoType": "EAN13",
  "formatId": null, "prefix": null }
```

Note the renames across the three vocabularies: `itemNumberType` on write, `itemNoType` in
`referenceItem`; `primaryReferenceItemInd` on write, `primaryRefItemInd` in `itemDetail`, `primaryInd`
in `referenceItem`. Three names for one flag.

A real UAT SKU carries two barcodes, exactly one with `primaryInd: "Y"`, and the non-primary one is
type `MANL` rather than `EAN13`.

## CREATE_STYLE with UDAs and barcodes, end to end — live, 2026-09-01

Request `LIVE-UPC-184508` on STG. Completed, eleven steps, style `100150161` with SKUs `100150170` and
`100150188` and three barcodes.

The document deliberately used the **legacy** `PLMSizeCurveDtl` key, to prove intake normalisation on a
real request rather than only in a test. The response came back naming `SIZE_CURVE_DETAIL`.

```jsonc
{
  "OPERATION_NAME": "CREATE_STYLE",
  "BRAND": "02",
  "STYLE_UDAS": [
    { "UDA_ID": 239,   "UDA_VALUE": "11" },   // Gender = Boy
    { "UDA_ID": 51037, "UDA_VALUE": "1"  }    // Fit = Regular
  ],
  "PLMSizeCurveDtl": [                        // accepted; stored as SIZE_CURVE_DETAIL
    { "SOURCE_VARIANT_REF": "...-7", "SKU_SIZE": "7", "SKU_QTY": 1,
      "SKU_UPCS": [ { "UPC": "2900184508010", "PRIMARY_YN": "Y" },
                    { "UPC": "2900184508027", "PRIMARY_YN": "N" } ] },
    { "SOURCE_VARIANT_REF": "...-8", "SKU_SIZE": "8", "SKU_QTY": 1,
      "SKU_UPCS": [ { "UPC": "2900184508034", "PRIMARY_YN": "Y" } ] }
  ]
}
```

Read back through `itemDetail`, six rows:

```
level 1  100150161
level 2  100150170                     level 2  100150188
level 3  2900184508010  primaryRef Y   level 3  2900184508034  primaryRef Y
level 3  2900184508027  primaryRef N
```

and through `foundation/item`, `itemUda.udaLov` carrying `239 = Boy` and `51037 = Regular`.

### The ordering this cost

The first attempt placed `CREATE_REFERENCE_ITEMS` at sequence 45, straight after the children were
created, which is where it looks like it belongs. It failed:

```json
{ "status": "ERROR",
  "message": "This item was not submitted successfully.ITEM: 2900184340016 ... This item's parent must
              be in submitted status before the item can be submitted.." }
```

A level-3 item is refused while its parent SKU is still in worksheet status. The step moved to 85, after
`APPROVE_ITEMS`, and the identical payload succeeded. The earlier manual proof had worked only because
it targeted a SKU that was already approved.

### Brand did not stick

`"brandName": "02"` was sent on the parent create - the stored attempt payload confirms it - and the
style reads back with `brandName` empty, while UDAs written in the same run are present. SUCCESS, and
nothing happened. `items/update` as a second attempt returned `The record is currently locked by
another user`, which is transient post-approval locking rather than an answer.

## Current Assumptions

These values are configurable and should be replaced with authoritative Office/MFCS foundation mappings when available:

| Config key | Current value | Why |
| --- | --- | --- |
| `MFCS_COST_ZONE_GROUP_ID` | `2000` | Observed on known-good foundation item `11743`. |
| `MFCS_PARENT_DIFF1_GROUP` | `RMS_ALL_C` | Parent style colour group observed on item `11743`. |
| `MFCS_PARENT_DIFF2_GROUP` | `ALL` | Parent style size group observed on item `11743`. |
| `MAP.COLOUR.08610` | `08610` | Concrete child colour diff ID observed from known-good SKU children. |
| `MAP.SIZE.7` | `070` | Tenant size diff ID for display size `7`. |
| `MAP.SIZE.8` | `080` | Tenant size diff ID for display size `8`. |
| `MFCS_DEFAULT_UOP` | `EA` | Required for sourcing. |
| `MFCS_COST_UOM` | `EA` | Required for sourcing. |
| `MFCS_SUPPLIER_PACK_SIZE` | `1` | Required for sourcing. |
| `MFCS_INNER_PACK_SIZE` | `1` | Required for sourcing. |
| `MFCS_PURCHASE_TYPE` | `0` | Observed on supplied known-good SKU and required by MFCS. |
| `MFCS_STORE_ORDER_MULTIPLE` | `E` | Required by item approval validation. |
| `MFCS_MANUFACTURER_COUNTRY` | `VN` | Observed on supplied known-good SKU and required by item approval validation. |
| `FEATURE_ITEM_LOCATIONS_YN` | `N` | No valid location hierarchy value has been confirmed yet. |
| `FEATURE_INITIAL_RETAIL_YN` | `N` | Initial retail endpoint is still a placeholder, so actual `CREATE_ALL` skips it. |
| `MFCS_ORDER_TYPE` | `N/B` | Matches the working order sample and live create. |
| `MFCS_ORDER_STATUS` | `A` | Creates approved purchase orders in the dev tenant. |
| `MFCS_ORDER_ORIGIN` | `2` | Matches the working order sample and live create. |
| `MFCS_ORDER_DEFAULT_TERMS` | `34` | Used when Office does not send `TERMS`. |
| `MFCS_ORDER_LOCATION_TYPE` | `W` | Purchase order currently targets warehouse location. |
| `MFCS_ORDER_DEFAULT_LOCATION` | `19271` | Default MFCS virtual warehouse. |
| `MAP.ORDER_LOCATION.1927` | `19271` | Maps Office physical delivery location to MFCS virtual warehouse. |
| `MFCS_ORDER_VERIFY_RETRY_COUNT` | `12` | Allows for delayed visibility after successful PO create. |
| `MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS` | `10` | Sleep between procurement GET verification attempts. |
| `FEATURE_GENERATE_MISSING_SKUS_YN` | `Y` | Creates the children a style lacks instead of stopping the request. |
| `MFCS_SKU_VERIFY_RETRY_COUNT` | `6` | Newly approved children take a moment to read back. |
| `MFCS_SKU_VERIFY_RETRY_SLEEP_SECONDS` | `5` | Sleep between read-backs after creating children. |
| `MFCS_DIRECT_SHIP_IND` | `N` | Required by `suppliers/update`; observed as `N` on every item in the tenant. |
| `MFCS_INNER_NAME` | `EA` | Required by `suppliers/update`; value from tenant code type `INRN`. |
| `MFCS_CASE_NAME` | `CS` | Value from tenant code type `CASN`. |
| `MFCS_PALLET_NAME` | `PAL` | Value from tenant code type `PALN`. |
| `MFCS_ORDER_CANCEL_CODE` | `S` | ORCA "Colour/Location Switched" — full-line cancellation on a colour switch. |
| `MFCS_ORDER_REDUCE_CANCEL_CODE` | `B` | ORCA "Buyer Cancelled" — reason attached to a quantity reduction. |
| `MFCS_ORDER_LINE_ABSENT_ACTION` | `CANCEL` | A line of this style absent from the document is cancelled; set `LEAVE` to keep it. |

## Logging Tables

For every request, inspect:

```sql
select *
  from request
 where action_request_id = :action_request_id;

select *
  from step
 where action_request_id = :action_request_id
 order by step_sequence;

select *
  from attempt
 where action_request_id = :action_request_id
 order by attempt_id;

select *
  from event_log
 where action_request_id = :action_request_id
 order by event_id;
```

`ATTEMPT` contains the outbound request payload, HTTP status, response payload, endpoint, method, attempt number, and correlation ID. `EVENT_LOG` is autonomous and records progress even when a downstream step fails.

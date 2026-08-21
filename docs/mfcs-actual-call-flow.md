# Actual MFCS Call Flow

This document captures the current live integration path from the Office-facing payload into the actual MFCS dev tenant.

The style examples below come from successful smoke request `DAYALAN-TEST-20260817164337108`, which completed on 2026-08-17 and created:

- Parent style item `100000180`
- Child SKU items `100000198` and `100000201`

JSON examples are shown as `jsonc` so assumptions can be documented inline. The integration sends strict JSON to MFCS; comments are documentation only.

## Runtime Mode

The current deployed route is:

- `MFCS_CLIENT_MODE = ACTUAL_MFCS`
- `MFCS_AUTH_MODE = STATIC_BEARER`
- `MFCS_BASE_URL = https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs`
- Bearer token stored externally in `OFFICE_MFCS_SECRET` under config ref `MFCS_BEARER_TOKEN_REF`
- Item locations disabled by default with `FEATURE_ITEM_LOCATIONS_YN = N`
- Initial retail disabled by default with `FEATURE_INITIAL_RETAIL_YN = N`
- Purchase-order verification retry enabled with `MFCS_ORDER_VERIFY_RETRY_COUNT = 12` and `MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS = 10`

Item locations are disabled because the item-location create schema is now known, but the dev tenant has not yet exposed a valid store/warehouse/chain hierarchy value via the tested foundation APIs. Once the correct hierarchy value is known, set `FEATURE_ITEM_LOCATIONS_YN = Y` and configure:

- `MFCS_LOCATION_HIERARCHY_LEVEL`
- `MFCS_LOCATION_HIERARCHY_VALUE`
- `MFCS_STORE_ORDER_MULTIPLE`
- `MFCS_TAXABLE_IND`

## Integration Payload Received

The integration layer receives the PLM/Office-style request through `office_mfcs_api_pkg.submit_transaction` or `POST /office-mfcs/v1/transactions`.

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
  "PLMSizeCurveDtl": [
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

The configured reservation chunk size is `1`, so the integration calls MFCS once for the parent and once per child SKU. The response is persisted to `OFFICE_MFCS_ENTITY_MAP`.

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
  "PLMSizeCurveDtl": [
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

The order number is reserved before the purchase-order create call, then stored in `OFFICE_MFCS_ENTITY_MAP`.

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

## Logging Tables

For every request, inspect:

```sql
select *
  from office_mfcs_request
 where action_request_id = :action_request_id;

select *
  from office_mfcs_step
 where action_request_id = :action_request_id
 order by step_sequence;

select *
  from office_mfcs_attempt
 where action_request_id = :action_request_id
 order by attempt_id;

select *
  from office_mfcs_event_log
 where action_request_id = :action_request_id
 order by event_id;
```

`OFFICE_MFCS_ATTEMPT` contains the outbound request payload, HTTP status, response payload, endpoint, method, attempt number, and correlation ID. `OFFICE_MFCS_EVENT_LOG` is autonomous and records progress even when a downstream step fails.

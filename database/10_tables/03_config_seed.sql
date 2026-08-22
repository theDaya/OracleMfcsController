set define off

-- This integration always talks to the real MFCS tenant. There is no client-mode
-- switch: the simulators and MOCK/PUBLIC_MOCK/LOCAL_MFCS modes were removed.
prompt Seeding OFFICE MFCS non-secret configuration

merge into config c
using (
    select 'DEFAULT' environment, 'MFCS_AUTH_MODE' config_key, 'STATIC_BEARER' config_value, 'Y' enabled_ind from dual union all
    select 'DEFAULT', 'MFCS_BASE_URL', 'https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_TOKEN_URL', 'https://idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com/oauth2/v1/token', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_CLIENT_ID', 'replace-with-client-id', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_SCOPE', 'urn:opc:idm:__myscopes__', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_CLIENT_SECRET_REF', 'replace-with-rds-secret-reference', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ITEM_NUMBER_RESERVATION_CHUNK_SIZE', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ITEM_NUMBER_RESERVATION_DAYS_UNTIL_EXPIRY', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_COST_ZONE_GROUP_ID', '2000', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_DEFAULT_UOP', 'EA', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_COST_UOM', 'EA', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_SUPPLIER_PACK_SIZE', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_INNER_PACK_SIZE', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_PURCHASE_TYPE', '0', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_MANUFACTURER_COUNTRY', 'VN', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_LOCATION_HIERARCHY_LEVEL', 'CH', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_LOCATION_HIERARCHY_VALUE', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_STORE_ORDER_MULTIPLE', 'E', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_TAXABLE_IND', 'Y', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_PARENT_DIFF1_GROUP', 'RMS_ALL_C', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_PARENT_DIFF2_GROUP', 'ALL', 'Y' from dual union all
    select 'DEFAULT', 'INTERNAL_TIME_BUDGET_SECONDS', '240', 'Y' from dual union all
    select 'DEFAULT', 'HTTP_TRANSFER_TIMEOUT_SECONDS', '45', 'Y' from dual union all
    select 'DEFAULT', 'FEATURE_INITIAL_RETAIL_YN', 'N', 'Y' from dual union all
    select 'DEFAULT', 'FEATURE_ITEM_LOCATIONS_YN', 'N', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_RESERVATION_DAYS_UNTIL_EXPIRY', '1', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_OTB_EOW_DAY', 'SUNDAY', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_TYPE', 'N/B', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_STATUS', 'A', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_ORIGIN', '2', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_INCLUDE_ON_ORDER_IND', 'Y', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_EDI_PO_IND', 'N', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_PRE_MARK_IND', 'N', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_QUALITY_CONTROL_IND', 'N', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_FREIGHT_TERMS', 'PREPAID', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_LOCATION_TYPE', 'W', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_DEFAULT_LOCATION', '19271', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_DEFAULT_TERMS', '34', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_DEFAULT_IMPORT_COUNTRY', 'GB', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_VERIFY_RETRY_COUNT', '12', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS', '10', 'Y' from dual union all
    select 'DEFAULT', 'BATCH_WINDOW_ACTIVE_YN', 'N', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_NUMBERS_MANAGE', '/MerchIntegrations/services/item/itemNumbers/reserve', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEMS_CREATE', '/MerchIntegrations/services/items/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEMS_UPDATE', '/MerchIntegrations/services/items/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_LOCATIONS_CREATE', '/MerchIntegrations/services/item/locations/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_SOURCING_CREATE', '/MerchIntegrations/services/item/suppliers/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_SOURCING_UPDATE', '/MerchIntegrations/services/item/suppliers/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_COUNTRIES_OF_MANUFACTURE_CREATE', '/MerchIntegrations/services/item/supplier/countriesOfManufacture/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_UDAS_CREATE', '/MerchIntegrations/services/item/uda/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_UDAS_UPDATE', '/MerchIntegrations/services/item/uda/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_LOCATIONS_UPDATE', '/MerchIntegrations/services/item/locations/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_APPROVE', '/MerchIntegrations/services/items/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.INITIAL_RETAIL', '/MerchIntegrations/services/TODO-from-office-openapi/item/initialRetail/apply', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.PO_PREISSUED_CREATE', '/MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.PURCHASE_ORDERS_CREATE', '/MerchIntegrations/services/purchaseOrders/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.PURCHASE_ORDERS_UPDATE', '/MerchIntegrations/services/purchaseOrders/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.PURCHASE_ORDER_GET', '/MerchIntegrations/services/procurement/order/{orderNo}', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.REST_SERVICE_STATUS', '/MerchIntegrations/services/administration/operations/restService/status', 'Y' from dual union all
    select 'DEFAULT', 'MAP.DEPARTMENT.100', '100', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CLASS.100.10', '10', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SUBCLASS.100.10.1', '1', 'Y' from dual union all
    select 'DEFAULT', 'MAP.DEPARTMENT.1517', '1517', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CLASS.1517.6892', '6892', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SUBCLASS.1517.6892.1128', '1128', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SUPPLIER.70001', '70001', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SUPPLIER.700087', '700087', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COUNTRY.ZA', 'ZA', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COUNTRY.CN', 'CN', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COUNTRY.GB', 'GB', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CURRENCY.ZAR', 'ZAR', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CURRENCY.USD', 'USD', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.BLACK', 'BLACK', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.WHITE', 'WHITE', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.RMS_ALL_C', 'RMS_ALL_C', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.08610', '08610', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.08621', '08621', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.7', '070', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.8', '080', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.9', '090', 'Y' from dual union all
    select 'DEFAULT', 'MAP.ORDER_LOCATION.1927', '19271', 'Y' from dual union all
    select 'DEFAULT', 'MAP.WIDTH.ALL', 'ALL', 'Y' from dual union all
    select 'DEFAULT', 'MAP.WIDTH.STANDARD', 'STANDARD', 'Y' from dual
) s
on (c.environment = s.environment and c.config_key = s.config_key)
when matched then update set
    c.config_value = s.config_value,
    c.enabled_ind = s.enabled_ind,
    c.updated_at = systimestamp
when not matched then insert (
    environment,
    config_key,
    config_value,
    enabled_ind
) values (
    s.environment,
    s.config_key,
    s.config_value,
    s.enabled_ind
);

delete from config
 where config_key in ('MFCS_CLIENT_MODE', 'MFCS_SCHEMA_READY_YN')
    or config_key like 'MOCK_%';

commit;

prompt OFFICE MFCS configuration seeded

set define off

prompt Seeding OFFICE MFCS non-secret configuration

merge into office_mfcs_config c
using (
    select 'DEFAULT' environment, 'MFCS_CLIENT_MODE' config_key, 'MOCK' config_value, 'Y' enabled_ind from dual union all
    select 'DEFAULT', 'MFCS_BASE_URL', 'https://office-hostname/namespace', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_TOKEN_URL', 'https://office-hostname/oauth2/v1/token', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_CLIENT_ID', 'replace-with-client-id', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_SCOPE', 'urn:opc:idm:__myscopes__', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_CLIENT_SECRET_REF', 'replace-with-rds-secret-reference', 'Y' from dual union all
    select 'DEFAULT', 'INTERNAL_TIME_BUDGET_SECONDS', '240', 'Y' from dual union all
    select 'DEFAULT', 'HTTP_TRANSFER_TIMEOUT_SECONDS', '45', 'Y' from dual union all
    select 'DEFAULT', 'MFCS_SCHEMA_READY_YN', 'N', 'Y' from dual union all
    select 'DEFAULT', 'FEATURE_INITIAL_RETAIL_YN', 'Y', 'Y' from dual union all
    select 'DEFAULT', 'BATCH_WINDOW_ACTIVE_YN', 'N', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_NUMBERS_MANAGE', '/MerchIntegrations/services/item/itemNumbers/reserve', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEMS_CREATE', '/MerchIntegrations/services/items/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEMS_UPDATE', '/MerchIntegrations/services/items/update', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_LOCATIONS_CREATE', '/MerchIntegrations/services/item/locations/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_SOURCING_CREATE', '/MerchIntegrations/services/item/suppliers/create', 'Y' from dual union all
    select 'DEFAULT', 'ENDPOINT.ITEM_SOURCING_UPDATE', '/MerchIntegrations/services/item/suppliers/update', 'Y' from dual union all
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
    select 'DEFAULT', 'MAP.SUPPLIER.70001', '70001', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COUNTRY.ZA', 'ZA', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COUNTRY.CN', 'CN', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CURRENCY.ZAR', 'ZAR', 'Y' from dual union all
    select 'DEFAULT', 'MAP.CURRENCY.USD', 'USD', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.BLACK', 'BLACK', 'Y' from dual union all
    select 'DEFAULT', 'MAP.COLOUR.WHITE', 'WHITE', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.7', '7', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.8', '8', 'Y' from dual union all
    select 'DEFAULT', 'MAP.SIZE.9', '9', 'Y' from dual union all
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

commit;

prompt OFFICE MFCS configuration seeded

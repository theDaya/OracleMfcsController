set define off
set serveroutput on size unlimited

prompt Running OFFICE MFCS public-contract HTTPS end-to-end test

declare
    l_old_mode varchar2(4000);
    l_old_base_url varchar2(4000);
    l_old_token_url varchar2(4000);
    l_old_client_id varchar2(4000);
    l_old_scope varchar2(4000);
    l_old_secret_ref varchar2(4000);
    l_old_wallet_path varchar2(4000);
    l_old_wallet_secret_ref varchar2(4000);
    l_old_retail varchar2(4000);
    l_payload clob := q'~{
  "ACTION_REQUEST_ID": "E2E-PUBLIC-CREATE-ALL",
  "OPERATION_NAME": "CREATE_ALL",
  "SOURCE_SYSTEM": "OFFICE",
  "SOURCE_STYLE_REF": "PUBLIC-CONTRACT-STYLE-001",
  "SOURCE_ORDER_REF": "PUBLIC-CONTRACT-ORDER-001",
  "SOURCE_VERSION": "1",
  "USER_ID": "public.contract@example.com",
  "DATE_TIME_STAMP": "2026-08-16T20:00:00Z",
  "STYLE": null,
  "ORDER_NO": null,
  "DEPARTMENT": 100,
  "CLASS": 10,
  "SUBCLASS": 1,
  "SUPPLIER": 70001,
  "ORIGIN_COUNTRY": "CN",
  "CURRENCY_CODE": "USD",
  "COLOUR": "BLACK",
  "UNIT_COST": 22.75,
  "RETAIL_PRICE": 69.99,
  "PLMSizeCurveDtl": [
    {"SOURCE_VARIANT_REF": "PUBLIC-CONTRACT-STYLE-001-UK7", "SKU_SIZE": "7", "SKU_WIDTH": "STANDARD", "SKU_QTY": 120, "SKU_ID": null},
    {"SOURCE_VARIANT_REF": "PUBLIC-CONTRACT-STYLE-001-UK8", "SKU_SIZE": "8", "SKU_WIDTH": "STANDARD", "SKU_QTY": 150, "SKU_ID": null}
  ],
  "NOT_BEFORE_DATE": "2026-10-12",
  "NOT_AFTER_DATE": "2026-10-18",
  "EARLIEST_SHIP_DATE": "2026-08-16",
  "LATEST_SHIP_DATE": "2026-08-30",
  "DELIVERY_LOC": 98,
  "PO_TYPE": "2",
  "ORDER_EXCHANGE_RATE": 1
}~';
    l_response clob;
    l_http number;
    l_count number;
    l_status varchar2(30);
    l_style varchar2(30);
    l_order varchar2(30);

    procedure assert_true(p_condition in boolean, p_message in varchar2) is
    begin
        if not p_condition then
            raise_application_error(-20010, 'PUBLIC CONTRACT ASSERTION FAILED: ' || p_message);
        end if;
    end;

    procedure set_cfg(p_key in varchar2, p_value in varchar2) is
    begin
        update office_mfcs_config
           set config_value = p_value,
               enabled_ind = 'Y',
               updated_at = systimestamp
         where environment = 'DEFAULT'
           and config_key = p_key;
        if sql%rowcount = 0 then
            insert into office_mfcs_config(environment, config_key, config_value, enabled_ind)
            values ('DEFAULT', p_key, p_value, 'Y');
        end if;
    end;

    procedure restore_config is
    begin
        set_cfg('MFCS_CLIENT_MODE', l_old_mode);
        set_cfg('MFCS_BASE_URL', l_old_base_url);
        set_cfg('MFCS_TOKEN_URL', l_old_token_url);
        set_cfg('MFCS_CLIENT_ID', l_old_client_id);
        set_cfg('MFCS_SCOPE', l_old_scope);
        set_cfg('MFCS_CLIENT_SECRET_REF', l_old_secret_ref);
        set_cfg('MFCS_WALLET_PATH', l_old_wallet_path);
        set_cfg('MFCS_WALLET_PASSWORD_REF', l_old_wallet_secret_ref);
        set_cfg('FEATURE_INITIAL_RETAIL_YN', l_old_retail);
        commit;
    end;
begin
    l_old_mode := office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE');
    l_old_base_url := office_mfcs_request_pkg.get_config('MFCS_BASE_URL');
    l_old_token_url := office_mfcs_request_pkg.get_config('MFCS_TOKEN_URL');
    l_old_client_id := office_mfcs_request_pkg.get_config('MFCS_CLIENT_ID');
    l_old_scope := office_mfcs_request_pkg.get_config('MFCS_SCOPE');
    l_old_secret_ref := office_mfcs_request_pkg.get_config('MFCS_CLIENT_SECRET_REF');
    l_old_wallet_path := office_mfcs_request_pkg.get_config('MFCS_WALLET_PATH', null);
    l_old_wallet_secret_ref := office_mfcs_request_pkg.get_config('MFCS_WALLET_PASSWORD_REF', null);
    l_old_retail := office_mfcs_request_pkg.get_config('FEATURE_INITIAL_RETAIL_YN');

    delete from office_mfcs_attempt where action_request_id = 'E2E-PUBLIC-CREATE-ALL';
    delete from office_mfcs_step where action_request_id = 'E2E-PUBLIC-CREATE-ALL';
    delete from office_mfcs_request where action_request_id = 'E2E-PUBLIC-CREATE-ALL';
    delete from office_mfcs_entity_map
     where source_style_ref = 'PUBLIC-CONTRACT-STYLE-001'
        or source_order_ref = 'PUBLIC-CONTRACT-ORDER-001';

    set_cfg('MFCS_CLIENT_MODE', 'PUBLIC_MOCK');
    set_cfg('MFCS_BASE_URL', 'https://host.docker.internal:18443');
    set_cfg('MFCS_TOKEN_URL', 'https://host.docker.internal:18443/oauth2/v1/token');
    set_cfg('MFCS_CLIENT_ID', 'office-mfcs-public-contract-client');
    set_cfg('MFCS_SCOPE', 'public-contract');
    set_cfg('MFCS_CLIENT_SECRET_REF', 'public-mock-secret-ref');
    set_cfg('MFCS_WALLET_PATH', 'DIR:MFCS_MOCK_WALLET_DIR');
    set_cfg('MFCS_WALLET_PASSWORD_REF', 'public-mock-wallet-secret-ref');
    set_cfg('FEATURE_INITIAL_RETAIL_YN', 'N');
    commit;

    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    dbms_output.put_line('HTTP=' || l_http || ' RESPONSE=' || dbms_lob.substr(l_response, 1000, 1));

    select json_value(l_response, '$.STATUS' returning varchar2(30)),
           json_value(l_response, '$.STYLE' returning varchar2(30)),
           json_value(l_response, '$.ORDER_NO' returning varchar2(30))
      into l_status, l_style, l_order
      from dual;

    assert_true(l_http = 200, 'CREATE_ALL returns HTTP 200');
    assert_true(l_status = 'COMPLETED', 'request completes');
    assert_true(l_style is not null, 'generated style is returned');
    assert_true(l_order is not null, 'generated order is returned');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and attempt_status = 'SUCCEEDED'
       and http_status = 200;
    assert_true(l_count = 9, 'all nine documented HTTP steps succeeded');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and endpoint like '%TODO%';
    assert_true(l_count = 0, 'no TODO endpoint was called');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and step_code = 'RESERVE_ITEM_NUMBERS'
       and json_value(request_payload, '$.itemNumberType' returning varchar2(6)) = 'ITEM'
       and json_value(request_payload, '$.quantity' returning number) = 3
       and json_value(response_payload, '$.items[0].item' returning varchar2(30)) is not null;
    assert_true(l_count = 1, 'item reservation uses documented request and response shapes');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and step_code = 'CREATE_ITEM_HIERARCHY'
       and json_value(request_payload, '$.collectionSize' returning number) = 3
       and json_value(request_payload, '$.items[0].dataLoadingDestination' returning varchar2(6)) = 'RMS';
    assert_true(l_count = 1, 'item creation uses direct RMS collection envelope');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and step_code = 'RESERVE_ORDER_NUMBER'
       and json_value(request_payload, '$.quantity' returning number) = 1
       and json_value(response_payload, '$.orderNumbers[0].orderNo' returning number) is not null;
    assert_true(l_count = 1, 'PO reservation uses documented nested orderNumbers response');

    select count(*) into l_count
      from office_mfcs_attempt
     where action_request_id = 'E2E-PUBLIC-CREATE-ALL'
       and step_code = 'CREATE_PURCHASE_ORDER'
       and json_value(request_payload, '$.items[0].dataLoadingDestination' returning varchar2(6)) = 'RMS'
       and json_value(request_payload, '$.items[0].details[0].item' returning varchar2(30)) is not null;
    assert_true(l_count = 1, 'PO creation uses nested RMS order and detail payload');

    restore_config;
    dbms_output.put_line('OFFICE MFCS public-contract HTTP end-to-end test passed');
exception
    when others then
        restore_config;
        raise;
end;
/

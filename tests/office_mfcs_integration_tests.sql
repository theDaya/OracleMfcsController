set define off
set serveroutput on size unlimited

prompt Running OFFICE MFCS integration tests

declare
    g_passed number := 0;
    l_payload clob;
    l_changed clob;
    l_response clob;
    l_http number;
    l_count number;

    procedure assert_true(p_condition in boolean, p_message in varchar2) is
    begin
        if not p_condition then
            raise_application_error(-20000, 'ASSERTION FAILED: ' || p_message);
        end if;
        g_passed := g_passed + 1;
    end;

    procedure assert_eq(p_actual in varchar2, p_expected in varchar2, p_message in varchar2) is
    begin
        assert_true(nvl(p_actual, '<NULL>') = nvl(p_expected, '<NULL>'), p_message || ' expected=' || p_expected || ' actual=' || p_actual);
    end;

    procedure assert_num_eq(p_actual in number, p_expected in number, p_message in varchar2) is
    begin
        assert_true(nvl(p_actual, -999999) = nvl(p_expected, -999999), p_message || ' expected=' || p_expected || ' actual=' || p_actual);
    end;

    procedure set_cfg(p_key in varchar2, p_value in varchar2) is
    begin
        merge into office_mfcs_config c
        using (select 'DEFAULT' environment, p_key config_key, p_value config_value from dual) s
        on (c.environment = s.environment and c.config_key = s.config_key)
        when matched then update set c.config_value = s.config_value, c.enabled_ind = 'Y', c.updated_at = systimestamp
        when not matched then insert (environment, config_key, config_value, enabled_ind)
            values (s.environment, s.config_key, s.config_value, 'Y');
    end;

    procedure clear_mock is
    begin
        delete from office_mfcs_config
         where environment = 'DEFAULT'
           and (config_key like 'MOCK_%' or config_key in ('BATCH_WINDOW_ACTIVE_YN'));

        set_cfg('MFCS_CLIENT_MODE', 'MOCK');
        set_cfg('BATCH_WINDOW_ACTIVE_YN', 'N');
        commit;
    end;

    procedure clear_test_data is
    begin
        delete from office_mfcs_attempt where action_request_id like 'T-%';
        delete from office_mfcs_step where action_request_id like 'T-%';
        delete from office_mfcs_request where action_request_id like 'T-%';
        delete from office_mfcs_entity_map where source_style_ref like 'OFF-STYLE-T-%' or source_order_ref like 'OFF-ORDER-T-%';
        commit;
    end;

    function payload(p_id in varchar2) return clob is
        l_payload clob := q'~{
  "ACTION_REQUEST_ID": "T-ID",
  "OPERATION_NAME": "CREATE_ALL",
  "SOURCE_SYSTEM": "OFFICE",
  "SOURCE_STYLE_REF": "OFF-STYLE-T-ID",
  "SOURCE_ORDER_REF": "OFF-ORDER-T-ID",
  "SOURCE_VERSION": "1",
  "USER_ID": "office.buyer@example.com",
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
    {"SOURCE_VARIANT_REF": "OFF-STYLE-T-ID-UK7", "SKU_SIZE": "7", "SKU_WIDTH": "STANDARD", "SKU_QTY": 120, "SKU_ID": null},
    {"SOURCE_VARIANT_REF": "OFF-STYLE-T-ID-UK8", "SKU_SIZE": "8", "SKU_WIDTH": "STANDARD", "SKU_QTY": 150, "SKU_ID": null}
  ],
  "NOT_BEFORE_DATE": "2026-10-12",
  "NOT_AFTER_DATE": "2026-10-18",
  "EARLIEST_SHIP_DATE": "2026-08-16",
  "LATEST_SHIP_DATE": "2026-08-30",
  "DELIVERY_LOC": 98,
  "PO_TYPE": "2",
  "ORDER_EXCHANGE_RATE": 1
}~';
    begin
        return replace(l_payload, 'T-ID', p_id);
    end;

    function jv(p_json in clob, p_path in varchar2) return varchar2 is
        l_value varchar2(4000);
    begin
        execute immediate
            'select json_value(:payload, ''' || replace(p_path, '''', '''''') || ''' returning varchar2(4000) null on error) from dual'
            into l_value
            using p_json;
        return l_value;
    end;

    function attempts_for(p_id in varchar2, p_step in varchar2) return number is
        l_count number;
    begin
        select count(*)
          into l_count
          from office_mfcs_attempt
         where action_request_id = p_id
           and step_code = p_step;
        return l_count;
    end;

    procedure submit(p_payload in clob, p_http out number, p_response out clob) is
    begin
        office_mfcs_api_pkg.submit_transaction(p_payload, p_http, p_response);
        dbms_output.put_line('HTTP ' || p_http || ' ' || substr(p_response, 1, 240));
    end;

begin
    clear_test_data;
    clear_mock;

    -- 1. Successful CREATE_ALL.
    l_payload := payload('T-SUCCESS');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'Successful CREATE_ALL returns 200');
    assert_eq(jv(l_response, '$.STATUS'), 'COMPLETED', 'Successful CREATE_ALL completed');
    assert_true(jv(l_response, '$.STYLE') is not null, 'Generated style returned');
    assert_true(jv(l_response, '$.ORDER_NO') is not null, 'Generated order returned');

    -- 2. Validation failure before side effects.
    l_payload := replace(payload('T-VALIDATION'), '"ORDER_NO": null', '"ORDER_NO": 10740001');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 422, 'Validation failure returns 422');
    assert_eq(jv(l_response, '$.STATUS'), 'FAILED_NO_SIDE_EFFECT', 'Validation failure has no side effect status');
    assert_num_eq(attempts_for('T-VALIDATION', 'RESERVE_ITEM_NUMBERS'), 0, 'Validation failure made no MFCS attempts');

    -- 3. Style/SKUs succeed and PO creation fails, then retry resumes.
    clear_mock;
    set_cfg('MOCK_FAIL_STEP', 'CREATE_PURCHASE_ORDER');
    l_payload := payload('T-PO-FAIL');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 502, 'PO creation failure returns downstream failure');
    assert_eq(jv(l_response, '$.STATUS'), 'PARTIALLY_COMPLETED', 'PO creation failure leaves partial request');
    assert_true(jv(l_response, '$.STYLE') is not null, 'Partial response keeps style');
    assert_true(jv(l_response, '$.ORDER_NO') is not null, 'Partial response keeps reserved PO number');
    assert_num_eq(attempts_for('T-PO-FAIL', 'RESERVE_ITEM_NUMBERS'), 1, 'Item reservation called once before resume');
    clear_mock;
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'PO failure retry completes');
    assert_num_eq(attempts_for('T-PO-FAIL', 'RESERVE_ITEM_NUMBERS'), 1, 'Resume did not recreate style/SKUs');

    -- 4. Item-number reservation succeeds and item creation fails.
    clear_mock;
    set_cfg('MOCK_FAIL_STEP', 'CREATE_ITEM_HIERARCHY');
    l_payload := payload('T-ITEM-CREATE-FAIL');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 502, 'Item creation failure returns 502');
    assert_eq(jv(l_response, '$.STATUS'), 'PARTIALLY_COMPLETED', 'Item creation failure leaves partial request');
    assert_true(jv(l_response, '$.STYLE') is not null, 'Item creation failure keeps reserved style');

    -- 5. PO number reservation succeeds and PO creation fails.
    clear_mock;
    set_cfg('MOCK_FAIL_STEP', 'CREATE_PURCHASE_ORDER');
    l_payload := payload('T-PO-NUMBER-THEN-FAIL');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 502, 'PO number reserved before create failure');
    assert_true(jv(l_response, '$.ORDER_NO') is not null, 'Reserved PO number returned');

    -- 6. Timeout where MFCS status later reports success.
    clear_mock;
    set_cfg('MOCK_TIMEOUT_STEP', 'CREATE_ITEM_HIERARCHY');
    set_cfg('MOCK_TIMEOUT_STATUS', 'SUCCESS');
    l_payload := payload('T-TIMEOUT-SUCCESS');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 503, 'Ambiguous timeout returns 503 first');
    clear_mock;
    set_cfg('MOCK_TIMEOUT_STATUS', 'SUCCESS');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'Recovered timeout success resumes and completes');

    -- 7. Timeout where MFCS has no record and retry is safe.
    clear_mock;
    set_cfg('MOCK_TIMEOUT_STEP', 'CREATE_ITEM_HIERARCHY');
    set_cfg('MOCK_TIMEOUT_STATUS', 'NO_RECORD');
    l_payload := payload('T-TIMEOUT-NO-RECORD');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 503, 'No-record timeout returns 503 first');
    delete from office_mfcs_config where environment = 'DEFAULT' and config_key = 'MOCK_TIMEOUT_STEP';
    commit;
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'No-record timeout retries with new correlation and completes');

    -- 8. Timeout that remains ambiguous and requires manual review.
    clear_mock;
    set_cfg('MOCK_TIMEOUT_STEP', 'CREATE_ITEM_HIERARCHY');
    set_cfg('MOCK_TIMEOUT_STATUS', 'UNKNOWN');
    l_payload := payload('T-TIMEOUT-UNKNOWN');
    submit(l_payload, l_http, l_response);
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 503, 'Unknown timeout returns 503');
    assert_eq(jv(l_response, '$.STATUS'), 'MANUAL_REVIEW', 'Unknown timeout moves to manual review');

    -- 9. Same request ID and same payload returns completed result.
    clear_mock;
    l_payload := payload('T-IDEMPOTENT');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'Initial idempotent request completed');
    l_count := attempts_for('T-IDEMPOTENT', 'RESERVE_ITEM_NUMBERS');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'Repeated completed request returns 200');
    assert_num_eq(attempts_for('T-IDEMPOTENT', 'RESERVE_ITEM_NUMBERS'), l_count, 'Repeated completed request does not call MFCS again');

    -- 10. Same request ID with changed business payload conflicts.
    l_changed := replace(l_payload, '"RETAIL_PRICE": 69.99', '"RETAIL_PRICE": 79.99');
    submit(l_changed, l_http, l_response);
    assert_num_eq(l_http, 409, 'Changed payload with same id returns conflict');

    -- 11. Partial request resumes without recreating style/SKUs.
    clear_mock;
    set_cfg('MOCK_FAIL_STEP', 'CREATE_ITEM_LOCATIONS');
    l_payload := payload('T-PARTIAL-RESUME');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 502, 'Location failure leaves partial');
    l_count := attempts_for('T-PARTIAL-RESUME', 'RESERVE_ITEM_NUMBERS');
    clear_mock;
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 200, 'Partial request resumes successfully');
    assert_num_eq(attempts_for('T-PARTIAL-RESUME', 'RESERVE_ITEM_NUMBERS'), l_count, 'Partial resume skipped style/SKU creation');

    -- 12. CREATE_ALL rejects populated style, SKU or order numbers.
    l_payload := replace(payload('T-REJECT-IDS'), '"STYLE": null', '"STYLE": "3024998"');
    l_payload := replace(l_payload, '"SKU_ID": null', '"SKU_ID": "10367579"');
    l_payload := replace(l_payload, '"ORDER_NO": null', '"ORDER_NO": 10740001');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 422, 'CREATE_ALL rejects generated identifiers supplied by caller');

    -- 13. MFCS batch-window failure.
    clear_mock;
    set_cfg('BATCH_WINDOW_ACTIVE_YN', 'Y');
    l_payload := payload('T-BATCH');
    submit(l_payload, l_http, l_response);
    assert_num_eq(l_http, 503, 'Batch window returns retryable 503');
    assert_eq(jv(l_response, '$.STATUS'), 'FAILED_NO_SIDE_EFFECT', 'Batch window starts no work');
    assert_num_eq(attempts_for('T-BATCH', 'RESERVE_ITEM_NUMBERS'), 0, 'Batch window made no MFCS attempts');

    -- 14. OAuth placeholder configuration exists; live refresh is exercised in non-MOCK mode with a tenant token endpoint.
    assert_true(office_mfcs_request_pkg.get_config('MFCS_TOKEN_URL') is not null, 'OAuth token URL configured');
    assert_true(office_mfcs_request_pkg.get_config('MFCS_CLIENT_SECRET_REF') is not null, 'OAuth secret reference configured without storing a secret');

    clear_mock;
    dbms_output.put_line('OFFICE MFCS tests passed: ' || g_passed);
end;
/

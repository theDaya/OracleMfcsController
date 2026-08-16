set define off
set serveroutput on size unlimited

prompt Running OFFICE MFCS permutation tests

declare
    g_passed number := 0;
    g_failed number := 0;
    l_payload clob;
    l_response clob;
    l_http number;
    l_style varchar2(30);

    procedure check_true(p_condition in boolean, p_message in varchar2) is
    begin
        if p_condition then
            g_passed := g_passed + 1;
        else
            g_failed := g_failed + 1;
            dbms_output.put_line('FAIL: ' || p_message);
        end if;
    end;

    procedure check_eq(p_actual in varchar2, p_expected in varchar2, p_message in varchar2) is
    begin
        check_true(
            nvl(p_actual, '<NULL>') = nvl(p_expected, '<NULL>'),
            p_message || ' expected=' || nvl(p_expected, '<NULL>') || ' actual=' || nvl(p_actual, '<NULL>')
        );
    end;

    procedure check_num(p_actual in number, p_expected in number, p_message in varchar2) is
    begin
        check_true(
            nvl(p_actual, -999999) = nvl(p_expected, -999999),
            p_message || ' expected=' || p_expected || ' actual=' || p_actual
        );
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

    procedure reset_environment is
    begin
        delete from office_mfcs_config
         where environment = 'DEFAULT'
           and (config_key like 'MOCK_%' or config_key = 'BATCH_WINDOW_ACTIVE_YN');
        set_cfg('MFCS_CLIENT_MODE', 'MOCK');
        set_cfg('BATCH_WINDOW_ACTIVE_YN', 'N');
        set_cfg('FEATURE_INITIAL_RETAIL_YN', 'N');
        commit;
    end;

    procedure clear_test_data is
    begin
        delete from office_mfcs_attempt where action_request_id like 'P-%';
        delete from office_mfcs_step where action_request_id like 'P-%';
        delete from office_mfcs_request where action_request_id like 'P-%';
        delete from office_mfcs_entity_map
         where source_style_ref like 'PERM-STYLE-P-%'
            or source_order_ref like 'PERM-ORDER-P-%';
        commit;
    end;

    function base_payload(p_id in varchar2, p_operation in varchar2) return clob is
        l_json clob := q'~{
  "ACTION_REQUEST_ID": "P-ID",
  "OPERATION_NAME": "OP_VALUE",
  "SOURCE_SYSTEM": "OFFICE",
  "SOURCE_STYLE_REF": "PERM-STYLE-P-ID",
  "SOURCE_ORDER_REF": "PERM-ORDER-P-ID",
  "SOURCE_VERSION": "1",
  "USER_ID": "permutation.test@example.com",
  "DATE_TIME_STAMP": "2026-08-16T20:00:00Z",
  "STYLE": "3500001",
  "ORDER_NO": "10740001",
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
    {"SOURCE_VARIANT_REF": "PERM-STYLE-P-ID-UK7", "SKU_SIZE": "7", "SKU_WIDTH": "STANDARD", "SKU_QTY": 120, "SKU_ID": "10300001"},
    {"SOURCE_VARIANT_REF": "PERM-STYLE-P-ID-UK8", "SKU_SIZE": "8", "SKU_WIDTH": "STANDARD", "SKU_QTY": 150, "SKU_ID": "10300002"}
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
        l_json := replace(replace(l_json, 'P-ID', p_id), 'OP_VALUE', p_operation);

        if p_operation in ('CREATE_STYLE', 'CREATE_ALL') then
            l_json := replace(l_json, '"STYLE": "3500001"', '"STYLE": null');
            l_json := replace(l_json, '"SKU_ID": "10300001"', '"SKU_ID": null');
            l_json := replace(l_json, '"SKU_ID": "10300002"', '"SKU_ID": null');
        end if;

        if p_operation in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then
            l_json := replace(l_json, '"ORDER_NO": "10740001"', '"ORDER_NO": null');
        end if;

        return l_json;
    end;

    function remove_field(p_payload in clob, p_name in varchar2) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
    begin
        l_obj.remove(p_name);
        return l_obj.to_clob;
    end;

    function put_string(p_payload in clob, p_name in varchar2, p_value in varchar2) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
    begin
        l_obj.put(p_name, p_value);
        return l_obj.to_clob;
    end;

    function put_number(p_payload in clob, p_name in varchar2, p_value in number) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
    begin
        l_obj.put(p_name, p_value);
        return l_obj.to_clob;
    end;

    function put_null(p_payload in clob, p_name in varchar2) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
    begin
        l_obj.put_null(p_name);
        return l_obj.to_clob;
    end;

    function variant_string(
        p_payload in clob,
        p_index   in pls_integer,
        p_name    in varchar2,
        p_value   in varchar2
    ) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
        l_array json_array_t;
        l_variant json_object_t;
    begin
        l_array := l_obj.get_array('PLMSizeCurveDtl');
        l_variant := treat(l_array.get(p_index) as json_object_t);
        l_variant.put(p_name, p_value);
        return l_obj.to_clob;
    end;

    function variant_number(
        p_payload in clob,
        p_index   in pls_integer,
        p_name    in varchar2,
        p_value   in number
    ) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
        l_array json_array_t;
        l_variant json_object_t;
    begin
        l_array := l_obj.get_array('PLMSizeCurveDtl');
        l_variant := treat(l_array.get(p_index) as json_object_t);
        l_variant.put(p_name, p_value);
        return l_obj.to_clob;
    end;

    function variant_null(
        p_payload in clob,
        p_index   in pls_integer,
        p_name    in varchar2
    ) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
        l_array json_array_t;
        l_variant json_object_t;
    begin
        l_array := l_obj.get_array('PLMSizeCurveDtl');
        l_variant := treat(l_array.get(p_index) as json_object_t);
        l_variant.put_null(p_name);
        return l_obj.to_clob;
    end;

    function empty_variants(p_payload in clob) return clob is
        l_obj json_object_t := json_object_t.parse(p_payload);
    begin
        l_obj.put('PLMSizeCurveDtl', json_array_t());
        return l_obj.to_clob;
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

    function attempt_count(p_id in varchar2) return number is
        l_count number;
    begin
        select count(*) into l_count from office_mfcs_attempt where action_request_id = p_id;
        return l_count;
    end;

    function step_attempts(p_id in varchar2, p_step in varchar2) return number is
        l_count number;
    begin
        select count(*) into l_count
          from office_mfcs_attempt
         where action_request_id = p_id
           and step_code = p_step;
        return l_count;
    end;

    function attempt_method(p_id in varchar2, p_step in varchar2) return varchar2 is
        l_method varchar2(10);
    begin
        select max(http_method) into l_method
          from office_mfcs_attempt
         where action_request_id = p_id
           and step_code = p_step;
        return l_method;
    end;

    procedure expect_validation_error(
        p_payload in clob,
        p_code    in varchar2,
        p_message in varchar2
    ) is
        l_case_http number;
        l_case_response clob;
    begin
        office_mfcs_api_pkg.validate_transaction(p_payload, l_case_http, l_case_response);
        check_num(l_case_http, 422, p_message || ' returns 422');
        check_true(dbms_lob.instr(l_case_response, '"CODE":"' || p_code || '"') > 0, p_message || ' returns ' || p_code);
    exception
        when others then
            g_failed := g_failed + 1;
            dbms_output.put_line('FAIL: ' || p_message || ' raised ' || sqlerrm);
    end;

    procedure expect_success(
        p_id                in varchar2,
        p_operation         in varchar2,
        p_expected_attempts in number,
        p_expected_style    in varchar2 default null,
        p_expected_order    in varchar2 default null,
        p_style_generated   in boolean default false,
        p_order_generated   in boolean default false
    ) is
        l_case_payload clob := base_payload(p_id, p_operation);
        l_case_http number;
        l_case_response clob;
    begin
        office_mfcs_api_pkg.submit_transaction(l_case_payload, l_case_http, l_case_response);
        check_num(l_case_http, 200, p_operation || ' returns 200');
        check_eq(jv(l_case_response, '$.STATUS'), 'COMPLETED', p_operation || ' completes');
        check_num(attempt_count(p_id), p_expected_attempts, p_operation || ' uses expected MFCS call count');

        if p_style_generated then
            check_true(jv(l_case_response, '$.STYLE') is not null, p_operation || ' returns generated STYLE');
        else
            check_eq(jv(l_case_response, '$.STYLE'), p_expected_style, p_operation || ' returns expected STYLE');
        end if;

        if p_order_generated then
            check_true(jv(l_case_response, '$.ORDER_NO') is not null, p_operation || ' returns generated ORDER_NO');
        else
            check_eq(jv(l_case_response, '$.ORDER_NO'), p_expected_order, p_operation || ' returns expected ORDER_NO');
        end if;
    exception
        when others then
            g_failed := g_failed + 1;
            dbms_output.put_line('FAIL: ' || p_operation || ' success path raised ' || sqlerrm);
    end;

begin
    clear_test_data;
    reset_environment;

    -- Happy paths and operation-specific step graphs.
    expect_success('P-CREATE-ALL', 'CREATE_ALL', 9, null, null, true, true);
    expect_success('P-CREATE-STYLE', 'CREATE_STYLE', 6, null, null, true, false);
    expect_success('P-CREATE-ORDER', 'CREATE_ORDER', 3, '3500001', null, false, true);
    expect_success('P-MODIFY-STYLE', 'MODIFY_STYLE', 5, '3500001', null, false, false);
    expect_success('P-MODIFY-ORDER', 'MODIFY_ORDER', 2, '3500001', '10740001', false, false);

    select style_no into l_style
      from office_mfcs_request
     where action_request_id = 'P-CREATE-STYLE';

    l_payload := put_null(base_payload('P-CREATE-ORDER-RESOLVED', 'CREATE_ORDER'), 'STYLE');
    l_payload := put_string(l_payload, 'SOURCE_STYLE_REF', 'PERM-STYLE-P-CREATE-STYLE');
    l_payload := variant_string(l_payload, 0, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK7');
    l_payload := variant_string(l_payload, 1, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK8');
    l_payload := variant_null(l_payload, 0, 'SKU_ID');
    l_payload := variant_null(l_payload, 1, 'SKU_ID');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 200, 'CREATE_ORDER resolves existing style and SKUs');
    check_eq(jv(l_response, '$.STATUS'), 'COMPLETED', 'Resolved CREATE_ORDER completes');
    check_eq(jv(l_response, '$.STYLE'), l_style, 'Resolved CREATE_ORDER returns mapped style');
    check_true(jv(l_response, '$.ORDER_NO') is not null, 'Resolved CREATE_ORDER returns generated order');

    l_payload := put_null(base_payload('P-MODIFY-ORDER-RESOLVED', 'MODIFY_ORDER'), 'STYLE');
    l_payload := put_string(l_payload, 'SOURCE_STYLE_REF', 'PERM-STYLE-P-CREATE-STYLE');
    l_payload := variant_string(l_payload, 0, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK7');
    l_payload := variant_string(l_payload, 1, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK8');
    l_payload := variant_null(l_payload, 0, 'SKU_ID');
    l_payload := variant_null(l_payload, 1, 'SKU_ID');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 200, 'MODIFY_ORDER resolves existing style and SKUs');
    check_eq(jv(l_response, '$.STATUS'), 'COMPLETED', 'Resolved MODIFY_ORDER completes');
    check_eq(jv(l_response, '$.STYLE'), l_style, 'Resolved MODIFY_ORDER returns mapped style');
    check_eq(jv(l_response, '$.ORDER_NO'), '10740001', 'Resolved MODIFY_ORDER keeps supplied order');

    l_payload := put_string(base_payload('P-MODIFY-STYLE-RESOLVED', 'MODIFY_STYLE'), 'SOURCE_STYLE_REF', 'PERM-STYLE-P-CREATE-STYLE');
    l_payload := put_string(l_payload, 'STYLE', l_style);
    l_payload := variant_string(l_payload, 0, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK7');
    l_payload := variant_string(l_payload, 1, 'SOURCE_VARIANT_REF', 'PERM-STYLE-P-CREATE-STYLE-UK8');
    l_payload := variant_null(l_payload, 0, 'SKU_ID');
    l_payload := variant_null(l_payload, 1, 'SKU_ID');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 200, 'MODIFY_STYLE resolves existing SKUs');
    check_eq(jv(l_response, '$.STATUS'), 'COMPLETED', 'Resolved MODIFY_STYLE completes');
    check_eq(jv(l_response, '$.STYLE'), l_style, 'Resolved MODIFY_STYLE keeps supplied style');

    set_cfg('FEATURE_INITIAL_RETAIL_YN', 'Y');
    commit;
    expect_success('P-CREATE-ALL-RETAIL', 'CREATE_ALL', 10, null, null, true, true);
    check_num(step_attempts('P-CREATE-ALL-RETAIL', 'APPLY_INITIAL_RETAIL'), 1, 'CREATE_ALL applies initial retail when enabled');
    set_cfg('FEATURE_INITIAL_RETAIL_YN', 'N');
    commit;

    check_num(step_attempts('P-CREATE-STYLE', 'RESERVE_ORDER_NUMBER'), 0, 'CREATE_STYLE does not reserve an order');
    check_num(step_attempts('P-CREATE-ORDER', 'RESERVE_ITEM_NUMBERS'), 0, 'CREATE_ORDER does not reserve item numbers');
    check_num(step_attempts('P-MODIFY-STYLE', 'RESERVE_ITEM_NUMBERS'), 0, 'MODIFY_STYLE does not reserve item numbers');
    check_num(step_attempts('P-MODIFY-ORDER', 'RESERVE_ORDER_NUMBER'), 0, 'MODIFY_ORDER reuses the supplied order number');
    check_eq(attempt_method('P-MODIFY-STYLE', 'CREATE_ITEM_HIERARCHY'), 'PUT', 'MODIFY_STYLE uses PUT');
    check_eq(attempt_method('P-MODIFY-ORDER', 'CREATE_PURCHASE_ORDER'), 'PUT', 'MODIFY_ORDER uses PUT');
    check_eq(attempt_method('P-MODIFY-ORDER', 'VERIFY_PURCHASE_ORDER'), 'GET', 'Order verification uses GET');

    -- Contract-level malformed and missing routing fields.
    office_mfcs_api_pkg.submit_transaction('{"ACTION_REQUEST_ID":', l_http, l_response);
    check_num(l_http, 400, 'Malformed JSON returns 400');
    check_true(dbms_lob.instr(l_response, '"CODE":"INVALID_JSON"') > 0, 'Malformed JSON returns INVALID_JSON');

    l_payload := remove_field(base_payload('P-NO-ID', 'CREATE_ALL'), 'ACTION_REQUEST_ID');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 400, 'Missing ACTION_REQUEST_ID returns 400');
    check_true(dbms_lob.instr(l_response, '"CODE":"REQUIRED"') > 0, 'Missing ACTION_REQUEST_ID returns REQUIRED');

    l_payload := remove_field(base_payload('P-NO-OP', 'CREATE_ALL'), 'OPERATION_NAME');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 400, 'Missing OPERATION_NAME returns 400');
    check_true(dbms_lob.instr(l_response, '"CODE":"REQUIRED"') > 0, 'Missing OPERATION_NAME returns REQUIRED');

    l_payload := put_string(base_payload('P-BAD-OP', 'CREATE_ALL'), 'OPERATION_NAME', 'create_all');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 400, 'Case-invalid OPERATION_NAME returns 400');
    check_true(dbms_lob.instr(l_response, '"CODE":"UNSUPPORTED_OPERATION"') > 0, 'Case-invalid operation is unsupported');

    -- Required references and operation identifier permutations.
    expect_validation_error(remove_field(base_payload('P-V01', 'CREATE_ALL'), 'SOURCE_SYSTEM'), 'REQUIRED', 'CREATE_ALL missing SOURCE_SYSTEM');
    expect_validation_error(put_string(base_payload('P-V02', 'CREATE_ALL'), 'SOURCE_SYSTEM', '   '), 'REQUIRED', 'CREATE_ALL blank SOURCE_SYSTEM');
    expect_validation_error(remove_field(base_payload('P-V03', 'CREATE_ALL'), 'SOURCE_STYLE_REF'), 'REQUIRED', 'CREATE_ALL missing SOURCE_STYLE_REF');
    expect_validation_error(remove_field(base_payload('P-V04', 'CREATE_ALL'), 'SOURCE_ORDER_REF'), 'REQUIRED', 'CREATE_ALL missing SOURCE_ORDER_REF');
    expect_validation_error(put_string(base_payload('P-V05', 'CREATE_ALL'), 'STYLE', '3509999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_ALL populated STYLE');
    expect_validation_error(variant_string(base_payload('P-V06', 'CREATE_ALL'), 0, 'SKU_ID', '10399999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_ALL populated SKU_ID');
    expect_validation_error(put_string(base_payload('P-V07', 'CREATE_ALL'), 'ORDER_NO', '10749999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_ALL populated ORDER_NO');
    expect_validation_error(put_string(base_payload('P-V08', 'CREATE_STYLE'), 'STYLE', '3509999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_STYLE populated STYLE');
    expect_validation_error(variant_string(base_payload('P-V09', 'CREATE_STYLE'), 0, 'SKU_ID', '10399999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_STYLE populated SKU_ID');
    expect_validation_error(put_string(base_payload('P-V10', 'CREATE_ORDER'), 'ORDER_NO', '10749999'), 'CREATE_IDENTIFIER_MUST_BE_NULL', 'CREATE_ORDER populated ORDER_NO');
    expect_validation_error(put_null(base_payload('P-V11', 'CREATE_ORDER'), 'STYLE'), 'STYLE_REQUIRED_OR_RESOLVABLE', 'CREATE_ORDER unresolved STYLE');
    expect_validation_error(put_null(base_payload('P-V12', 'MODIFY_STYLE'), 'STYLE'), 'REQUIRED', 'MODIFY_STYLE missing STYLE');
    expect_validation_error(put_null(base_payload('P-V13', 'MODIFY_ORDER'), 'ORDER_NO'), 'REQUIRED', 'MODIFY_ORDER missing ORDER_NO');
    expect_validation_error(put_null(base_payload('P-V14', 'MODIFY_ORDER'), 'STYLE'), 'STYLE_REQUIRED_OR_RESOLVABLE', 'MODIFY_ORDER missing or unresolved STYLE');
    expect_validation_error(variant_null(base_payload('P-V15', 'MODIFY_STYLE'), 0, 'SKU_ID'), 'SKU_REQUIRED_OR_RESOLVABLE', 'MODIFY_STYLE unresolved SKU');
    expect_validation_error(variant_null(base_payload('P-V16', 'MODIFY_ORDER'), 0, 'SKU_ID'), 'SKU_REQUIRED_OR_RESOLVABLE', 'MODIFY_ORDER unresolved SKU');

    -- Product, variant and mapping permutations.
    expect_validation_error(empty_variants(base_payload('P-V17', 'CREATE_ALL')), 'REQUIRED', 'CREATE_ALL empty variant array');
    expect_validation_error(remove_field(base_payload('P-V18', 'CREATE_STYLE'), 'PLMSizeCurveDtl'), 'REQUIRED', 'CREATE_STYLE missing variant array');
    expect_validation_error(variant_null(base_payload('P-V19', 'CREATE_ALL'), 0, 'SKU_SIZE'), 'MAPPING_NOT_FOUND', 'Variant missing size');
    expect_validation_error(variant_null(base_payload('P-V20', 'CREATE_ALL'), 0, 'SKU_WIDTH'), 'MAPPING_NOT_FOUND', 'Variant missing width');
    expect_validation_error(variant_string(base_payload('P-V21', 'CREATE_ALL'), 1, 'SKU_SIZE', '7'), 'DUPLICATE_SIZE_WIDTH', 'Duplicate size and width');
    expect_validation_error(variant_null(base_payload('P-V22', 'CREATE_ALL'), 0, 'SKU_QTY'), 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Null quantity');
    expect_validation_error(variant_number(base_payload('P-V23', 'CREATE_ALL'), 0, 'SKU_QTY', 0), 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Zero quantity');
    expect_validation_error(variant_number(base_payload('P-V24', 'CREATE_ALL'), 0, 'SKU_QTY', -1), 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Negative quantity');
    expect_validation_error(variant_number(base_payload('P-V25', 'CREATE_ALL'), 0, 'SKU_QTY', 1.5), 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Fractional quantity');
    expect_validation_error(variant_string(base_payload('P-V26', 'CREATE_ALL'), 0, 'SKU_SIZE', 'UNKNOWN'), 'MAPPING_NOT_FOUND', 'Unknown size mapping');
    expect_validation_error(variant_string(base_payload('P-V27', 'CREATE_ALL'), 0, 'SKU_WIDTH', 'UNKNOWN'), 'MAPPING_NOT_FOUND', 'Unknown width mapping');
    expect_validation_error(put_number(base_payload('P-V28', 'CREATE_ALL'), 'DEPARTMENT', 999), 'MAPPING_NOT_FOUND', 'Unknown department mapping');
    expect_validation_error(put_number(base_payload('P-V29', 'CREATE_ALL'), 'CLASS', 999), 'MAPPING_NOT_FOUND', 'Unknown class mapping');
    expect_validation_error(put_number(base_payload('P-V30', 'CREATE_ALL'), 'SUBCLASS', 999), 'MAPPING_NOT_FOUND', 'Unknown subclass mapping');
    expect_validation_error(put_number(base_payload('P-V31', 'CREATE_ALL'), 'SUPPLIER', 999), 'MAPPING_NOT_FOUND', 'Unknown supplier mapping');
    expect_validation_error(put_string(base_payload('P-V32', 'CREATE_ALL'), 'ORIGIN_COUNTRY', 'ZZ'), 'MAPPING_NOT_FOUND', 'Unknown country mapping');
    expect_validation_error(put_string(base_payload('P-V33', 'CREATE_ALL'), 'CURRENCY_CODE', 'ZZZ'), 'MAPPING_NOT_FOUND', 'Unknown currency mapping');
    expect_validation_error(put_string(base_payload('P-V34', 'CREATE_ALL'), 'COLOUR', 'UNKNOWN'), 'MAPPING_NOT_FOUND', 'Unknown colour mapping');
    expect_validation_error(remove_field(base_payload('P-V35', 'CREATE_ALL'), 'DEPARTMENT'), 'REQUIRED', 'CREATE_ALL missing department');
    expect_validation_error(remove_field(base_payload('P-V36', 'CREATE_ALL'), 'CLASS'), 'REQUIRED', 'CREATE_ALL missing class');
    expect_validation_error(remove_field(base_payload('P-V37', 'CREATE_ALL'), 'SUBCLASS'), 'REQUIRED', 'CREATE_ALL missing subclass');
    expect_validation_error(remove_field(base_payload('P-V38', 'CREATE_ALL'), 'SUPPLIER'), 'REQUIRED', 'CREATE_ALL missing supplier');
    expect_validation_error(remove_field(base_payload('P-V39', 'CREATE_ALL'), 'ORIGIN_COUNTRY'), 'REQUIRED', 'CREATE_ALL missing country');
    expect_validation_error(remove_field(base_payload('P-V40', 'CREATE_ALL'), 'CURRENCY_CODE'), 'REQUIRED', 'CREATE_ALL missing currency');
    expect_validation_error(remove_field(base_payload('P-V41', 'CREATE_ALL'), 'COLOUR'), 'REQUIRED', 'CREATE_ALL missing colour');

    -- Cost, order and date boundaries.
    expect_validation_error(put_null(base_payload('P-V42', 'CREATE_ALL'), 'UNIT_COST'), 'POSITIVE_VALUE_REQUIRED', 'Null unit cost');
    expect_validation_error(put_number(base_payload('P-V43', 'CREATE_ALL'), 'UNIT_COST', 0), 'POSITIVE_VALUE_REQUIRED', 'Zero unit cost');
    expect_validation_error(put_number(base_payload('P-V44', 'CREATE_ALL'), 'UNIT_COST', -1), 'POSITIVE_VALUE_REQUIRED', 'Negative unit cost');
    expect_validation_error(put_null(base_payload('P-V45', 'CREATE_ALL'), 'RETAIL_PRICE'), 'POSITIVE_VALUE_REQUIRED', 'Null retail price');
    expect_validation_error(put_number(base_payload('P-V46', 'CREATE_ALL'), 'RETAIL_PRICE', 0), 'POSITIVE_VALUE_REQUIRED', 'Zero retail price');
    expect_validation_error(remove_field(base_payload('P-V47', 'CREATE_ORDER'), 'DELIVERY_LOC'), 'REQUIRED', 'CREATE_ORDER missing delivery location');
    expect_validation_error(put_null(base_payload('P-V48', 'MODIFY_ORDER'), 'DELIVERY_LOC'), 'REQUIRED', 'MODIFY_ORDER null delivery location');
    expect_validation_error(put_string(base_payload('P-V49', 'CREATE_ALL'), 'NOT_BEFORE_DATE', '2026-11-01'), 'DATE_RELATIONSHIP', 'Not-before after not-after');
    expect_validation_error(put_string(base_payload('P-V50', 'CREATE_ALL'), 'EARLIEST_SHIP_DATE', '2026-09-01'), 'DATE_RELATIONSHIP', 'Earliest ship after latest ship');
    expect_validation_error(put_string(base_payload('P-V51', 'CREATE_ALL'), 'NOT_BEFORE_DATE', 'not-a-date'), 'INVALID_DATE', 'Malformed not-before date');
    expect_validation_error(put_string(base_payload('P-V52', 'CREATE_ALL'), 'LATEST_SHIP_DATE', '2026-02-30'), 'INVALID_DATE', 'Impossible latest ship date');

    -- Canonical idempotency excludes the volatile transport timestamp.
    l_payload := base_payload('P-VOLATILE-HASH', 'CREATE_ALL');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 200, 'Initial volatile-hash request completes');
    l_payload := put_string(l_payload, 'DATE_TIME_STAMP', '2030-01-01T00:00:00Z');
    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    check_num(l_http, 200, 'Changed DATE_TIME_STAMP remains idempotent');
    check_num(step_attempts('P-VOLATILE-HASH', 'RESERVE_ITEM_NUMBERS'), 1, 'Volatile-field retry does not repeat MFCS work');

    reset_environment;
    dbms_output.put_line('OFFICE MFCS permutation tests passed=' || g_passed || ' failed=' || g_failed);

    if g_failed > 0 then
        raise_application_error(-20001, 'Permutation suite failed ' || g_failed || ' assertions.');
    end if;
end;
/

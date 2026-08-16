set define off
set serveroutput on size unlimited

prompt Running Local MFCS controller-to-RMS end-to-end test

declare
    l_old_mode varchar2(4000);
    l_old_retail varchar2(4000);
    l_payload clob := q'~{
  "ACTION_REQUEST_ID": "LOCAL-MFCS-CREATE-ALL-001",
  "OPERATION_NAME": "CREATE_ALL",
  "SOURCE_SYSTEM": "OFFICE",
  "SOURCE_STYLE_REF": "LOCAL-MFCS-STYLE-001",
  "SOURCE_ORDER_REF": "LOCAL-MFCS-ORDER-001",
  "SOURCE_VERSION": "1",
  "USER_ID": "local.mfcs@example.com",
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
    {"SOURCE_VARIANT_REF": "LOCAL-MFCS-STYLE-001-UK7", "SKU_SIZE": "7", "SKU_WIDTH": "STANDARD", "SKU_QTY": 120, "SKU_ID": null},
    {"SOURCE_VARIANT_REF": "LOCAL-MFCS-STYLE-001-UK8", "SKU_SIZE": "8", "SKU_WIDTH": "STANDARD", "SKU_QTY": 150, "SKU_ID": null}
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
    l_repeat_response clob;
    l_http number;
    l_repeat_http number;
    l_status varchar2(30);
    l_style varchar2(25);
    l_order_no number;
    l_count number;
    l_events_before number;
    l_events_after number;
    l_total_qty number;
    l_total_cost number;
    l_negative_response clob;
    l_negative_http number;

    procedure assert_true(p_condition in boolean, p_message in varchar2) is
    begin
        if not p_condition then
            raise_application_error(-20020, 'LOCAL MFCS ASSERTION FAILED: ' || p_message);
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
        set_cfg('FEATURE_INITIAL_RETAIL_YN', l_old_retail);
        commit;
    end;
begin
    l_old_mode := office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE');
    l_old_retail := office_mfcs_request_pkg.get_config('FEATURE_INITIAL_RETAIL_YN');

    local_mfcs_service_pkg.reset_transactional_data;
    delete from office_mfcs_attempt where action_request_id = 'LOCAL-MFCS-CREATE-ALL-001';
    delete from office_mfcs_step where action_request_id = 'LOCAL-MFCS-CREATE-ALL-001';
    delete from office_mfcs_request where action_request_id = 'LOCAL-MFCS-CREATE-ALL-001';
    delete from office_mfcs_entity_map
     where source_style_ref = 'LOCAL-MFCS-STYLE-001'
        or source_order_ref = 'LOCAL-MFCS-ORDER-001';

    set_cfg('MFCS_CLIENT_MODE', 'LOCAL_MFCS');
    set_cfg('FEATURE_INITIAL_RETAIL_YN', 'N');
    commit;

    office_mfcs_api_pkg.submit_transaction(l_payload, l_http, l_response);
    dbms_output.put_line('HTTP=' || l_http || ' RESPONSE=' || dbms_lob.substr(l_response, 1500, 1));

    select json_value(l_response, '$.STATUS' returning varchar2(30)),
           json_value(l_response, '$.STYLE' returning varchar2(25)),
           json_value(l_response, '$.ORDER_NO' returning number)
      into l_status, l_style, l_order_no
      from dual;

    assert_true(l_http = 200, 'CREATE_ALL returns HTTP 200');
    assert_true(l_status = 'COMPLETED', 'CREATE_ALL completes');
    assert_true(l_style is not null and l_order_no is not null, 'generated style and order are returned');

    select count(*) into l_count from item_master;
    assert_true(l_count = 3, 'ITEM_MASTER contains one style and two SKUs');

    select count(*) into l_count
      from item_master
     where item = l_style
       and item_level = 1
       and tran_level = 2
       and diff_1 = 'SHOE_SIZE'
       and diff_2 = 'WIDTH_STD'
       and diff_3 = 'COLOR_STD'
       and status = 'A';
    assert_true(l_count = 1, 'style row references seeded diff groups and is approved');

    select count(*) into l_count
      from item_master
     where item_parent = l_style
       and item_level = 2
       and tran_level = 2
       and diff_1 in ('7', '8')
       and diff_2 = 'STANDARD'
       and diff_3 = 'BLACK'
       and status = 'A';
    assert_true(l_count = 2, 'SKU rows carry concrete size, width and colour diffs');

    select count(*) into l_count from item_supplier where supplier = 70001 and primary_supp_ind = 'Y';
    assert_true(l_count = 2, 'both transaction items have a primary supplier');
    select count(*) into l_count from item_supp_country where supplier = 70001 and origin_country_id = 'CN' and unit_cost = 22.75;
    assert_true(l_count = 2, 'both transaction items have China sourcing and unit cost');
    select count(*) into l_count from item_loc where location = 98 and loc_type = 'S' and status = 'A';
    assert_true(l_count = 2, 'both transaction items are active at store 98');

    select count(*), max(total_qty_ordered), max(total_cost)
      into l_count, l_total_qty, l_total_cost
      from ordhead
     where order_no = l_order_no
       and status = 'A';
    assert_true(l_count = 1, 'ORDHEAD contains the approved order');
    assert_true(l_total_qty = 270, 'ORDHEAD total quantity is 270');
    assert_true(l_total_cost = 6142.5, 'ORDHEAD total cost is 6142.5');
    select count(*) into l_count from ordsku where order_no = l_order_no;
    assert_true(l_count = 2, 'ORDSKU contains two order/item aggregates');
    select count(*) into l_count from ordloc where order_no = l_order_no and location = 98 and origin_country_id = 'CN';
    assert_true(l_count = 2, 'ORDLOC contains two sourced location lines');

    select count(*) into l_count
      from local_mfcs_rest_event
     where response_code = 200
       and service_name in (
          'RESERVE_ITEM_NUMBERS', 'ITEMS', 'ITEMS_UPDATE', 'ITEM_SUPPLIERS',
          'ITEM_UDAS', 'ITEM_LOCATIONS', 'RESERVE_ORDER_NUMBERS',
          'PURCHASE_ORDERS', 'GET_ORDER'
       );
    assert_true(l_count = 9, 'all nine downstream service attempts are journalled');

    select count(*) into l_events_before from local_mfcs_rest_event;
    office_mfcs_api_pkg.submit_transaction(l_payload, l_repeat_http, l_repeat_response);
    select count(*) into l_events_after from local_mfcs_rest_event;
    assert_true(l_repeat_http = 200, 'idempotent repeat returns HTTP 200');
    assert_true(l_events_after = l_events_before, 'idempotent repeat creates no downstream service events');

    local_mfcs_service_pkg.handle(
        p_resource => 'ITEMS',
        p_http_method => 'POST',
        p_request_payload => q'~{"collectionSize":1,"items":[{"item":"3999999","itemDescription":"Invalid Diff","itemLevel":1,"tranLevel":1,"dept":100,"class":10,"subclass":1,"diff1":"NOT_A_DIFF","diff1Type":"S","dataLoadingDestination":"RMS"}]}~',
        p_correlation_id => 'local-mfcs-negative-diff',
        o_http_status => l_negative_http,
        o_response => l_negative_response
    );
    assert_true(l_negative_http = 400, 'unknown differentiator returns HTTP 400');
    select count(*) into l_count from item_master where item = '3999999';
    assert_true(l_count = 0, 'invalid item is not persisted');

    local_mfcs_service_pkg.handle(
        p_resource => 'ITEMS',
        p_http_method => 'POST',
        p_request_payload => '{"collectionSize":1,"items":[{"item":"3999997","itemParent":"' || l_style || '","itemDescription":"Out of Group Size","itemLevel":2,"tranLevel":2,"dept":100,"class":10,"subclass":1,"diff1":"13","diff1Type":"S","diff2":"STANDARD","diff2Type":"W","diff3":"BLACK","diff3Type":"C","dataLoadingDestination":"RMS"}]}',
        p_correlation_id => 'local-mfcs-negative-diff-group',
        o_http_status => l_negative_http,
        o_response => l_negative_response
    );
    assert_true(l_negative_http = 400, 'diff ID outside the parent group returns HTTP 400');
    select count(*) into l_count from item_master where item = '3999997';
    assert_true(l_count = 0, 'out-of-group SKU is not persisted');

    restore_config;
    dbms_output.put_line('Local MFCS controller-to-RMS tests passed: 26');
exception
    when others then
        restore_config;
        raise;
end;
/

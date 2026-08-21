set define off
set serveroutput on size unlimited
set lines 200

-- Exercises the preview package for CREATE_ALL and MODIFY_ORDER.
-- Sends nothing to MFCS and leaves no request rows behind.

declare
    l_payload clob;
    l_status number;
    l_response clob;
    l_calls json_array_t;
    l_call json_object_t;
    l_root json_object_t;
    l_before number;
    l_after number;

    procedure run(p_label in varchar2, p_payload in clob) is
        l_st number;
        l_resp clob;
        l_r json_object_t;
        l_c json_array_t;
        l_o json_object_t;
    begin
        office_mfcs_preview_pkg.preview_transaction(p_payload, l_st, l_resp);
        l_r := json_object_t.parse(l_resp);
        dbms_output.put_line('=========================================================');
        dbms_output.put_line(p_label || '   HTTP ' || l_st || '   VALID=' || l_r.get_string('VALID'));
        if l_r.get('MFCS_CALLS') is not null then
            l_c := l_r.get_array('MFCS_CALLS');
            dbms_output.put_line('planned calls: ' || l_c.get_size);
            for i in 0 .. l_c.get_size - 1 loop
                l_o := treat(l_c.get(i) as json_object_t);
                dbms_output.put_line('  ' || lpad(l_o.get_number('sequence'), 4) || '  '
                    || rpad(l_o.get_string('method'), 6)
                    || rpad(l_o.get_string('stepCode'), 38)
                    || nvl(l_o.get_string('endpointPath'), '(local)'));
            end loop;
        end if;
        if l_r.get('ERRORS') is not null then
            dbms_output.put_line('errors: ' || substr(l_r.get('ERRORS').to_string, 1, 600));
        end if;
    end;
begin
    select count(*) into l_before from office_mfcs_request;

    l_payload := q'[{
      "ACTION_REQUEST_ID": "PREVIEW-TEST-1",
      "OPERATION_NAME": "CREATE_ALL",
      "SOURCE_SYSTEM": "OFFICE_DEV",
      "SOURCE_STYLE_REF": "Preview test style",
      "SOURCE_ORDER_REF": "Preview test order",
      "SOURCE_VERSION": "1",
      "USER_ID": "office.buyer@example.com",
      "DESCRIPTION": "Preview test",
      "DEPARTMENT": "1517",
      "CLASS": "6892",
      "SUBCLASS": "1128",
      "SUPPLIER": "700087",
      "ORIGIN_COUNTRY": "GB",
      "IMPORT_COUNTRY": "GB",
      "CURRENCY_CODE": "ZAR",
      "COLOUR": "08610",
      "UNIT_COST": 48.49,
      "RETAIL_PRICE": 100,
      "PLMSizeCurveDtl": [
        {"SOURCE_VARIANT_REF": "pv-7", "SKU_SIZE": "7", "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null},
        {"SOURCE_VARIANT_REF": "pv-8", "SKU_SIZE": "8", "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null}
      ],
      "NOT_BEFORE_DATE": "2026-08-21",
      "NOT_AFTER_DATE": "2026-08-21",
      "OTB_EOW_DATE": "2026-08-23",
      "EARLIEST_SHIP_DATE": "2026-08-21",
      "LATEST_SHIP_DATE": "2026-09-09",
      "DELIVERY_LOC": 1927,
      "ORDER_EXCHANGE_RATE": 1
    }]';
    run('CREATE_ALL', l_payload);

    l_payload := q'[{
      "ACTION_REQUEST_ID": "PREVIEW-TEST-2",
      "OPERATION_NAME": "MODIFY_ORDER",
      "SOURCE_SYSTEM": "OFFICE_DEV",
      "SOURCE_STYLE_REF": "Preview modify style",
      "SOURCE_ORDER_REF": "Preview modify order",
      "SOURCE_VERSION": "2",
      "USER_ID": "office.buyer@example.com",
      "DESCRIPTION": "Preview modify",
      "STYLE": "100050005",
      "ORDER_NO": 25005,
      "DEPARTMENT": "1517",
      "CLASS": "6892",
      "SUBCLASS": "1128",
      "SUPPLIER": "700087",
      "ORIGIN_COUNTRY": "GB",
      "IMPORT_COUNTRY": "GB",
      "CURRENCY_CODE": "ZAR",
      "COLOUR": "08610",
      "UNIT_COST": 50.00,
      "RETAIL_PRICE": 110,
      "PLMSizeCurveDtl": [
        {"SOURCE_VARIANT_REF": "pv-7", "SKU_SIZE": "7", "SKU_WIDTH": "ALL", "SKU_QTY": 5, "SKU_ID": "100050013"}
      ],
      "NOT_BEFORE_DATE": "2026-08-21",
      "NOT_AFTER_DATE": "2026-08-21",
      "OTB_EOW_DATE": "2026-08-23",
      "EARLIEST_SHIP_DATE": "2026-08-21",
      "LATEST_SHIP_DATE": "2026-09-09",
      "DELIVERY_LOC": 1927,
      "ORDER_EXCHANGE_RATE": 1
    }]';
    run('MODIFY_ORDER', l_payload);

    l_payload := q'[{"ACTION_REQUEST_ID":"PREVIEW-TEST-3","OPERATION_NAME":"CREATE_ALL","SOURCE_SYSTEM":"OFFICE_DEV"}]';
    run('CREATE_ALL (deliberately incomplete)', l_payload);

    select count(*) into l_after from office_mfcs_request;
    dbms_output.put_line('=========================================================');
    dbms_output.put_line('office_mfcs_request rows before=' || l_before || ' after=' || l_after
        || '  (must be equal - preview must leave no trace)');
end;
/

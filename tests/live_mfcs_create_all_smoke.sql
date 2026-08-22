set define off
set serveroutput on

declare
    l_payload clob;
    l_http number;
    l_response clob;
    l_action_request_id varchar2(80) :=
        'DAYALAN-ALL-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
    l_source_ref varchar2(120) :=
        'Dayalan all ' || to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS.FF3');
begin
    update config
       set config_value = 'N',
           updated_at = systimestamp
     where environment = 'DEFAULT'
       and config_key in ('FEATURE_INITIAL_RETAIL_YN', 'FEATURE_ITEM_LOCATIONS_YN');

    commit;

    l_payload := '{'
        || '"ACTION_REQUEST_ID":"' || l_action_request_id || '",'
        || '"OPERATION_NAME":"CREATE_ALL",'
        || '"SOURCE_SYSTEM":"OFFICE_DEV",'
        || '"SOURCE_STYLE_REF":"' || l_source_ref || '",'
        || '"SOURCE_ORDER_REF":"' || l_source_ref || '-PO",'
        || '"SOURCE_VERSION":"1",'
        || '"USER_ID":"office.buyer@example.com",'
        || '"STYLE":null,'
        || '"ORDER_NO":null,'
        || '"DESCRIPTION":"Dayalan order test",'
        || '"DEPARTMENT":"1517",'
        || '"CLASS":"6892",'
        || '"SUBCLASS":"1128",'
        || '"SUPPLIER":"700087",'
        || '"ORIGIN_COUNTRY":"GB",'
        || '"IMPORT_COUNTRY":"GB",'
        || '"CURRENCY_CODE":"ZAR",'
        || '"COLOUR":"08610",'
        || '"UNIT_COST":48.49,'
        || '"RETAIL_PRICE":100,'
        || '"PLMSizeCurveDtl":['
        || '{"SOURCE_VARIANT_REF":"' || l_source_ref || '-7",'
        || '"SKU_SIZE":"7","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null},'
        || '{"SOURCE_VARIANT_REF":"' || l_source_ref || '-8",'
        || '"SKU_SIZE":"8","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null}'
        || '],'
        || '"NOT_BEFORE_DATE":"' || to_char(trunc(sysdate), 'YYYY-MM-DD') || '",'
        || '"NOT_AFTER_DATE":"' || to_char(trunc(sysdate), 'YYYY-MM-DD') || '",'
        || '"OTB_EOW_DATE":"' || to_char(next_day(trunc(sysdate) - 1, 'SUNDAY'), 'YYYY-MM-DD') || '",'
        || '"EARLIEST_SHIP_DATE":"' || to_char(trunc(sysdate), 'YYYY-MM-DD') || '",'
        || '"LATEST_SHIP_DATE":"' || to_char(trunc(sysdate) + 19, 'YYYY-MM-DD') || '",'
        || '"DELIVERY_LOC":1927,'
        || '"PO_TYPE":null,'
        || '"ORDER_EXCHANGE_RATE":1'
        || '}';

    api_pkg.submit_transaction(l_payload, l_http, l_response);

    dbms_output.put_line('ACTION_REQUEST_ID=' || l_action_request_id);
    dbms_output.put_line('HTTP_STATUS=' || l_http);
    dbms_output.put_line('RESPONSE=' || dbms_lob.substr(l_response, 4000, 1));
end;
/

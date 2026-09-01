set define off
set serveroutput on

declare
    l_payload clob;
    l_http number;
    l_response clob;
    l_action_request_id varchar2(80) :=
        'DAYALAN-TEST-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
    l_source_ref varchar2(120) :=
        'Dayalan test ' || to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS.FF3');
begin

    l_payload := '{'
        || '"ACTION_REQUEST_ID":"' || l_action_request_id || '",'
        || '"OPERATION_NAME":"CREATE_STYLE",'
        || '"SOURCE_SYSTEM":"OFFICE_DEV",'
        || '"SOURCE_STYLE_REF":"' || l_source_ref || '",'
        || '"SOURCE_VERSION":"1",'
        || '"STYLE":null,'
        || '"DESCRIPTION":"Dayalan test x",'
        || '"DEPARTMENT":"1517",'
        || '"CLASS":"6892",'
        || '"SUBCLASS":"1128",'
        || '"SUPPLIER":"700087",'
        || '"ORIGIN_COUNTRY":"GB",'
        || '"CURRENCY_CODE":"ZAR",'
        || '"COLOUR":"08610",'
        || '"UNIT_COST":48.49,'
        || '"RETAIL_PRICE":100,'
        || '"SIZE_CURVE_DETAIL":['
        || '{"SOURCE_VARIANT_REF":"' || l_source_ref || '-7",'
        || '"SKU_SIZE":"7","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null},'
        || '{"SOURCE_VARIANT_REF":"' || l_source_ref || '-8",'
        || '"SKU_SIZE":"8","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null}'
        || ']}';

    api_pkg.submit_transaction(l_payload, l_http, l_response);

    dbms_output.put_line('ACTION_REQUEST_ID=' || l_action_request_id);
    dbms_output.put_line('HTTP_STATUS=' || l_http);
    dbms_output.put_line('RESPONSE=' || dbms_lob.substr(l_response, 4000, 1));
exception
    when others then
        raise;
end;
/

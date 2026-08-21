set define off
set serveroutput on size unlimited
set lines 200

-- Diagnostic: why does a mapper return an empty body in ACTUAL_MFCS mode?

declare
    l_id varchar2(100) := 'DBG-PREVIEW-1';
    l_payload clob;
    l_result varchar2(30);
    l_status varchar2(40);
    l_existing clob;
    l_out clob;
    l_len number;
    l_mode varchar2(40);
    l_ready varchar2(10);

    procedure try(p_name in varchar2, p_body in clob) is
    begin
        dbms_output.put_line(rpad(p_name, 42) || 'len=' || nvl(dbms_lob.getlength(p_body), 0)
            || '  ' || substr(dbms_lob.substr(p_body, 300, 1), 1, 300));
    end;
begin
    select dbms_lob.substr(config_value, 40, 1) into l_mode
      from office_mfcs_config where config_key = 'MFCS_CLIENT_MODE' and environment = 'DEFAULT';
    select dbms_lob.substr(config_value, 10, 1) into l_ready
      from office_mfcs_config where config_key = 'MFCS_SCHEMA_READY_YN' and environment = 'DEFAULT';
    dbms_output.put_line('MFCS_CLIENT_MODE     = ' || l_mode);
    dbms_output.put_line('MFCS_SCHEMA_READY_YN = ' || l_ready);
    dbms_output.put_line('');

    l_payload := q'[{"ACTION_REQUEST_ID":"DBG-PREVIEW-1","OPERATION_NAME":"CREATE_ALL","SOURCE_SYSTEM":"OFFICE_DEV","SOURCE_STYLE_REF":"dbg","SOURCE_ORDER_REF":"dbgo","SOURCE_VERSION":"1","DESCRIPTION":"d","DEPARTMENT":"1517","CLASS":"6892","SUBCLASS":"1128","SUPPLIER":"700087","ORIGIN_COUNTRY":"GB","IMPORT_COUNTRY":"GB","CURRENCY_CODE":"ZAR","COLOUR":"08610","UNIT_COST":48.49,"RETAIL_PRICE":100,"PLMSizeCurveDtl":[{"SOURCE_VARIANT_REF":"v7","SKU_SIZE":"7","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null}],"NOT_BEFORE_DATE":"2026-08-21","NOT_AFTER_DATE":"2026-08-21","OTB_EOW_DATE":"2026-08-23","EARLIEST_SHIP_DATE":"2026-08-21","LATEST_SHIP_DATE":"2026-09-09","DELIVERY_LOC":1927,"ORDER_EXCHANGE_RATE":1}]';

    delete from office_mfcs_step where action_request_id = l_id;
    delete from office_mfcs_request where action_request_id = l_id;
    commit;

    office_mfcs_request_pkg.register_request(
        l_id, 'CREATE_ALL', office_mfcs_request_pkg.payload_hash(l_payload),
        l_payload, l_result, l_status, l_existing);
    dbms_output.put_line('register result = ' || l_result);

    select dbms_lob.getlength(request_payload) into l_len
      from office_mfcs_request where action_request_id = l_id;
    dbms_output.put_line('stored payload len = ' || l_len);
    dbms_output.put_line('');

    try('build_item_number_request', office_mfcs_mapping_pkg.build_item_number_request(l_id));
    try('build_parent_item_create_request', office_mfcs_mapping_pkg.build_parent_item_create_request(l_id));
    try('build_child_item_create_request', office_mfcs_mapping_pkg.build_child_item_create_request(l_id));
    try('build_item_create_request', office_mfcs_mapping_pkg.build_item_create_request(l_id));
    try('build_purchase_order_request', office_mfcs_mapping_pkg.build_purchase_order_request(l_id));

    delete from office_mfcs_step where action_request_id = l_id;
    delete from office_mfcs_request where action_request_id = l_id;
    commit;
exception
    when others then
        dbms_output.put_line('ERROR: ' || sqlerrm);
        rollback;
end;
/

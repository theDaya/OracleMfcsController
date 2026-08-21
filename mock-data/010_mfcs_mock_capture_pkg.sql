set define off

prompt Creating MFCS mock capture package

create or replace package mfcs_mock_capture_pkg authid definer as
    procedure capture_foundation_item(p_item in varchar2);
end mfcs_mock_capture_pkg;
/

create or replace package body mfcs_mock_capture_pkg as
    function bearer_token return varchar2 is
        l_token varchar2(32767);
    begin
        select dbms_lob.substr(secret_value, 32767, 1)
          into l_token
          from office_mfcs_secret
         where secret_ref = office_mfcs_request_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');

        if lower(substr(trim(l_token), 1, 7)) <> 'bearer ' then
            return 'Bearer ' || trim(l_token);
        end if;

        return trim(l_token);
    end;

    procedure upsert_item(
        p_capture_id in number,
        p_response   in clob
    ) is
    begin
        merge into mfcs_mock.mfcs_foundation_item t
        using (
            select *
              from json_table(p_response, '$.items[*]'
                  columns (
                      item varchar2(30) path '$.item',
                      item_number_type varchar2(30) path '$.itemNumberType',
                      status varchar2(10) path '$.status',
                      item_level number path '$.itemLevel',
                      tran_level number path '$.tranLevel',
                      item_description varchar2(500) path '$.itemDescription',
                      short_description varchar2(250) path '$.shortDescription',
                      sellable_ind varchar2(1) path '$.sellableInd',
                      orderable_ind varchar2(1) path '$.orderableInd',
                      inventory_ind varchar2(1) path '$.inventoryInd',
                      dept number path '$.dept',
                      dept_name varchar2(250) path '$.deptName',
                      class number path '$.class',
                      class_name varchar2(250) path '$.className',
                      subclass number path '$.subclass',
                      subclass_name varchar2(250) path '$.subclassName',
                      diff1 varchar2(80) path '$.diff1',
                      diff1_type varchar2(30) path '$.diff1Type',
                      diff1_description varchar2(250) path '$.diff1Description',
                      diff2 varchar2(80) path '$.diff2',
                      diff2_type varchar2(30) path '$.diff2Type',
                      diff2_description varchar2(250) path '$.diff2Description',
                      diff3 varchar2(80) path '$.diff3',
                      diff3_type varchar2(30) path '$.diff3Type',
                      diff3_description varchar2(250) path '$.diff3Description',
                      diff4 varchar2(80) path '$.diff4',
                      diff4_type varchar2(30) path '$.diff4Type',
                      diff4_description varchar2(250) path '$.diff4Description',
                      brand_name varchar2(250) path '$.brandName',
                      brand_description varchar2(250) path '$.brandDescription',
                      standard_uom varchar2(30) path '$.standardUom',
                      unit_retail number path '$.unitRetail',
                      retail_currency varchar2(10) path '$.manufacturerRetailCurrencyCode',
                      primary_image_url varchar2(1000) path '$.primaryImageUrl'
                  )
              )
        ) s
        on (t.item = s.item)
        when matched then update set
            t.item_number_type = s.item_number_type,
            t.status = s.status,
            t.item_level = s.item_level,
            t.tran_level = s.tran_level,
            t.item_description = s.item_description,
            t.short_description = s.short_description,
            t.sellable_ind = s.sellable_ind,
            t.orderable_ind = s.orderable_ind,
            t.inventory_ind = s.inventory_ind,
            t.dept = s.dept,
            t.dept_name = s.dept_name,
            t.class = s.class,
            t.class_name = s.class_name,
            t.subclass = s.subclass,
            t.subclass_name = s.subclass_name,
            t.diff1 = s.diff1,
            t.diff1_type = s.diff1_type,
            t.diff1_description = s.diff1_description,
            t.diff2 = s.diff2,
            t.diff2_type = s.diff2_type,
            t.diff2_description = s.diff2_description,
            t.diff3 = s.diff3,
            t.diff3_type = s.diff3_type,
            t.diff3_description = s.diff3_description,
            t.diff4 = s.diff4,
            t.diff4_type = s.diff4_type,
            t.diff4_description = s.diff4_description,
            t.brand_name = s.brand_name,
            t.brand_description = s.brand_description,
            t.standard_uom = s.standard_uom,
            t.unit_retail = s.unit_retail,
            t.retail_currency = s.retail_currency,
            t.primary_image_url = s.primary_image_url,
            t.source_capture_id = p_capture_id,
            t.last_refreshed_at = systimestamp
        when not matched then insert (
            item, item_number_type, status, item_level, tran_level, item_description, short_description,
            sellable_ind, orderable_ind, inventory_ind, dept, dept_name, class, class_name, subclass, subclass_name,
            diff1, diff1_type, diff1_description, diff2, diff2_type, diff2_description,
            diff3, diff3_type, diff3_description, diff4, diff4_type, diff4_description,
            brand_name, brand_description, standard_uom, unit_retail, retail_currency, primary_image_url,
            source_capture_id
        ) values (
            s.item, s.item_number_type, s.status, s.item_level, s.tran_level, s.item_description, s.short_description,
            s.sellable_ind, s.orderable_ind, s.inventory_ind, s.dept, s.dept_name, s.class, s.class_name, s.subclass, s.subclass_name,
            s.diff1, s.diff1_type, s.diff1_description, s.diff2, s.diff2_type, s.diff2_description,
            s.diff3, s.diff3_type, s.diff3_description, s.diff4, s.diff4_type, s.diff4_description,
            s.brand_name, s.brand_description, s.standard_uom, s.unit_retail, s.retail_currency, s.primary_image_url,
            p_capture_id
        );
    end;

    procedure upsert_suppliers(
        p_capture_id in number,
        p_response   in clob
    ) is
    begin
        merge into mfcs_mock.mfcs_foundation_supplier t
        using (
            select item, supplier, primary_supplier_ind, vpn, supplier_label
              from json_table(p_response, '$.items[*]'
                  columns (
                      item varchar2(30) path '$.item',
                      nested path '$.itemSupplier[*]'
                          columns (
                              supplier number path '$.supplier',
                              primary_supplier_ind varchar2(1) path '$.primarySupplierInd',
                              vpn varchar2(250) path '$.vpn',
                              supplier_label varchar2(250) path '$.supplierLabel'
                          )
                  )
              )
             where supplier is not null
        ) s
        on (t.item = s.item and t.supplier = s.supplier)
        when matched then update set
            t.primary_supplier_ind = s.primary_supplier_ind,
            t.vpn = s.vpn,
            t.supplier_label = s.supplier_label,
            t.source_capture_id = p_capture_id,
            t.last_refreshed_at = systimestamp
        when not matched then insert (
            item, supplier, primary_supplier_ind, vpn, supplier_label, source_capture_id
        ) values (
            s.item, s.supplier, s.primary_supplier_ind, s.vpn, s.supplier_label, p_capture_id
        );

        merge into mfcs_mock.mfcs_foundation_supplier_country t
        using (
            select item, supplier, origin_country_id, primary_country_ind, unit_cost, currency_code
              from json_table(p_response, '$.items[*]'
                  columns (
                      item varchar2(30) path '$.item',
                      nested path '$.itemSupplier[*]'
                          columns (
                              supplier number path '$.supplier',
                              nested path '$.itemSupplierCountry[*]'
                                  columns (
                                      origin_country_id varchar2(10) path '$.originCountry',
                                      primary_country_ind varchar2(1) path '$.primaryCountryInd',
                                      unit_cost number path '$.unitCost',
                                      currency_code varchar2(10) path '$.currencyCode'
                                  )
                          )
                  )
              )
             where supplier is not null
               and origin_country_id is not null
        ) s
        on (t.item = s.item and t.supplier = s.supplier and t.origin_country_id = s.origin_country_id)
        when matched then update set
            t.primary_country_ind = s.primary_country_ind,
            t.unit_cost = s.unit_cost,
            t.currency_code = s.currency_code,
            t.source_capture_id = p_capture_id,
            t.last_refreshed_at = systimestamp
        when not matched then insert (
            item, supplier, origin_country_id, primary_country_ind, unit_cost, currency_code, source_capture_id
        ) values (
            s.item, s.supplier, s.origin_country_id, s.primary_country_ind, s.unit_cost, s.currency_code, p_capture_id
        );
    end;

    procedure capture_foundation_item(p_item in varchar2) is
        l_url varchar2(1200);
        l_response clob;
        l_capture_id number;
    begin
        l_url := rtrim(office_mfcs_request_pkg.get_config('MFCS_BASE_URL'), '/')
              || '/MerchIntegrations/services/foundation/item/'
              || trim(p_item);

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := bearer_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';

        l_response := apex_web_service.make_rest_request(
            p_url => l_url,
            p_http_method => 'GET',
            p_transfer_timeout => to_number(office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '60'))
        );

        l_capture_id := mfcs_mock.mfcs_api_capture_seq.nextval;

        insert into mfcs_mock.mfcs_api_capture (
            capture_id,
            resource_type,
            resource_key,
            endpoint_url,
            http_status,
            response_payload
        ) values (
            l_capture_id,
            'FOUNDATION_ITEM',
            trim(p_item),
            l_url,
            apex_web_service.g_status_code,
            l_response
        );

        if apex_web_service.g_status_code between 200 and 299 then
            upsert_item(l_capture_id, l_response);
            upsert_suppliers(l_capture_id, l_response);
        end if;

        commit;
        dbms_output.put_line('HTTP_STATUS=' || apex_web_service.g_status_code);
        dbms_output.put_line('CAPTURE_ID=' || l_capture_id);
        dbms_output.put_line('RESPONSE_LEN=' || dbms_lob.getlength(l_response));
    end;
end mfcs_mock_capture_pkg;
/

show errors

prompt MFCS mock capture package created

set define off

-- Field-level validation of the inbound Office document.

prompt Creating validation_pkg

create or replace package validation_pkg authid definer as
    function validate_request(
        p_payload in clob,
        o_errors  out clob
    ) return boolean;
end validation_pkg;
/

show errors

create or replace package body validation_pkg as
    procedure add_error(
        p_errors in out nocopy json_array_t,
        p_field  in varchar2,
        p_code   in varchar2,
        p_msg    in varchar2
    ) is
        l_error json_object_t := json_object_t();
    begin
        l_error.put('FIELD', p_field);
        l_error.put('CODE', p_code);
        l_error.put('MESSAGE', p_msg);
        p_errors.append(l_error);
    end;

    function has_config(p_key in varchar2) return boolean is
    begin
        return config_pkg.get_config(p_key) is not null;
    end;

    function validate_request(
        p_payload in clob,
        o_errors  out clob
    ) return boolean is
        l_errors json_array_t := json_array_t();
        l_action_request_id varchar2(80);
        l_operation varchar2(30);
        l_source_system varchar2(60);
        l_source_style_ref varchar2(120);
        l_source_order_ref varchar2(120);
        l_style varchar2(30);
        l_order_no varchar2(30);
        l_delivery_loc varchar2(30);
        l_department varchar2(30);
        l_class varchar2(30);
        l_subclass varchar2(30);
        l_supplier varchar2(30);
        l_country varchar2(30);
        l_currency varchar2(30);
        l_colour varchar2(60);
        l_unit_cost number;
        l_retail_price number;
        l_not_before date;
        l_not_after date;
        l_earliest date;
        l_latest date;
        l_not_before_text varchar2(30);
        l_not_after_text varchar2(30);
        l_earliest_text varchar2(30);
        l_latest_text varchar2(30);
        l_count number;
        l_distinct_count number;
        l_parsed json_element_t;
    begin
        begin
            l_parsed := json_element_t.parse(p_payload);
        exception
            when others then
                add_error(l_errors, '$', 'INVALID_JSON', sqlerrm);
                o_errors := l_errors.to_clob;
                return false;
        end;

        select json_value(p_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error),
               json_value(p_payload, '$.OPERATION_NAME' returning varchar2(30) null on error),
               json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60) null on error),
               json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.SOURCE_ORDER_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.STYLE' returning varchar2(30) null on error),
               json_value(p_payload, '$.ORDER_NO' returning varchar2(30) null on error),
               json_value(p_payload, '$.DELIVERY_LOC' returning varchar2(30) null on error),
               json_value(p_payload, '$.DEPARTMENT' returning varchar2(30) null on error),
               json_value(p_payload, '$.CLASS' returning varchar2(30) null on error),
               json_value(p_payload, '$.SUBCLASS' returning varchar2(30) null on error),
               json_value(p_payload, '$.SUPPLIER' returning varchar2(30) null on error),
               json_value(p_payload, '$.ORIGIN_COUNTRY' returning varchar2(30) null on error),
               json_value(p_payload, '$.CURRENCY_CODE' returning varchar2(30) null on error),
               json_value(p_payload, '$.COLOUR' returning varchar2(60) null on error),
               json_value(p_payload, '$.UNIT_COST' returning number null on error),
               json_value(p_payload, '$.RETAIL_PRICE' returning number null on error)
          into l_action_request_id, l_operation, l_source_system, l_source_style_ref,
               l_source_order_ref, l_style, l_order_no, l_delivery_loc, l_department,
               l_class, l_subclass, l_supplier, l_country, l_currency, l_colour,
               l_unit_cost, l_retail_price
          from dual;

        if trim(l_action_request_id) is null then
            add_error(l_errors, 'ACTION_REQUEST_ID', 'REQUIRED', 'ACTION_REQUEST_ID is required.');
        end if;

        if trim(l_operation) is null then
            add_error(l_errors, 'OPERATION_NAME', 'REQUIRED', 'OPERATION_NAME is required.');
        elsif l_operation not in ('CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            add_error(l_errors, 'OPERATION_NAME', 'UNSUPPORTED_OPERATION', 'Unsupported OPERATION_NAME.');
        end if;

        if trim(l_source_system) is null then
            add_error(l_errors, 'SOURCE_SYSTEM', 'REQUIRED', 'SOURCE_SYSTEM is required.');
        end if;

        if trim(l_source_style_ref) is null and l_operation in ('CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ALL') then
            add_error(l_errors, 'SOURCE_STYLE_REF', 'REQUIRED', 'SOURCE_STYLE_REF is required.');
        end if;

        if trim(l_source_order_ref) is null and l_operation in ('CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            add_error(l_errors, 'SOURCE_ORDER_REF', 'REQUIRED', 'SOURCE_ORDER_REF is required.');
        end if;

        if l_operation in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then
            if trim(l_department) is null then
                add_error(l_errors, 'DEPARTMENT', 'REQUIRED', 'DEPARTMENT is required for create operations.');
            end if;
            if trim(l_class) is null then
                add_error(l_errors, 'CLASS', 'REQUIRED', 'CLASS is required for create operations.');
            end if;
            if trim(l_subclass) is null then
                add_error(l_errors, 'SUBCLASS', 'REQUIRED', 'SUBCLASS is required for create operations.');
            end if;
            if trim(l_supplier) is null then
                add_error(l_errors, 'SUPPLIER', 'REQUIRED', 'SUPPLIER is required for create operations.');
            end if;
            if trim(l_country) is null then
                add_error(l_errors, 'ORIGIN_COUNTRY', 'REQUIRED', 'ORIGIN_COUNTRY is required for create operations.');
            end if;
            if trim(l_currency) is null then
                add_error(l_errors, 'CURRENCY_CODE', 'REQUIRED', 'CURRENCY_CODE is required for create operations.');
            end if;
            if trim(l_colour) is null then
                add_error(l_errors, 'COLOUR', 'REQUIRED', 'COLOUR is required for create operations.');
            end if;
        end if;

        select count(*)
          into l_count
          from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
              columns sku_id varchar2(60) path '$.SKU_ID' null on error
          )
         where sku_id is not null;

        if l_operation = 'CREATE_ALL' then
            if l_style is not null then
                add_error(l_errors, 'STYLE', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'STYLE must be null for CREATE_ALL.');
            end if;
            if l_count > 0 then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_ID', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'SKU_ID must be null for CREATE_ALL.');
            end if;
            if l_order_no is not null then
                add_error(l_errors, 'ORDER_NO', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'ORDER_NO must be null for CREATE_ALL.');
            end if;
        elsif l_operation = 'CREATE_STYLE' then
            if l_style is not null then
                add_error(l_errors, 'STYLE', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'STYLE must be null for CREATE_STYLE.');
            end if;
            if l_count > 0 then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_ID', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'SKU_ID must be null for CREATE_STYLE.');
            end if;
        elsif l_operation = 'CREATE_ORDER' then
            if l_order_no is not null then
                add_error(l_errors, 'ORDER_NO', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'ORDER_NO must be null for CREATE_ORDER.');
            end if;
            if trim(l_style) is null then
                select count(*)
                  into l_count
                  from entity_map
                 where source_system = l_source_system
                   and source_style_ref = l_source_style_ref
                   and mfcs_style_no is not null;
                if l_count = 0 then
                    add_error(l_errors, 'STYLE', 'STYLE_REQUIRED_OR_RESOLVABLE', 'STYLE is required or must be resolvable for CREATE_ORDER.');
                end if;
            end if;
        elsif l_operation = 'MODIFY_ORDER' then
            if l_order_no is null then
                add_error(l_errors, 'ORDER_NO', 'REQUIRED', 'ORDER_NO is required for MODIFY_ORDER.');
            end if;
            if trim(l_style) is null then
                select count(*)
                  into l_count
                  from entity_map
                 where source_system = l_source_system
                   and source_style_ref = l_source_style_ref
                   and mfcs_style_no is not null;
                if l_count = 0 then
                    add_error(l_errors, 'STYLE', 'STYLE_REQUIRED_OR_RESOLVABLE', 'STYLE is required or must be resolvable for MODIFY_ORDER.');
                end if;
            end if;
        elsif l_operation = 'MODIFY_STYLE' then
            if l_style is null then
                add_error(l_errors, 'STYLE', 'REQUIRED', 'STYLE is required for MODIFY_STYLE.');
            end if;
        end if;

        select count(*), count(distinct sku_size || '|' || sku_width)
          into l_count, l_distinct_count
          from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
              columns
                  sku_size varchar2(60) path '$.SKU_SIZE' null on error,
                  sku_width varchar2(60) path '$.SKU_WIDTH' null on error
          );

        if l_count = 0 and l_operation in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then
            add_error(l_errors, 'PLMSizeCurveDtl', 'REQUIRED', 'At least one size/width variant is required.');
        elsif l_count <> l_distinct_count then
            add_error(l_errors, 'PLMSizeCurveDtl', 'DUPLICATE_SIZE_WIDTH', 'Size and width combinations must be unique.');
        end if;

        select count(*)
          into l_count
          from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
              columns sku_qty number path '$.SKU_QTY' null on error
          )
         where sku_qty is null
            or sku_qty <= 0
            or sku_qty <> trunc(sku_qty);

        if l_count > 0 then
            add_error(l_errors, 'PLMSizeCurveDtl.SKU_QTY', 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Quantities must be positive whole numbers.');
        end if;

        if l_operation in ('CREATE_ORDER', 'MODIFY_STYLE', 'MODIFY_ORDER') then
            for v in (
                select source_variant_ref, sku_id
                  from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
                      columns
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF' null on error,
                          sku_id varchar2(60) path '$.SKU_ID' null on error
                  )
            ) loop
                if trim(v.sku_id) is null then
                    select count(*)
                      into l_count
                      from entity_map
                     where source_system = l_source_system
                       and source_style_ref = l_source_style_ref
                       and source_variant_ref = v.source_variant_ref
                       and mfcs_sku_no is not null;

                    if l_count = 0 then
                        add_error(l_errors, 'PLMSizeCurveDtl.SKU_ID', 'SKU_REQUIRED_OR_RESOLVABLE', 'SKU_ID is required or must be resolvable for this operation.');
                    end if;
                end if;
            end loop;
        end if;

        if l_delivery_loc is null and l_operation in ('CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            add_error(l_errors, 'DELIVERY_LOC', 'REQUIRED', 'DELIVERY_LOC is required for order operations.');
        end if;

        if l_operation in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then
            if l_unit_cost is null or l_unit_cost <= 0 then
                add_error(l_errors, 'UNIT_COST', 'POSITIVE_VALUE_REQUIRED', 'UNIT_COST is required and must be positive.');
            end if;

            if l_retail_price is null or l_retail_price <= 0 then
                add_error(l_errors, 'RETAIL_PRICE', 'POSITIVE_VALUE_REQUIRED', 'RETAIL_PRICE is required and must be positive.');
            end if;
        end if;

        select json_value(p_payload, '$.NOT_BEFORE_DATE' returning varchar2(30) null on error),
               json_value(p_payload, '$.NOT_AFTER_DATE' returning varchar2(30) null on error),
               json_value(p_payload, '$.EARLIEST_SHIP_DATE' returning varchar2(30) null on error),
               json_value(p_payload, '$.LATEST_SHIP_DATE' returning varchar2(30) null on error)
          into l_not_before_text, l_not_after_text, l_earliest_text, l_latest_text
          from dual;

        select to_date(l_not_before_text default null on conversion error, 'FXYYYY-MM-DD'),
               to_date(l_not_after_text default null on conversion error, 'FXYYYY-MM-DD'),
               to_date(l_earliest_text default null on conversion error, 'FXYYYY-MM-DD'),
               to_date(l_latest_text default null on conversion error, 'FXYYYY-MM-DD')
          into l_not_before, l_not_after, l_earliest, l_latest
          from dual;

        if l_not_before_text is not null and l_not_before is null then
            add_error(l_errors, 'NOT_BEFORE_DATE', 'INVALID_DATE', 'NOT_BEFORE_DATE must use YYYY-MM-DD and be a valid date.');
        end if;
        if l_not_after_text is not null and l_not_after is null then
            add_error(l_errors, 'NOT_AFTER_DATE', 'INVALID_DATE', 'NOT_AFTER_DATE must use YYYY-MM-DD and be a valid date.');
        end if;
        if l_earliest_text is not null and l_earliest is null then
            add_error(l_errors, 'EARLIEST_SHIP_DATE', 'INVALID_DATE', 'EARLIEST_SHIP_DATE must use YYYY-MM-DD and be a valid date.');
        end if;
        if l_latest_text is not null and l_latest is null then
            add_error(l_errors, 'LATEST_SHIP_DATE', 'INVALID_DATE', 'LATEST_SHIP_DATE must use YYYY-MM-DD and be a valid date.');
        end if;

        if l_not_before is not null and l_not_after is not null and l_not_before > l_not_after then
            add_error(l_errors, 'NOT_BEFORE_DATE', 'DATE_RELATIONSHIP', 'NOT_BEFORE_DATE must be on or before NOT_AFTER_DATE.');
        end if;

        if l_earliest is not null and l_latest is not null and l_earliest > l_latest then
            add_error(l_errors, 'EARLIEST_SHIP_DATE', 'DATE_RELATIONSHIP', 'EARLIEST_SHIP_DATE must be on or before LATEST_SHIP_DATE.');
        end if;

        if trim(l_department) is not null and not has_config('MAP.DEPARTMENT.' || l_department) then
            add_error(l_errors, 'DEPARTMENT', 'MAPPING_NOT_FOUND', 'Department mapping is not configured.');
        end if;

        if trim(l_department) is not null and trim(l_class) is not null and not has_config('MAP.CLASS.' || l_department || '.' || l_class) then
            add_error(l_errors, 'CLASS', 'MAPPING_NOT_FOUND', 'Class mapping is not configured.');
        end if;

        if trim(l_department) is not null and trim(l_class) is not null and trim(l_subclass) is not null
           and not has_config('MAP.SUBCLASS.' || l_department || '.' || l_class || '.' || l_subclass) then
            add_error(l_errors, 'SUBCLASS', 'MAPPING_NOT_FOUND', 'Subclass mapping is not configured.');
        end if;

        if trim(l_supplier) is not null and not has_config('MAP.SUPPLIER.' || l_supplier) then
            add_error(l_errors, 'SUPPLIER', 'MAPPING_NOT_FOUND', 'Supplier mapping is not configured.');
        end if;

        if trim(l_country) is not null and not has_config('MAP.COUNTRY.' || upper(l_country)) then
            add_error(l_errors, 'ORIGIN_COUNTRY', 'MAPPING_NOT_FOUND', 'Country mapping is not configured.');
        end if;

        if trim(l_currency) is not null and not has_config('MAP.CURRENCY.' || upper(l_currency)) then
            add_error(l_errors, 'CURRENCY_CODE', 'MAPPING_NOT_FOUND', 'Currency mapping is not configured.');
        end if;

        if trim(l_colour) is not null and not has_config('MAP.COLOUR.' || upper(l_colour)) then
            add_error(l_errors, 'COLOUR', 'MAPPING_NOT_FOUND', 'Colour mapping is not configured.');
        end if;

        for v in (
            select sku_size, sku_width
              from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      sku_size varchar2(60) path '$.SKU_SIZE' null on error,
                      sku_width varchar2(60) path '$.SKU_WIDTH' null on error
              )
        ) loop
            if v.sku_size is null or not has_config('MAP.SIZE.' || upper(v.sku_size)) then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_SIZE', 'MAPPING_NOT_FOUND', 'Size mapping is not configured.');
            end if;

            if v.sku_width is null or not has_config('MAP.WIDTH.' || upper(v.sku_width)) then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_WIDTH', 'MAPPING_NOT_FOUND', 'Width mapping is not configured.');
            end if;
        end loop;

        if l_errors.get_size > 0 then
            o_errors := l_errors.to_clob;
            return false;
        end if;

        o_errors := '[]';
        return true;
    end;
end validation_pkg;
/

show errors

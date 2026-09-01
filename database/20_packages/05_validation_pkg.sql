set define off

-- Field-level validation of the inbound Office document.
--
-- Runs before anything is registered or sent, so a rejected request has no
-- side effects anywhere. Checks presence, types, dates and reference values
-- translations; rules MFCS only enforces late (OTB_EOW_DATE falling on a
-- Sunday, for one) are checked here so they fail before a style exists and an
-- order number is burned.

prompt Creating validation_pkg

create or replace package validation_pkg authid definer as
    -- Returns true when the document is executable. On false, o_errors is a
    -- JSON array of {FIELD, CODE, MESSAGE} - every problem found, not only
    -- the first.
    function validate_request(
        p_payload in clob,
        o_errors  out clob
    ) return boolean;
end validation_pkg;
/

show errors

create or replace package body validation_pkg as
    -- Whether a barcode is a well-formed EAN-13.
    --
    -- Worth checking here because MFCS will not: it validates the length of the
    -- number but not its check digit, so a transposed pair of digits is accepted
    -- and creates a barcode that no scanner will ever match. Catching it costs
    -- nothing; finding it later means the item exists and cannot be unmade.
    function is_valid_ean13(p_upc in varchar2) return boolean is
        l_sum pls_integer := 0;
        l_digit pls_integer;
    begin
        if p_upc is null or length(p_upc) <> 13 or not regexp_like(p_upc, '^[0-9]{13}$') then
            return false;
        end if;
        for i in 1 .. 12 loop
            l_digit := to_number(substr(p_upc, i, 1));
            l_sum := l_sum + l_digit * case when mod(i, 2) = 0 then 3 else 1 end;
        end loop;
        return to_number(substr(p_upc, 13, 1)) = mod(10 - mod(l_sum, 10), 10);
    end;

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

    -- Whether the tenant holds this reference value.
    --
    -- These checks used to read MAP.* config, a list maintained alongside master
    -- data and free to disagree with it - which is how MAP.COLOUR.BLACK came to
    -- exist, offering a colour the tenant would reject after an item number had
    -- already been burned. Master data is what the tenant actually has.
    --
    -- Returns true when the type has not been loaded at all. A database whose
    -- master data has never been refreshed should not reject every document; it
    -- should behave as it did before the check existed. The refresh log is where
    -- an empty type is visible, not here.
    function has_master(
        p_type   in varchar2,
        p_code   in varchar2,
        p_parent in varchar2 default '~'
    ) return boolean is
        l_loaded number;
        l_found number;
    begin
        if p_code is null then
            return false;
        end if;

        select count(*) into l_loaded from master_data where data_type = p_type;
        if l_loaded = 0 then
            return true;
        end if;

        select count(*)
          into l_found
          from master_data
         where data_type = p_type
           and data_code = p_code
           and parent_code = nvl(p_parent, '~');
        return l_found > 0;
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
        l_otb_eow_text varchar2(30);
        l_otb_eow date;
        l_week_end_day varchar2(20);
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
          from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
              columns sku_id varchar2(60) path '$.SKU_ID' null on error
          )
         where sku_id is not null;

        if l_operation = 'CREATE_ALL' then
            if l_style is not null then
                add_error(l_errors, 'STYLE', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'STYLE must be null for CREATE_ALL.');
            end if;
            if l_count > 0 then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_ID', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'SKU_ID must be null for CREATE_ALL.');
            end if;
            if l_order_no is not null then
                add_error(l_errors, 'ORDER_NO', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'ORDER_NO must be null for CREATE_ALL.');
            end if;
        elsif l_operation = 'CREATE_STYLE' then
            if l_style is not null then
                add_error(l_errors, 'STYLE', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'STYLE must be null for CREATE_STYLE.');
            end if;
            if l_count > 0 then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_ID', 'CREATE_IDENTIFIER_MUST_BE_NULL', 'SKU_ID must be null for CREATE_STYLE.');
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
          from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
              columns
                  sku_size varchar2(60) path '$.SKU_SIZE' null on error,
                  sku_width varchar2(60) path '$.SKU_WIDTH' null on error
          );

        if l_count = 0 and l_operation in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then
            add_error(l_errors, 'SIZE_CURVE_DETAIL', 'REQUIRED', 'At least one size/width variant is required.');
        elsif l_count <> l_distinct_count then
            add_error(l_errors, 'SIZE_CURVE_DETAIL', 'DUPLICATE_SIZE_WIDTH', 'Size and width combinations must be unique.');
        end if;

        select count(*)
          into l_count
          from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
              columns sku_qty number path '$.SKU_QTY' null on error
          )
         where sku_qty is null
            or sku_qty <= 0
            or sku_qty <> trunc(sku_qty);

        if l_count > 0 then
            add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_QTY', 'POSITIVE_WHOLE_NUMBER_REQUIRED', 'Quantities must be positive whole numbers.');
        end if;

        -- Barcodes. Optional by design: a document with no SKU_UPCS produces no
        -- rows here and no errors, which is what lets Office adopt them per style
        -- rather than all at once.
        for u in (
            select source_variant_ref, upc, upc_type, primary_yn
              from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF' null on error,
                      nested path '$.SKU_UPCS[*]'
                          columns (
                              upc        varchar2(30) path '$.UPC' null on error,
                              upc_type   varchar2(10) path '$.UPC_TYPE' null on error,
                              primary_yn varchar2(1)  path '$.PRIMARY_YN' null on error
                          )
              )
             where upc is not null or primary_yn is not null
        ) loop
            if trim(u.upc) is null then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_UPCS.UPC', 'REQUIRED',
                    'UPC is required on every SKU_UPCS entry.');
            elsif nvl(upper(u.upc_type), 'EAN13') = 'EAN13'
                  and not is_valid_ean13(trim(u.upc)) then
                -- Only EAN13 is checked. MANL barcodes are free-form by definition,
                -- and a real Office SKU carries one of each.
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_UPCS.UPC', 'INVALID_EAN13',
                    'UPC ' || u.upc || ' is not a valid 13-digit EAN with a correct check digit.');
            end if;
        end loop;

        -- Exactly one primary barcode per SKU, for the SKUs that have any.
        --
        -- MFCS does not appear to enforce this and a second primary would be a
        -- silent contradiction in the tenant, which is the failure mode this layer
        -- exists to prevent.
        for v in (
            select source_variant_ref,
                   count(*) upc_count,
                   count(case when upper(primary_yn) = 'Y' then 1 end) primary_count
              from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF' null on error,
                      nested path '$.SKU_UPCS[*]'
                          columns (
                              upc        varchar2(30) path '$.UPC' null on error,
                              primary_yn varchar2(1)  path '$.PRIMARY_YN' null on error
                          )
              )
             where upc is not null
             group by source_variant_ref
        ) loop
            if v.primary_count <> 1 then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_UPCS.PRIMARY_YN', 'ONE_PRIMARY_UPC_REQUIRED',
                    'SKU ' || v.source_variant_ref || ' has ' || v.primary_count
                    || ' primary barcodes across ' || v.upc_count || '; exactly one must be PRIMARY_YN Y.');
            end if;
        end loop;

        -- UDAs, checked against the tenant's own definitions.
        --
        -- Skipped entirely when master data holds no UDA definitions. On a tenant
        -- whose uda feed has never been refreshed - or has gone empty again, which
        -- is how this one behaved until recently - validating would reject every
        -- document carrying a UDA rather than reject the ones that are wrong.
        select count(*)
          into l_count
          from master_data
         where data_type = 'UDA';

        if l_count > 0 then
            for u in (
                select uda_id, uda_value, uda_text, uda_date
                  from json_table(p_payload, '$.STYLE_UDAS[*]'
                      columns
                          uda_id    number        path '$.UDA_ID' null on error,
                          uda_value varchar2(30)  path '$.UDA_VALUE' null on error,
                          uda_text  varchar2(250) path '$.UDA_TEXT' null on error,
                          uda_date  varchar2(30)  path '$.UDA_DATE' null on error
                  )
            ) loop
                if u.uda_id is null then
                    add_error(l_errors, 'STYLE_UDAS.UDA_ID', 'REQUIRED',
                        'UDA_ID is required on every STYLE_UDAS entry.');
                else
                    select count(*)
                      into l_distinct_count
                      from master_data
                     where data_type = 'UDA'
                       and data_code = to_char(u.uda_id)
                       and parent_code = '~';

                    if l_distinct_count = 0 then
                        add_error(l_errors, 'STYLE_UDAS.UDA_ID', 'UNKNOWN_UDA',
                            'UDA ' || u.uda_id || ' is not defined on this tenant.');
                    elsif u.uda_value is not null then
                        -- Only list-of-values UDAs have a value set to check
                        -- against; freeform and date carry whatever they carry.
                        select count(*)
                          into l_distinct_count
                          from master_data
                         where data_type = 'UDA_VALUE'
                           and parent_code = to_char(u.uda_id)
                           and data_code = u.uda_value;

                        if l_distinct_count = 0 then
                            select count(*)
                              into l_distinct_count
                              from master_data
                             where data_type = 'UDA_VALUE'
                               and parent_code = to_char(u.uda_id);

                            -- A UDA with no values loaded is not evidence the value
                            -- is wrong, so only complain when there is a list to
                            -- have failed against.
                            if l_distinct_count > 0 then
                                add_error(l_errors, 'STYLE_UDAS.UDA_VALUE', 'UNKNOWN_UDA_VALUE',
                                    'Value ' || u.uda_value || ' is not in the list of values for UDA '
                                    || u.uda_id || '.');
                            end if;
                        end if;
                    end if;
                end if;
            end loop;
        end if;

        -- Only when the integration has no way to work the SKU out for itself.
        --
        -- entity_map is this database's memory, not the tenant's: a style created by
        -- an earlier install, or by somebody else entirely, leaves no row behind and
        -- fails this check while being perfectly orderable. ENSURE_STYLE_SKUS reads
        -- the style and either finds the SKU - recording the mapping as it goes - or
        -- creates it, so with generation on an unresolvable row is not yet an error.
        -- With generation off it still is, and failing here costs no side effect.
        if l_operation in ('CREATE_ORDER', 'MODIFY_STYLE', 'MODIFY_ORDER')
           and config_pkg.get_config('FEATURE_GENERATE_MISSING_SKUS_YN', 'Y') <> 'Y' then
            for v in (
                select source_variant_ref, sku_id
                  from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
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
                        add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_ID', 'SKU_REQUIRED_OR_RESOLVABLE', 'SKU_ID is required or must be resolvable for this operation.');
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
               json_value(p_payload, '$.LATEST_SHIP_DATE' returning varchar2(30) null on error),
               json_value(p_payload, '$.OTB_EOW_DATE' returning varchar2(30) null on error)
          into l_not_before_text, l_not_after_text, l_earliest_text, l_latest_text, l_otb_eow_text
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

        -- OTB end-of-week must land on the retail calendar's week-ending day.
        -- MFCS enforces this at purchase-order create, which is step 100: by then a
        -- style has been created and an order number burned, leaving a partially
        -- completed request over a date the caller could have corrected up front.
        -- The tenant calendar (administration/operations/calendar) starts every
        -- retail month on a Monday, so the week ends Sunday. Configurable because
        -- another tenant may run a different calendar.
        l_otb_eow := to_date(l_otb_eow_text default null on conversion error, 'FXYYYY-MM-DD');
        if l_otb_eow_text is not null and l_otb_eow is null then
            add_error(l_errors, 'OTB_EOW_DATE', 'INVALID_DATE', 'OTB_EOW_DATE must use YYYY-MM-DD and be a valid date.');
        elsif l_otb_eow is not null then
            l_week_end_day := upper(config_pkg.get_config('MFCS_OTB_EOW_DAY', 'SUNDAY'));
            if l_week_end_day is not null
               and trim(to_char(l_otb_eow, 'DAY', 'NLS_DATE_LANGUAGE=ENGLISH')) <> l_week_end_day then
                add_error(l_errors, 'OTB_EOW_DATE', 'NOT_WEEK_END_DATE',
                    'OTB_EOW_DATE must fall on a ' || initcap(l_week_end_day)
                    || ' to match the retail calendar; '
                    || to_char(l_otb_eow, 'YYYY-MM-DD') || ' is a '
                    || trim(initcap(to_char(l_otb_eow, 'DAY', 'NLS_DATE_LANGUAGE=ENGLISH'))) || '.');
            end if;
        end if;

        -- Non-merchandise costs. Optional, but a malformed one is worth catching
        -- here: MFCS applies expenses during order create, and a rejection there
        -- costs a burned order number.
        for e in (
            select component, component_rate, rn
              from json_table(p_payload, '$.NON_MERCH_COSTS[*]'
                  columns
                      rn for ordinality,
                      component      varchar2(30) path '$.COMPONENT',
                      component_rate number       path '$.RATE'
              )
        ) loop
            if trim(e.component) is null then
                add_error(l_errors, 'NON_MERCH_COSTS.COMPONENT', 'REQUIRED',
                    'COMPONENT is required on non-merchandise cost row ' || e.rn || '.');
            end if;
            if e.component_rate is null or e.component_rate < 0 then
                add_error(l_errors, 'NON_MERCH_COSTS.RATE', 'POSITIVE_VALUE_REQUIRED',
                    'RATE is required and cannot be negative on non-merchandise cost row ' || e.rn || '.');
            end if;
        end loop;

        if trim(l_department) is not null
           and not has_master('DEPARTMENT', trim(l_department)) then
            add_error(l_errors, 'DEPARTMENT', 'UNKNOWN_DEPARTMENT',
                'Department ' || l_department || ' is not known to this tenant.');
        end if;

        if trim(l_department) is not null and trim(l_class) is not null
           and not has_master('CLASS', trim(l_class), trim(l_department)) then
            add_error(l_errors, 'CLASS', 'UNKNOWN_CLASS',
                'Class ' || l_class || ' is not known under department ' || l_department || '.');
        end if;

        if trim(l_department) is not null and trim(l_class) is not null and trim(l_subclass) is not null
           and not has_master('SUBCLASS', trim(l_subclass),
                              trim(l_department) || '.' || trim(l_class)) then
            add_error(l_errors, 'SUBCLASS', 'UNKNOWN_SUBCLASS',
                'Subclass ' || l_subclass || ' is not known under ' || l_department || '.' || l_class || '.');
        end if;

        if trim(l_supplier) is not null
           and not has_master('SUPPLIER_SVC', trim(l_supplier)) then
            add_error(l_errors, 'SUPPLIER', 'UNKNOWN_SUPPLIER',
                'Supplier ' || l_supplier || ' is not known to this tenant.');
        end if;

        if trim(l_country) is not null
           and not has_master('COUNTRY', upper(trim(l_country))) then
            add_error(l_errors, 'ORIGIN_COUNTRY', 'UNKNOWN_COUNTRY',
                'Country ' || l_country || ' is not known to this tenant.');
        end if;

        if trim(l_currency) is not null
           and not has_master('CURRENCY', upper(trim(l_currency))) then
            add_error(l_errors, 'CURRENCY_CODE', 'UNKNOWN_CURRENCY',
                'Currency ' || l_currency || ' is not known to this tenant.');
        end if;

        -- The colour is a differentiator ID, not a name. Front ends send the
        -- tenant's own code; there is no description to translate.
        if trim(l_colour) is not null
           and not has_master('DIFF_C', trim(l_colour)) then
            add_error(l_errors, 'COLOUR', 'UNKNOWN_COLOUR',
                'Colour ' || l_colour || ' is not a differentiator on this tenant.');
        end if;

        for v in (
            select sku_size, sku_width
              from json_table(p_payload, '$.SIZE_CURVE_DETAIL[*]'
                  columns
                      sku_size varchar2(60) path '$.SKU_SIZE' null on error,
                      sku_width varchar2(60) path '$.SKU_WIDTH' null on error
              )
        ) loop
            -- Likewise a differentiator ID. This is what removed the last reason
            -- to keep MAP: eight size descriptions are ambiguous on this tenant
            -- ("16" is three different differentiators), and a code never is.
            if v.sku_size is null then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_SIZE', 'REQUIRED',
                    'SKU_SIZE is required.');
            elsif not has_master('DIFF_S', trim(v.sku_size)) then
                add_error(l_errors, 'SIZE_CURVE_DETAIL.SKU_SIZE', 'UNKNOWN_SIZE',
                    'Size ' || v.sku_size || ' is not a differentiator on this tenant.');
            end if;

        end loop;

        declare
            l_brand varchar2(120) := json_value(p_payload, '$.BRAND' returning varchar2(120) null on error);
            l_brands number;
        begin
            if trim(l_brand) is not null then
                select count(*) into l_brands from master_data where data_type = 'BRAND';
                if l_brands > 0 then
                    select count(*)
                      into l_count
                      from master_data
                     where data_type = 'BRAND'
                       and data_code = l_brand;
                    if l_count = 0 then
                        add_error(l_errors, 'BRAND', 'UNKNOWN_BRAND',
                            'Brand ' || l_brand || ' is not defined on this tenant.');
                    end if;
                end if;
            end if;
        end;

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

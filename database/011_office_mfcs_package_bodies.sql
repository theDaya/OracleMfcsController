set define off

prompt Creating OFFICE MFCS package bodies

create or replace package body office_mfcs_request_pkg as
    function json_escape(p_value in varchar2) return varchar2 is
    begin
        if p_value is null then
            return null;
        end if;

        return replace(
                   replace(
                       replace(
                           replace(p_value, '\', '\\'),
                           '"', '\"'
                       ),
                       chr(10), '\n'
                   ),
                   chr(13), '\r'
               );
    end;

    function get_config(
        p_key         in varchar2,
        p_default     in varchar2 default null,
        p_environment in varchar2 default 'DEFAULT'
    ) return varchar2 is
        l_value varchar2(32767);
    begin
        select dbms_lob.substr(config_value, 32767, 1)
          into l_value
          from office_mfcs_config
         where environment = p_environment
           and config_key = p_key
           and enabled_ind = 'Y';

        return l_value;
    exception
        when no_data_found then
            return p_default;
    end;

    function canonicalize(p_element in json_element_t) return clob is
        l_object json_object_t;
        l_array json_array_t;
        l_keys json_key_list;
        l_key varchar2(4000);
        l_tmp varchar2(4000);
        l_result clob;
        l_first boolean := true;
    begin
        if p_element is null then
            return 'null';
        elsif p_element.is_object then
            l_object := treat(p_element as json_object_t);
            l_keys := l_object.get_keys;

            if l_keys is not null then
                for i in 1 .. l_keys.count loop
                    if i < l_keys.count then
                        for j in i + 1 .. l_keys.count loop
                            if l_keys(j) < l_keys(i) then
                                l_tmp := l_keys(i);
                                l_keys(i) := l_keys(j);
                                l_keys(j) := l_tmp;
                            end if;
                        end loop;
                    end if;
                end loop;
            end if;

            l_result := '{';
            if l_keys is not null then
                for i in 1 .. l_keys.count loop
                    l_key := l_keys(i);
                    if upper(l_key) not in ('DATE_TIME_STAMP', 'REQUEST_RECEIVED_AT', 'TRANSPORT_ID') then
                        if l_first then
                            l_first := false;
                        else
                            l_result := l_result || ',';
                        end if;

                        l_result := l_result
                            || '"' || json_escape(l_key) || '":'
                            || canonicalize(l_object.get(l_key));
                    end if;
                end loop;
            end if;
            l_result := l_result || '}';
            return l_result;
        elsif p_element.is_array then
            l_array := treat(p_element as json_array_t);
            l_result := '[';

            if l_array.get_size > 0 then
                for i in 0 .. l_array.get_size - 1 loop
                    if i > 0 then
                        l_result := l_result || ',';
                    end if;
                    l_result := l_result || canonicalize(l_array.get(i));
                end loop;
            end if;

            l_result := l_result || ']';
            return l_result;
        else
            return p_element.to_string;
        end if;
    end;

    function payload_hash(p_payload in clob) return varchar2 is
        l_element json_element_t;
        l_canonical clob;
        l_hash varchar2(64);
    begin
        l_element := json_element_t.parse(p_payload);
        l_canonical := canonicalize(l_element);

        l_hash := rawtohex(dbms_crypto.hash(l_canonical, dbms_crypto.hash_sh256));

        return lower(l_hash);
    end;

    procedure register_request(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2,
        p_payload_hash      in varchar2,
        p_payload           in clob,
        p_result            out varchar2,
        p_status            out varchar2,
        p_response_payload  out clob
    ) is
        l_existing_hash varchar2(64);
        l_status varchar2(30);
        l_source_system varchar2(60);
        l_source_style_ref varchar2(120);
        l_source_order_ref varchar2(120);
        l_source_version varchar2(60);
        l_style_no varchar2(30);
        l_order_no varchar2(30);
    begin
        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60) null on error),
               json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.SOURCE_ORDER_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.SOURCE_VERSION' returning varchar2(60) null on error),
               json_value(p_payload, '$.STYLE' returning varchar2(30) null on error),
               json_value(p_payload, '$.ORDER_NO' returning varchar2(30) null on error)
          into l_source_system, l_source_style_ref, l_source_order_ref, l_source_version,
               l_style_no, l_order_no
          from dual;

        if l_style_no is null and l_source_system is not null and l_source_style_ref is not null then
            select max(mfcs_style_no)
              into l_style_no
              from office_mfcs_entity_map
             where source_system = l_source_system
               and source_style_ref = l_source_style_ref
               and mfcs_style_no is not null;
        end if;

        if p_operation_name in ('CREATE_STYLE', 'MODIFY_STYLE') then
            l_order_no := null;
        end if;

        begin
            insert into office_mfcs_request (
                action_request_id,
                operation_name,
                source_system,
                source_style_ref,
                source_order_ref,
                source_version,
                payload_hash,
                request_status,
                style_no,
                order_no,
                request_payload
            ) values (
                p_action_request_id,
                p_operation_name,
                l_source_system,
                l_source_style_ref,
                l_source_order_ref,
                l_source_version,
                p_payload_hash,
                'RECEIVED',
                l_style_no,
                l_order_no,
                p_payload
            );

            commit;
            p_result := 'NEW';
            p_status := 'RECEIVED';
            p_response_payload := null;
            return;
        exception
            when dup_val_on_index then
                null;
        end;

        begin
            select payload_hash, request_status, response_payload
              into l_existing_hash, l_status, p_response_payload
              from office_mfcs_request
             where action_request_id = p_action_request_id
             for update nowait;
        exception
            when others then
                if sqlcode = -54 then
                    p_result := 'EXECUTING';
                    p_status := 'IN_PROGRESS';
                    p_response_payload := null;
                    rollback;
                    return;
                end if;
                raise;
        end;

        if l_existing_hash <> p_payload_hash then
            p_result := 'CONFLICT';
            p_status := l_status;
        elsif l_status = 'IN_PROGRESS' then
            p_result := 'EXECUTING';
            p_status := l_status;
        elsif l_status = 'FAILED_NO_SIDE_EFFECT'
              and p_response_payload is not null
              and dbms_lob.instr(p_response_payload, 'MFCS_BATCH_WINDOW_ACTIVE') > 0 then
            update office_mfcs_request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            p_result := 'RESUME';
            p_status := 'IN_PROGRESS';
        elsif l_status in ('COMPLETED', 'FAILED_NO_SIDE_EFFECT', 'MANUAL_REVIEW') then
            p_result := 'EXISTING';
            p_status := l_status;
        else
            update office_mfcs_request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            p_result := 'RESUME';
            p_status := 'IN_PROGRESS';
        end if;

        commit;
    end;

    procedure add_step(
        p_action_request_id in varchar2,
        p_step_code in varchar2,
        p_step_sequence in number
    ) is
    begin
        merge into office_mfcs_step s
        using (
            select p_action_request_id action_request_id,
                   p_step_code step_code,
                   p_step_sequence step_sequence
              from dual
        ) x
        on (s.action_request_id = x.action_request_id and s.step_code = x.step_code)
        when not matched then insert (
            action_request_id,
            step_code,
            step_sequence,
            step_status
        ) values (
            x.action_request_id,
            x.step_code,
            x.step_sequence,
            'PENDING'
        );
    end;

    procedure initialize_steps(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2
    ) is
    begin
        add_step(p_action_request_id, 'VALIDATE_REQUEST', 10);

        if p_operation_name in ('CREATE_STYLE', 'CREATE_ALL') then
            add_step(p_action_request_id, 'RESERVE_ITEM_NUMBERS', 20);
            add_step(p_action_request_id, 'CREATE_ITEM_HIERARCHY', 30);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 40);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 50);
            add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 60);
            add_step(p_action_request_id, 'APPROVE_ITEMS', 70);
        elsif p_operation_name = 'MODIFY_STYLE' then
            add_step(p_action_request_id, 'CREATE_ITEM_HIERARCHY', 30);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 40);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 50);
            add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 60);
            add_step(p_action_request_id, 'APPROVE_ITEMS', 70);
        end if;

        if p_operation_name = 'CREATE_ALL'
           and get_config('FEATURE_INITIAL_RETAIL_YN', 'N') = 'Y' then
            add_step(p_action_request_id, 'APPLY_INITIAL_RETAIL', 80);
        end if;

        if p_operation_name in ('CREATE_ORDER', 'CREATE_ALL') then
            add_step(p_action_request_id, 'RESERVE_ORDER_NUMBER', 90);
            add_step(p_action_request_id, 'CREATE_PURCHASE_ORDER', 100);
            add_step(p_action_request_id, 'VERIFY_PURCHASE_ORDER', 110);
        elsif p_operation_name = 'MODIFY_ORDER' then
            add_step(p_action_request_id, 'CREATE_PURCHASE_ORDER', 100);
            add_step(p_action_request_id, 'VERIFY_PURCHASE_ORDER', 110);
        end if;

        commit;
    end;

    function first_runnable_step(
        p_action_request_id in varchar2
    ) return varchar2 is
        l_step_code varchar2(60);
    begin
        select step_code
          into l_step_code
          from (
              select step_code
                from office_mfcs_step
               where action_request_id = p_action_request_id
                 and step_status in ('PENDING', 'FAILED', 'OUTCOME_UNKNOWN')
               order by step_sequence
          )
         where rownum = 1;

        return l_step_code;
    exception
        when no_data_found then
            return null;
    end;

    function step_succeeded(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from office_mfcs_step
         where action_request_id = p_action_request_id
           and step_code = p_step_code
           and step_status = 'SUCCEEDED';

        return l_count > 0;
    end;

    procedure set_request_status(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_response_payload  in clob default null
    ) is
    begin
        update office_mfcs_request
           set request_status = p_status,
               response_payload = case when p_response_payload is not null then p_response_payload else response_payload end,
               started_at = case when p_status = 'IN_PROGRESS' then coalesce(started_at, systimestamp) else started_at end,
               completed_at = case when p_status in ('COMPLETED', 'FAILED_NO_SIDE_EFFECT', 'MANUAL_REVIEW') then systimestamp else completed_at end,
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;

        commit;
    end;

    procedure set_step_status(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_status            in varchar2,
        p_entity_identifier in varchar2 default null,
        p_error_code        in varchar2 default null,
        p_error_message     in varchar2 default null
    ) is
    begin
        update office_mfcs_step
           set step_status = p_status,
               entity_identifier = coalesce(p_entity_identifier, entity_identifier),
               started_at = case when p_status = 'IN_PROGRESS' then coalesce(started_at, systimestamp) else started_at end,
               completed_at = case when p_status in ('SUCCEEDED', 'FAILED', 'OUTCOME_UNKNOWN', 'SKIPPED') then systimestamp else completed_at end,
               last_error_code = p_error_code,
               last_error_message = substr(p_error_message, 1, 4000)
         where action_request_id = p_action_request_id
           and step_code = p_step_code;

        commit;
    end;

    procedure save_generated_identifier(
        p_action_request_id   in varchar2,
        p_source_system       in varchar2,
        p_source_style_ref    in varchar2,
        p_mfcs_style_no       in varchar2,
        p_source_variant_ref  in varchar2 default null,
        p_mfcs_sku_no         in varchar2 default null,
        p_sku_size            in varchar2 default null,
        p_sku_width           in varchar2 default null,
        p_source_order_ref    in varchar2 default null,
        p_mfcs_order_no       in varchar2 default null
    ) is
    begin
        update office_mfcs_entity_map
           set mfcs_style_no = coalesce(p_mfcs_style_no, mfcs_style_no),
               mfcs_sku_no = coalesce(p_mfcs_sku_no, mfcs_sku_no),
               sku_size = coalesce(p_sku_size, sku_size),
               sku_width = coalesce(p_sku_width, sku_width),
               mfcs_order_no = coalesce(p_mfcs_order_no, mfcs_order_no),
               last_updated_at = systimestamp
         where source_system = p_source_system
           and nvl(source_style_ref, '-') = nvl(p_source_style_ref, '-')
           and nvl(source_variant_ref, '-') = nvl(p_source_variant_ref, '-')
           and nvl(source_order_ref, '-') = nvl(p_source_order_ref, '-');

        if sql%rowcount = 0 then
            insert into office_mfcs_entity_map (
                source_system,
                source_style_ref,
                mfcs_style_no,
                source_variant_ref,
                mfcs_sku_no,
                sku_size,
                sku_width,
                source_order_ref,
                mfcs_order_no
            ) values (
                p_source_system,
                p_source_style_ref,
                p_mfcs_style_no,
                p_source_variant_ref,
                p_mfcs_sku_no,
                p_sku_size,
                p_sku_width,
                p_source_order_ref,
                p_mfcs_order_no
            );
        end if;

        update office_mfcs_request
           set style_no = coalesce(p_mfcs_style_no, style_no),
               order_no = coalesce(p_mfcs_order_no, order_no),
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;

        commit;
    end;

    procedure begin_attempt(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        p_attempt_id        out number,
        p_correlation_id    out varchar2
    ) is
        l_attempt_number number;
        l_guid varchar2(32);
    begin
        select nvl(max(attempt_number), 0) + 1
          into l_attempt_number
          from office_mfcs_attempt
         where action_request_id = p_action_request_id
           and step_code = p_step_code;

        l_guid := lower(rawtohex(sys_guid()));
        p_correlation_id := substr(l_guid, 1, 8) || '-'
                         || substr(l_guid, 9, 4) || '-'
                         || substr(l_guid, 13, 4) || '-'
                         || substr(l_guid, 17, 4) || '-'
                         || substr(l_guid, 21);

        p_attempt_id := office_mfcs_attempt_seq.nextval;

        insert into office_mfcs_attempt (
            attempt_id,
            action_request_id,
            step_code,
            attempt_number,
            correlation_id,
            http_method,
            endpoint,
            request_payload,
            attempt_status
        ) values (
            p_attempt_id,
            p_action_request_id,
            p_step_code,
            l_attempt_number,
            p_correlation_id,
            p_http_method,
            p_endpoint,
            p_request_payload,
            'IN_PROGRESS'
        );

        commit;
    end;

    procedure complete_attempt(
        p_attempt_id       in number,
        p_attempt_status   in varchar2,
        p_http_status      in number default null,
        p_response_payload in clob default null
    ) is
    begin
        update office_mfcs_attempt
           set attempt_status = p_attempt_status,
               http_status = p_http_status,
               response_payload = p_response_payload,
               completed_at = systimestamp
         where attempt_id = p_attempt_id;

        commit;
    end;

    function build_status_response(
        p_action_request_id in varchar2,
        p_status_override   in varchar2 default null
    ) return clob is
        l_status varchar2(30);
        l_operation varchar2(30);
        l_style varchar2(30);
        l_order varchar2(30);
        l_failed_step varchar2(60);
        l_response clob;
        l_retryable varchar2(5);
        l_first boolean := true;
    begin
        select operation_name, request_status, style_no, order_no
          into l_operation, l_status, l_style, l_order
          from office_mfcs_request
         where action_request_id = p_action_request_id;

        l_status := nvl(p_status_override, l_status);

        l_retryable := case when l_status in ('PARTIALLY_COMPLETED', 'OUTCOME_UNKNOWN', 'FAILED_NO_SIDE_EFFECT') then 'true' else 'false' end;
        l_response := '{'
            || '"OPERATION_NAME":"' || json_escape(l_operation) || '",'
            || '"ACTION_REQUEST_ID":"' || json_escape(p_action_request_id) || '",'
            || '"STATUS":"' || json_escape(l_status) || '",'
            || '"RETRYABLE":' || l_retryable || ','
            || '"STYLE":' || case when l_style is null then 'null' else '"' || json_escape(l_style) || '"' end || ','
            || '"ORDER_NO":' || case when l_order is null then 'null' else '"' || json_escape(l_order) || '"' end || ','
            || '"PLMSizeCurveDtl":[';

        for l_request_row in (
            select source_variant_ref, sku_size, sku_width, mfcs_sku_no
              from office_mfcs_entity_map m
              join office_mfcs_request r
                on r.source_system = m.source_system
               and nvl(r.source_style_ref, '-') = nvl(m.source_style_ref, '-')
             where r.action_request_id = p_action_request_id
               and m.mfcs_sku_no is not null
             order by source_variant_ref
        ) loop
            if l_first then
                l_first := false;
            else
                l_response := l_response || ',';
            end if;

            l_response := l_response
                || '{"SOURCE_VARIANT_REF":"' || json_escape(l_request_row.source_variant_ref) || '",'
                || '"SKU_SIZE":"' || json_escape(l_request_row.sku_size) || '",'
                || '"SKU_WIDTH":"' || json_escape(l_request_row.sku_width) || '",'
                || '"SKU_ID":"' || json_escape(l_request_row.mfcs_sku_no) || '"}';
        end loop;

        l_response := l_response || '],"COMPLETED_STEPS":[';
        l_first := true;
        for l_step_row in (
            select step_code
              from office_mfcs_step
             where action_request_id = p_action_request_id
               and step_status = 'SUCCEEDED'
             order by step_sequence
        ) loop
            if l_first then
                l_first := false;
            else
                l_response := l_response || ',';
            end if;
            l_response := l_response || '"' || json_escape(l_step_row.step_code) || '"';
        end loop;

        l_response := l_response || '],"FAILED_STEP":';
        begin
            select step_code
              into l_failed_step
              from (
                  select step_code
                    from office_mfcs_step
                   where action_request_id = p_action_request_id
                     and step_status in ('FAILED', 'OUTCOME_UNKNOWN')
                   order by step_sequence
              )
             where rownum = 1;
            l_response := l_response || '"' || json_escape(l_failed_step) || '"';
        exception
            when no_data_found then
                l_response := l_response || 'null';
        end;

        l_response := l_response || ',"GENERATED_IDENTIFIERS":{'
            || '"STYLE":' || case when l_style is null then 'null' else '"' || json_escape(l_style) || '"' end
            || ',"ORDER_NO":' || case when l_order is null then 'null' else '"' || json_escape(l_order) || '"' end
            || '},"ERRORS":[]}';

        return l_response;
    end;
end office_mfcs_request_pkg;
/

create or replace package body office_mfcs_validation_pkg as
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
        return office_mfcs_request_pkg.get_config(p_key) is not null;
    end;

    function validate_request(
        p_payload in clob,
        p_errors  out clob
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
                p_errors := l_errors.to_clob;
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
                  from office_mfcs_entity_map
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
                  from office_mfcs_entity_map
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
            for l_variant_row in (
                select source_variant_ref, sku_id
                  from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
                      columns
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF' null on error,
                          sku_id varchar2(60) path '$.SKU_ID' null on error
                  )
            ) loop
                if trim(l_variant_row.sku_id) is null then
                    select count(*)
                      into l_count
                      from office_mfcs_entity_map
                     where source_system = l_source_system
                       and source_style_ref = l_source_style_ref
                       and source_variant_ref = l_variant_row.source_variant_ref
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

        for l_variant_row in (
            select sku_size, sku_width
              from json_table(p_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      sku_size varchar2(60) path '$.SKU_SIZE' null on error,
                      sku_width varchar2(60) path '$.SKU_WIDTH' null on error
              )
        ) loop
            if l_variant_row.sku_size is null or not has_config('MAP.SIZE.' || upper(l_variant_row.sku_size)) then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_SIZE', 'MAPPING_NOT_FOUND', 'Size mapping is not configured.');
            end if;

            if l_variant_row.sku_width is null or not has_config('MAP.WIDTH.' || upper(l_variant_row.sku_width)) then
                add_error(l_errors, 'PLMSizeCurveDtl.SKU_WIDTH', 'MAPPING_NOT_FOUND', 'Width mapping is not configured.');
            end if;
        end loop;

        if l_errors.get_size > 0 then
            p_errors := l_errors.to_clob;
            return false;
        end if;

        p_errors := '[]';
        return true;
    end;
end office_mfcs_validation_pkg;
/

create or replace package body office_mfcs_mapping_pkg as
    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;

        return l_payload;
    end;

    procedure assert_mapper_ready(p_mapper in varchar2) is
    begin
        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') not in ('MOCK', 'PUBLIC_MOCK', 'LOCAL_MFCS')
           and office_mfcs_request_pkg.get_config('MFCS_SCHEMA_READY_YN', 'N') <> 'Y' then
            raise_application_error(
                -20810,
                p_mapper || ' requires the authoritative Office MFCS OpenAPI schema before production payloads can be emitted.'
            );
        end if;
    end;

    function public_contract_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob is
        l_payload clob;
    begin
        execute immediate
            'begin :x := office_mfcs_public_contract_pkg.build_request(:a,:b); end;'
            using out l_payload, p_action_request_id, p_mapper_name;
        return l_payload;
    exception
        when others then
            raise_application_error(-20811, 'Public contract mapper is unavailable for ' || p_mapper_name || ': ' || sqlerrm);
    end;

    function use_public_contract return boolean is
    begin
        return office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') in ('PUBLIC_MOCK', 'LOCAL_MFCS');
    end;

    function source_system(p_payload in clob) return varchar2 is
        l_value varchar2(60);
    begin
        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function source_style_ref(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function source_order_ref(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select json_value(p_payload, '$.SOURCE_ORDER_REF' returning varchar2(120) null on error)
          into l_value
          from dual;
        return l_value;
    end;

    function user_id(p_payload in clob) return varchar2 is
        l_value varchar2(120);
    begin
        select coalesce(
                   json_value(p_payload, '$.USER_ID' returning varchar2(120) null on error),
                   json_value(p_payload, '$.APPROVED_BY' returning varchar2(120) null on error),
                   'OFFICE_MFCS_INTEGRATION'
               )
          into l_value
          from dual;
        return l_value;
    end;

    function envelope(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2,
        p_endpoint_key      in varchar2
    ) return clob is
        l_obj json_object_t := json_object_t();
        l_payload clob := request_payload(p_action_request_id);
    begin
        assert_mapper_ready(p_mapper_name);
        l_obj.put('mappingStatus', 'MOCK_OR_SCHEMA_PENDING');
        l_obj.put('mapperMethod', p_mapper_name);
        l_obj.put('endpointKey', p_endpoint_key);
        l_obj.put('actionRequestId', p_action_request_id);
        l_obj.put('sourcePayload', json_element_t.parse(l_payload));
        return l_obj.to_clob;
    end;

    function build_item_number_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_number_request');
        end if;
        return envelope(p_action_request_id, 'build_item_number_request', 'ENDPOINT.ITEM_NUMBERS_MANAGE');
    end;

    function build_item_create_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_create_request');
        end if;
        return envelope(p_action_request_id, 'build_item_create_request', 'ENDPOINT.ITEMS_CREATE');
    end;

    function build_item_sourcing_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_sourcing_request');
        end if;
        return envelope(p_action_request_id, 'build_item_sourcing_request', 'ENDPOINT.ITEM_SOURCING_CREATE');
    end;

    function build_item_uda_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_uda_request');
        end if;
        return envelope(p_action_request_id, 'build_item_uda_request', 'ENDPOINT.ITEM_UDAS_CREATE');
    end;

    function build_item_location_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_location_request');
        end if;
        return envelope(p_action_request_id, 'build_item_location_request', 'ENDPOINT.ITEM_LOCATIONS_CREATE');
    end;

    function build_item_approval_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_item_approval_request');
        end if;
        return envelope(p_action_request_id, 'build_item_approval_request', 'ENDPOINT.ITEM_APPROVE');
    end;

    function build_initial_retail_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_initial_retail_request');
        end if;
        return envelope(p_action_request_id, 'build_initial_retail_request', 'ENDPOINT.INITIAL_RETAIL');
    end;

    function build_po_number_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_po_number_request');
        end if;
        return envelope(p_action_request_id, 'build_po_number_request', 'ENDPOINT.PO_PREISSUED_CREATE');
    end;

    function build_purchase_order_request(p_action_request_id in varchar2) return clob is
        l_obj json_object_t;
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_purchase_order_request');
        end if;
        l_obj := json_object_t.parse(envelope(p_action_request_id, 'build_purchase_order_request', 'ENDPOINT.PURCHASE_ORDERS_CREATE'));
        l_obj.put('dataLoadingDestination', 'RMS');
        return l_obj.to_clob;
    end;

    function build_purchase_order_verify_request(p_action_request_id in varchar2) return clob is
    begin
        if use_public_contract then
            return public_contract_request(p_action_request_id, 'build_purchase_order_verify_request');
        end if;
        return envelope(p_action_request_id, 'build_purchase_order_verify_request', 'ENDPOINT.PURCHASE_ORDER_GET');
    end;
end office_mfcs_mapping_pkg;
/

create or replace package body office_mfcs_client_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_MFCS_CLIENT_PKG';
    g_access_token varchar2(4000);
    g_token_expires_at timestamp with time zone;

    function get_secret(p_secret_ref in varchar2) return varchar2 is
        l_secret varchar2(4000);
    begin
        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') in ('PUBLIC_MOCK', 'LOCAL_MFCS') then
            return 'public-mock-client-secret';
        end if;

        l_secret := sys_context('OFFICE_MFCS_CTX', p_secret_ref);

        if l_secret is null then
            raise_application_error(
                -20890,
                'MFCS secret retrieval is not configured. Replace office_mfcs_client_pkg.get_secret with the approved RDS secret-store integration.'
            );
        end if;

        return l_secret;
    end;

    function wallet_path return varchar2 is
    begin
        return office_mfcs_request_pkg.get_config('MFCS_WALLET_PATH', null);
    end;

    function wallet_password return varchar2 is
        l_secret_ref varchar2(200);
    begin
        l_secret_ref := office_mfcs_request_pkg.get_config('MFCS_WALLET_PASSWORD_REF', null);
        if l_secret_ref is null then
            return null;
        end if;
        return get_secret(l_secret_ref);
    end;

    function https_host return varchar2 is
    begin
        return office_mfcs_request_pkg.get_config('MFCS_HTTPS_HOST', null);
    end;

    function local_resource(p_endpoint_key in varchar2) return varchar2 is
    begin
        return case p_endpoint_key
            when 'ENDPOINT.ITEM_NUMBERS_MANAGE' then 'RESERVE_ITEM_NUMBERS'
            when 'ENDPOINT.ITEMS_CREATE' then 'ITEMS'
            when 'ENDPOINT.ITEMS_UPDATE' then 'ITEMS_UPDATE'
            when 'ENDPOINT.ITEM_APPROVE' then 'ITEMS_UPDATE'
            when 'ENDPOINT.INITIAL_RETAIL' then 'ITEMS_UPDATE'
            when 'ENDPOINT.ITEM_SOURCING_CREATE' then 'ITEM_SUPPLIERS'
            when 'ENDPOINT.ITEM_SOURCING_UPDATE' then 'ITEM_SUPPLIERS'
            when 'ENDPOINT.ITEM_UDAS_CREATE' then 'ITEM_UDAS'
            when 'ENDPOINT.ITEM_UDAS_UPDATE' then 'ITEM_UDAS'
            when 'ENDPOINT.ITEM_LOCATIONS_CREATE' then 'ITEM_LOCATIONS'
            when 'ENDPOINT.ITEM_LOCATIONS_UPDATE' then 'ITEM_LOCATIONS'
            when 'ENDPOINT.PO_PREISSUED_CREATE' then 'RESERVE_ORDER_NUMBERS'
            when 'ENDPOINT.PURCHASE_ORDERS_CREATE' then 'PURCHASE_ORDERS'
            when 'ENDPOINT.PURCHASE_ORDERS_UPDATE' then 'PURCHASE_ORDERS'
            when 'ENDPOINT.PURCHASE_ORDER_GET' then 'GET_ORDER'
            else null
        end;
    end;

    function access_token return varchar2 is
        l_token_url varchar2(1000);
        l_client_id varchar2(4000);
        l_client_secret varchar2(4000);
        l_secret_ref varchar2(200);
        l_scope varchar2(4000);
        l_response clob;
        l_expires_in number;
    begin
        if g_access_token is not null
           and g_token_expires_at > systimestamp + interval '60' second then
            return g_access_token;
        end if;

        l_token_url := office_mfcs_request_pkg.get_config('MFCS_TOKEN_URL');
        l_client_id := office_mfcs_request_pkg.get_config('MFCS_CLIENT_ID');
        l_secret_ref := office_mfcs_request_pkg.get_config('MFCS_CLIENT_SECRET_REF');
        l_scope := office_mfcs_request_pkg.get_config('MFCS_SCOPE');
        l_client_secret := get_secret(l_secret_ref);

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/x-www-form-urlencoded';
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';

        l_response := apex_web_service.make_rest_request(
            p_url => l_token_url,
            p_http_method => 'POST',
            p_body => 'grant_type=client_credentials'
                   || '&client_id=' || l_client_id
                   || '&client_secret=' || l_client_secret
                   || '&scope=' || l_scope,
            p_wallet_path => wallet_path,
            p_wallet_pwd => wallet_password,
            p_https_host => https_host,
            p_transfer_timeout => to_number(office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );

        select json_value(l_response, '$.access_token' returning varchar2(4000) null on error),
               json_value(l_response, '$.expires_in' returning number default 300 on error)
          into g_access_token, l_expires_in
          from dual;

        if g_access_token is null then
            raise_application_error(-20951, 'OAuth token endpoint did not return access_token.');
        end if;

        g_token_expires_at := systimestamp + numtodsinterval(greatest(l_expires_in - 60, 60), 'SECOND');
        l_client_secret := null;
        return g_access_token;
    end;

    function call_mock(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        p_correlation_id    in varchar2,
        p_user_id           in varchar2
    ) return clob is
        l_response clob;
    begin
        execute immediate
            'begin :x := office_mfcs_mock_pkg.invoke(:a,:b,:c,:d,:e,:f,:g); end;'
            using out l_response,
                  p_action_request_id,
                  p_step_code,
                  p_http_method,
                  p_endpoint,
                  p_request_payload,
                  p_correlation_id,
                  p_user_id;
        return l_response;
    end;

    function call_service(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint_key      in varchar2,
        p_request_payload   in clob,
        p_user_id           in varchar2
    ) return clob is
        l_endpoint_path varchar2(1000);
        l_endpoint varchar2(1000);
        l_base_url varchar2(1000);
        l_attempt_id number;
        l_correlation_id varchar2(80);
        l_response clob;
        l_http_status number;
        l_mock_attempt_status varchar2(30);
        l_order_no varchar2(30);
        l_local_resource varchar2(100);
        l_error_code number;
        l_error_message varchar2(4000);
    begin
        office_mfcs_log_pkg.info(
            c_package_name, 'CALL_SERVICE', p_action_request_id,
            p_step_code || ' -> ' || p_endpoint_key
        );
        l_base_url := office_mfcs_request_pkg.get_config('MFCS_BASE_URL');
        l_endpoint_path := office_mfcs_request_pkg.get_config(p_endpoint_key);

        if instr(l_endpoint_path, '{orderNo}') > 0 then
            select order_no
              into l_order_no
              from office_mfcs_request
             where action_request_id = p_action_request_id;
            l_endpoint_path := replace(l_endpoint_path, '{orderNo}', l_order_no);
        end if;

        l_endpoint := rtrim(l_base_url, '/') || l_endpoint_path;

        office_mfcs_request_pkg.begin_attempt(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => p_http_method,
            p_endpoint => l_endpoint,
            p_request_payload => p_request_payload,
            p_attempt_id => l_attempt_id,
            p_correlation_id => l_correlation_id
        );

        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') = 'MOCK' then
            l_response := call_mock(
                p_action_request_id,
                p_step_code,
                p_http_method,
                l_endpoint,
                p_request_payload,
                l_correlation_id,
                p_user_id
            );

            select json_value(l_response, '$.mock.httpStatus' returning number default 200 on error),
                   json_value(l_response, '$.mock.attemptStatus' returning varchar2(30) default 'SUCCEEDED' on error)
              into l_http_status, l_mock_attempt_status
              from dual;

            if l_mock_attempt_status = 'OUTCOME_UNKNOWN' then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'OUTCOME_UNKNOWN', l_http_status, l_response);
                raise_application_error(-20952, 'MFCS call timed out after request was sent.');
            elsif l_http_status >= 500 then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
                raise_application_error(-20950, 'MFCS downstream failure at ' || p_endpoint_key);
            elsif l_http_status >= 400 then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
                raise_application_error(-20950, 'MFCS rejected request at ' || p_endpoint_key);
            end if;

            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
            office_mfcs_log_pkg.info(c_package_name, 'CALL_SERVICE', p_action_request_id, p_step_code || ' completed');
            return l_response;
        end if;

        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') = 'LOCAL_MFCS' then
            l_local_resource := local_resource(p_endpoint_key);
            if l_local_resource is null then
                raise_application_error(-20950, 'Local MFCS resource mapping is missing for ' || p_endpoint_key);
            end if;
            execute immediate
                'begin local_mfcs_service_pkg.handle(:a,:b,:c,:d,:e,null,:f,:g); end;'
                using l_local_resource,
                      p_http_method,
                      p_request_payload,
                      l_correlation_id,
                      l_order_no,
                      out l_http_status,
                      out l_response;
            if l_http_status between 200 and 299 then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
                office_mfcs_log_pkg.info(c_package_name, 'CALL_SERVICE', p_action_request_id, p_step_code || ' completed');
                return l_response;
            end if;
            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20950, 'Local MFCS rejected request at ' || p_endpoint_key);
        end if;

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || access_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';
        apex_web_service.g_request_headers(3).name := 'Content-Type';
        apex_web_service.g_request_headers(3).value := 'application/json';
        apex_web_service.g_request_headers(4).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(4).value := l_correlation_id;
        apex_web_service.g_request_headers(5).name := 'X-Client-Principal-User';
        apex_web_service.g_request_headers(5).value := p_user_id;

        l_response := apex_web_service.make_rest_request(
            p_url => l_endpoint,
            p_http_method => p_http_method,
            p_body => p_request_payload,
            p_wallet_path => wallet_path,
            p_wallet_pwd => wallet_password,
            p_https_host => https_host,
            p_transfer_timeout => to_number(office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );
        l_http_status := apex_web_service.g_status_code;

        if l_http_status between 200 and 299 then
            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
            office_mfcs_log_pkg.info(c_package_name, 'CALL_SERVICE', p_action_request_id, p_step_code || ' completed');
            return l_response;
        elsif l_http_status = 503 then
            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20951, 'MFCS service unavailable at ' || p_endpoint_key);
        else
            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20950, 'MFCS returned HTTP ' || l_http_status || ' at ' || p_endpoint_key);
        end if;
    exception
        when others then
            l_error_code := sqlcode;
            l_error_message := sqlerrm;
            office_mfcs_log_pkg.error(
                c_package_name, 'CALL_SERVICE', p_action_request_id,
                p_step_code || ' failed', l_error_message
            );

            if l_error_code in (-20950, -20951, -20952) then
                raise;
            end if;

            if instr(lower(l_error_message), 'timeout') > 0 then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'OUTCOME_UNKNOWN', null, '{"ERROR":"' || replace(l_error_message, '"', '\"') || '"}');
                raise_application_error(-20952, 'MFCS timeout after request was sent.');
            end if;

            if l_attempt_id is not null then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', null, '{"ERROR":"' || replace(l_error_message, '"', '\"') || '"}');
            end if;
            raise_application_error(-20950, l_error_message);
    end;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob is
        l_response clob;
        l_endpoint varchar2(1000);
        l_http_status number;
    begin
        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') = 'MOCK' then
            execute immediate
                'begin :x := office_mfcs_mock_pkg.correlation_status(:a,:b); end;'
                using out l_response, p_action_request_id, p_correlation_id;
            return l_response;
        end if;

        if office_mfcs_request_pkg.get_config('MFCS_CLIENT_MODE', 'MOCK') = 'LOCAL_MFCS' then
            execute immediate
                'begin local_mfcs_service_pkg.handle(''GET_STATUS'',''GET'',null,:a,null,:b,:c,:d); end;'
                using lower(rawtohex(sys_guid())), p_correlation_id, out l_http_status, out l_response;
            return l_response;
        end if;

        l_endpoint := rtrim(office_mfcs_request_pkg.get_config('MFCS_BASE_URL'), '/')
            || office_mfcs_request_pkg.get_config('ENDPOINT.REST_SERVICE_STATUS')
            || '?xCorrelationId=' || p_correlation_id
            || '&includePayload=Y';

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || access_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';

        l_response := apex_web_service.make_rest_request(
            p_url => l_endpoint,
            p_http_method => 'GET',
            p_wallet_path => wallet_path,
            p_wallet_pwd => wallet_password,
            p_https_host => https_host,
            p_transfer_timeout => to_number(office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );

        return l_response;
    end;
end office_mfcs_client_pkg;
/

create or replace package body office_mfcs_recovery_pkg as
    function resolve_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return varchar2 is
        l_correlation_id varchar2(80);
        l_status_response clob;
        l_status varchar2(30);
        l_response_code number;
        l_result_count number;
    begin
        select correlation_id
          into l_correlation_id
          from (
              select correlation_id
                from office_mfcs_attempt
               where action_request_id = p_action_request_id
                 and step_code = p_step_code
                 and attempt_status = 'OUTCOME_UNKNOWN'
               order by attempt_number desc
          )
         where rownum = 1;

        l_status_response := office_mfcs_client_pkg.correlation_status(p_action_request_id, l_correlation_id);

        select json_value(l_status_response, '$.status' returning varchar2(30) null on error),
               json_value(l_status_response, '$.items[0].responseCode' returning number null on error),
               json_value(l_status_response, '$.count' returning number null on error)
          into l_status, l_response_code, l_result_count
          from dual;

        if l_status is null then
            if nvl(l_result_count, 0) = 0 then
                l_status := 'NO_RECORD';
            elsif l_response_code between 200 and 299 then
                l_status := 'SUCCESS';
            elsif l_response_code >= 400 then
                l_status := 'FAILURE';
            else
                l_status := 'UNKNOWN';
            end if;
        end if;

        if l_status = 'SUCCESS' then
            office_mfcs_request_pkg.set_step_status(p_action_request_id, p_step_code, 'SUCCEEDED');
            return 'SUCCEEDED';
        elsif l_status = 'FAILURE' then
            office_mfcs_request_pkg.set_step_status(p_action_request_id, p_step_code, 'FAILED', null, 'MFCS_REPORTED_FAILURE', 'MFCS operation-status service reported failure.');
            return 'FAILED';
        elsif l_status = 'NO_RECORD' then
            office_mfcs_request_pkg.set_step_status(p_action_request_id, p_step_code, 'PENDING');
            return 'NO_RECORD';
        else
            office_mfcs_request_pkg.set_step_status(p_action_request_id, p_step_code, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', 'MFCS operation outcome is still ambiguous.');
            office_mfcs_request_pkg.set_request_status(p_action_request_id, 'MANUAL_REVIEW', office_mfcs_request_pkg.build_status_response(p_action_request_id, 'MANUAL_REVIEW'));
            return 'MANUAL_REVIEW';
        end if;
    exception
        when no_data_found then
            return 'NO_UNKNOWN_ATTEMPT';
    end;
end office_mfcs_recovery_pkg;
/

create or replace package body office_mfcs_orchestrator_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_MFCS_ORCHESTRATOR_PKG';

    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_payload;
    end;

    function operation_name(p_action_request_id in varchar2) return varchar2 is
        l_operation varchar2(30);
    begin
        select operation_name
          into l_operation
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_operation;
    end;

    function any_succeeded(p_action_request_id in varchar2) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from office_mfcs_step
         where action_request_id = p_action_request_id
           and step_status = 'SUCCEEDED'
           and step_code <> 'VALIDATE_REQUEST';
        return l_count > 0;
    end;

    procedure persist_item_numbers(
        p_action_request_id in varchar2,
        p_response          in clob
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_source_system varchar2(60) := office_mfcs_mapping_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := office_mfcs_mapping_pkg.source_style_ref(l_payload);
        l_style_no varchar2(30);
        l_sku_no varchar2(30);
        l_response_obj json_object_t;
        l_items json_array_t;
    begin
        select coalesce(
                   json_value(p_response, '$.STYLE' returning varchar2(30) null on error),
                   json_value(p_response, '$.items[0].item' returning varchar2(30) null on error)
               )
          into l_style_no
          from dual;

        office_mfcs_request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => l_source_system,
            p_source_style_ref => l_source_style_ref,
            p_mfcs_style_no => l_style_no
        );

        l_response_obj := json_object_t.parse(p_response);
        if l_response_obj.has('items') then
            l_items := l_response_obj.get_array('items');
            for l_variant_row in (
                select ordinality, source_variant_ref, sku_size, sku_width
                  from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                      columns
                          ordinality for ordinality,
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH'
                  )
            ) loop
                l_sku_no := treat(l_items.get(l_variant_row.ordinality) as json_object_t).get_string('item');
                office_mfcs_request_pkg.save_generated_identifier(
                    p_action_request_id => p_action_request_id,
                    p_source_system => l_source_system,
                    p_source_style_ref => l_source_style_ref,
                    p_mfcs_style_no => l_style_no,
                    p_source_variant_ref => l_variant_row.source_variant_ref,
                    p_mfcs_sku_no => l_sku_no,
                    p_sku_size => l_variant_row.sku_size,
                    p_sku_width => l_variant_row.sku_width
                );
            end loop;
        else
            for l_variant_row in (
                select source_variant_ref, sku_size, sku_width, sku_id
                  from json_table(p_response, '$.PLMSizeCurveDtl[*]'
                      columns
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH',
                          sku_id varchar2(30) path '$.SKU_ID'
                  )
            ) loop
                office_mfcs_request_pkg.save_generated_identifier(
                    p_action_request_id => p_action_request_id,
                    p_source_system => l_source_system,
                    p_source_style_ref => l_source_style_ref,
                    p_mfcs_style_no => l_style_no,
                    p_source_variant_ref => l_variant_row.source_variant_ref,
                    p_mfcs_sku_no => l_variant_row.sku_id,
                    p_sku_size => l_variant_row.sku_size,
                    p_sku_width => l_variant_row.sku_width
                );
            end loop;
        end if;
    end;

    procedure persist_po_number(
        p_action_request_id in varchar2,
        p_response          in clob
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_order_no varchar2(30);
    begin
        select coalesce(
                   json_value(p_response, '$.ORDER_NO' returning varchar2(30) null on error),
                   json_value(p_response, '$.orderNumbers[0].orderNo' returning varchar2(30) null on error)
               )
          into l_order_no
          from dual;

        office_mfcs_request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => office_mfcs_mapping_pkg.source_system(l_payload),
            p_source_style_ref => office_mfcs_mapping_pkg.source_style_ref(l_payload),
            p_mfcs_style_no => null,
            p_source_order_ref => office_mfcs_mapping_pkg.source_order_ref(l_payload),
            p_mfcs_order_no => l_order_no
        );
    end;

    function payload_for_step(
        p_action_request_id in varchar2,
        p_step_code in varchar2
    ) return clob is
    begin
        case p_step_code
            when 'RESERVE_ITEM_NUMBERS' then return office_mfcs_mapping_pkg.build_item_number_request(p_action_request_id);
            when 'CREATE_ITEM_HIERARCHY' then return office_mfcs_mapping_pkg.build_item_create_request(p_action_request_id);
            when 'CREATE_ITEM_SOURCING' then return office_mfcs_mapping_pkg.build_item_sourcing_request(p_action_request_id);
            when 'CREATE_ITEM_UDAS' then return office_mfcs_mapping_pkg.build_item_uda_request(p_action_request_id);
            when 'CREATE_ITEM_LOCATIONS' then return office_mfcs_mapping_pkg.build_item_location_request(p_action_request_id);
            when 'APPROVE_ITEMS' then return office_mfcs_mapping_pkg.build_item_approval_request(p_action_request_id);
            when 'APPLY_INITIAL_RETAIL' then return office_mfcs_mapping_pkg.build_initial_retail_request(p_action_request_id);
            when 'RESERVE_ORDER_NUMBER' then return office_mfcs_mapping_pkg.build_po_number_request(p_action_request_id);
            when 'CREATE_PURCHASE_ORDER' then return office_mfcs_mapping_pkg.build_purchase_order_request(p_action_request_id);
            when 'VERIFY_PURCHASE_ORDER' then return office_mfcs_mapping_pkg.build_purchase_order_verify_request(p_action_request_id);
            else return '{"step":"' || p_step_code || '"}';
        end case;
    end;

    function endpoint_for_step(p_step_code in varchar2, p_operation in varchar2) return varchar2 is
    begin
        case p_step_code
            when 'RESERVE_ITEM_NUMBERS' then return 'ENDPOINT.ITEM_NUMBERS_MANAGE';
            when 'CREATE_ITEM_HIERARCHY' then
                if p_operation = 'MODIFY_STYLE' then
                    return 'ENDPOINT.ITEMS_UPDATE';
                end if;
                return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_ITEM_SOURCING' then
                if p_operation = 'MODIFY_STYLE' then return 'ENDPOINT.ITEM_SOURCING_UPDATE'; end if;
                return 'ENDPOINT.ITEM_SOURCING_CREATE';
            when 'CREATE_ITEM_UDAS' then
                if p_operation = 'MODIFY_STYLE' then return 'ENDPOINT.ITEM_UDAS_UPDATE'; end if;
                return 'ENDPOINT.ITEM_UDAS_CREATE';
            when 'CREATE_ITEM_LOCATIONS' then
                if p_operation = 'MODIFY_STYLE' then return 'ENDPOINT.ITEM_LOCATIONS_UPDATE'; end if;
                return 'ENDPOINT.ITEM_LOCATIONS_CREATE';
            when 'APPROVE_ITEMS' then return 'ENDPOINT.ITEM_APPROVE';
            when 'APPLY_INITIAL_RETAIL' then return 'ENDPOINT.INITIAL_RETAIL';
            when 'RESERVE_ORDER_NUMBER' then return 'ENDPOINT.PO_PREISSUED_CREATE';
            when 'CREATE_PURCHASE_ORDER' then
                if p_operation = 'MODIFY_ORDER' then return 'ENDPOINT.PURCHASE_ORDERS_UPDATE'; end if;
                return 'ENDPOINT.PURCHASE_ORDERS_CREATE';
            when 'VERIFY_PURCHASE_ORDER' then return 'ENDPOINT.PURCHASE_ORDER_GET';
            else return null;
        end case;
    end;

    function method_for_step(p_step_code in varchar2, p_operation in varchar2) return varchar2 is
    begin
        if p_step_code = 'VERIFY_PURCHASE_ORDER' then
            return 'GET';
        elsif p_operation = 'MODIFY_STYLE'
              and p_step_code in ('CREATE_ITEM_HIERARCHY', 'CREATE_ITEM_SOURCING', 'CREATE_ITEM_UDAS', 'CREATE_ITEM_LOCATIONS', 'APPROVE_ITEMS') then
            return 'PUT';
        elsif p_step_code = 'CREATE_PURCHASE_ORDER' and p_operation = 'MODIFY_ORDER' then
            return 'PUT';
        end if;
        return 'POST';
    end;

    procedure execute_request(
        p_action_request_id in varchar2
    ) is
        l_step varchar2(60);
        l_operation varchar2(30) := operation_name(p_action_request_id);
        l_payload clob := request_payload(p_action_request_id);
        l_user_id varchar2(120) := office_mfcs_mapping_pkg.user_id(l_payload);
        l_request_payload clob;
        l_response clob;
        l_endpoint_key varchar2(200);
        l_method varchar2(10);
        l_recovery_status varchar2(30);
        l_started_at timestamp with time zone := systimestamp;
        l_budget_seconds number := to_number(office_mfcs_request_pkg.get_config('INTERNAL_TIME_BUDGET_SECONDS', '240'));
        l_error_code number;
        l_error_message varchar2(4000);
    begin
        office_mfcs_log_pkg.info(c_package_name, 'EXECUTE_REQUEST', p_action_request_id, 'Integration orchestration started');
        if l_operation = 'CREATE_ALL'
           and office_mfcs_request_pkg.get_config('BATCH_WINDOW_ACTIVE_YN', 'N') = 'Y'
           and not any_succeeded(p_action_request_id) then
            office_mfcs_request_pkg.set_request_status(
                p_action_request_id,
                'FAILED_NO_SIDE_EFFECT',
                '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"MFCS_BATCH_WINDOW","CODE":"MFCS_BATCH_WINDOW_ACTIVE","MESSAGE":"Required MFCS services are unavailable during the configured batch window."}]}'
            );
            return;
        end if;

        office_mfcs_request_pkg.set_request_status(p_action_request_id, 'IN_PROGRESS');
        office_mfcs_request_pkg.set_step_status(p_action_request_id, 'VALIDATE_REQUEST', 'SUCCEEDED');

        loop
            l_step := office_mfcs_request_pkg.first_runnable_step(p_action_request_id);
            exit when l_step is null;

            if l_step = 'VALIDATE_REQUEST' then
                office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                continue;
            end if;

            if (cast(systimestamp as date) - cast(l_started_at as date)) * 86400 >= l_budget_seconds then
                office_mfcs_request_pkg.set_request_status(
                    p_action_request_id,
                    case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end,
                    office_mfcs_request_pkg.build_status_response(
                        p_action_request_id,
                        case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end
                    )
                );
                return;
            end if;

            select step_status
              into l_recovery_status
              from office_mfcs_step
             where action_request_id = p_action_request_id
               and step_code = l_step;

            if l_recovery_status = 'OUTCOME_UNKNOWN' then
                l_recovery_status := office_mfcs_recovery_pkg.resolve_step(p_action_request_id, l_step);
                if l_recovery_status = 'SUCCEEDED' then
                    continue;
                elsif l_recovery_status = 'MANUAL_REVIEW' then
                    return;
                end if;
            end if;

            l_endpoint_key := endpoint_for_step(l_step, l_operation);
            l_method := method_for_step(l_step, l_operation);
            l_request_payload := payload_for_step(p_action_request_id, l_step);

            office_mfcs_log_pkg.info(c_package_name, 'EXECUTE_STEP', p_action_request_id, l_step || ' started');
            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'IN_PROGRESS');
            l_response := office_mfcs_client_pkg.call_service(
                p_action_request_id => p_action_request_id,
                p_step_code => l_step,
                p_http_method => l_method,
                p_endpoint_key => l_endpoint_key,
                p_request_payload => l_request_payload,
                p_user_id => l_user_id
            );

            if l_step = 'RESERVE_ITEM_NUMBERS' then
                persist_item_numbers(p_action_request_id, l_response);
            elsif l_step = 'RESERVE_ORDER_NUMBER' then
                persist_po_number(p_action_request_id, l_response);
            end if;

            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
            office_mfcs_log_pkg.info(c_package_name, 'EXECUTE_STEP', p_action_request_id, l_step || ' completed');
        end loop;

        office_mfcs_request_pkg.set_request_status(
            p_action_request_id,
            'COMPLETED',
            office_mfcs_request_pkg.build_status_response(p_action_request_id, 'COMPLETED')
        );
        office_mfcs_log_pkg.info(c_package_name, 'EXECUTE_REQUEST', p_action_request_id, 'Integration orchestration completed');
    exception
        when office_mfcs_client_pkg.e_outcome_unknown then
            l_error_message := sqlerrm;
            office_mfcs_log_pkg.error(c_package_name, 'EXECUTE_REQUEST', p_action_request_id, l_step || ' outcome is unknown', l_error_message);
            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', l_error_message);
            office_mfcs_request_pkg.set_request_status(p_action_request_id, 'OUTCOME_UNKNOWN', office_mfcs_request_pkg.build_status_response(p_action_request_id, 'OUTCOME_UNKNOWN'));
        when others then
            l_error_code := sqlcode;
            l_error_message := sqlerrm;
            office_mfcs_log_pkg.error(c_package_name, 'EXECUTE_REQUEST', p_action_request_id, coalesce(l_step, 'REQUEST') || ' failed', l_error_message);
            if l_step is not null then
                office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'FAILED', null, to_char(l_error_code), l_error_message);
            end if;

            if any_succeeded(p_action_request_id) then
                office_mfcs_request_pkg.set_request_status(p_action_request_id, 'PARTIALLY_COMPLETED', office_mfcs_request_pkg.build_status_response(p_action_request_id, 'PARTIALLY_COMPLETED'));
            else
                office_mfcs_request_pkg.set_request_status(
                    p_action_request_id,
                    'FAILED_NO_SIDE_EFFECT',
                    '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":"' || l_step || '","GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"' || l_step || '","CODE":"' || l_error_code || '","MESSAGE":"' || replace(l_error_message, '"', '\"') || '"}]}'
                );
            end if;
    end;

    procedure resume_request(
        p_action_request_id in varchar2
    ) is
    begin
        execute_request(p_action_request_id);
    end;
end office_mfcs_orchestrator_pkg;
/

create or replace package body office_mfcs_api_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_MFCS_API_PKG';

    function simple_error(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_retryable         in varchar2,
        p_field             in varchar2,
        p_code              in varchar2,
        p_message           in varchar2
    ) return clob is
    begin
        return '{"ACTION_REQUEST_ID":' || case when p_action_request_id is null then 'null' else '"' || replace(p_action_request_id, '"', '\"') || '"' end
            || ',"STATUS":"' || p_status || '","RETRYABLE":' || p_retryable
            || ',"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{}'
            || ',"ERRORS":[{"FIELD":"' || replace(p_field, '"', '\"') || '","CODE":"' || replace(p_code, '"', '\"') || '","MESSAGE":"' || replace(p_message, '"', '\"') || '"}]}';
    end;

    function status_to_http(p_status in varchar2) return number is
    begin
        case p_status
            when 'COMPLETED' then return 200;
            when 'PARTIALLY_COMPLETED' then return 502;
            when 'OUTCOME_UNKNOWN' then return 503;
            when 'MANUAL_REVIEW' then return 503;
            when 'FAILED_NO_SIDE_EFFECT' then return 422;
            when 'IN_PROGRESS' then return 409;
            else return 200;
        end case;
    end;

    function response_status_to_http(
        p_status in varchar2,
        p_response in clob
    ) return number is
    begin
        if p_status = 'FAILED_NO_SIDE_EFFECT'
           and p_response is not null
           and dbms_lob.instr(p_response, 'MFCS_BATCH_WINDOW_ACTIVE') > 0 then
            return 503;
        end if;

        return status_to_http(p_status);
    end;

    procedure submit_transaction(
        p_payload      in clob,
        p_http_status  out number,
        p_response     out clob
    ) is
        l_action_request_id varchar2(80);
        l_operation varchar2(30);
        l_hash varchar2(64);
        l_result varchar2(30);
        l_status varchar2(30);
        l_existing_response clob;
        l_errors clob;
        l_valid boolean;
        l_parsed json_element_t;
    begin
        begin
            l_parsed := json_element_t.parse(p_payload);
        exception
            when others then
                office_mfcs_log_pkg.error(c_package_name, 'SUBMIT_TRANSACTION', null, 'Invalid JSON payload', sqlerrm);
                p_http_status := 400;
                p_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', '$', 'INVALID_JSON', sqlerrm);
                return;
        end;

        select json_value(p_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error),
               json_value(p_payload, '$.OPERATION_NAME' returning varchar2(30) null on error)
          into l_action_request_id, l_operation
          from dual;

        office_mfcs_log_pkg.info(c_package_name, 'SUBMIT_TRANSACTION', l_action_request_id, coalesce(l_operation, 'UNKNOWN') || ' received');

        if trim(l_action_request_id) is null then
            p_http_status := 400;
            p_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'REQUIRED', 'ACTION_REQUEST_ID is required.');
            return;
        end if;

        if trim(l_operation) is null then
            p_http_status := 400;
            p_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'OPERATION_NAME', 'REQUIRED', 'OPERATION_NAME is required.');
            return;
        elsif l_operation not in ('CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            p_http_status := 400;
            p_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'OPERATION_NAME', 'UNSUPPORTED_OPERATION', 'Unsupported OPERATION_NAME.');
            return;
        end if;

        l_hash := office_mfcs_request_pkg.payload_hash(p_payload);
        office_mfcs_request_pkg.register_request(
            p_action_request_id => l_action_request_id,
            p_operation_name => l_operation,
            p_payload_hash => l_hash,
            p_payload => p_payload,
            p_result => l_result,
            p_status => l_status,
            p_response_payload => l_existing_response
        );

        if l_result = 'CONFLICT' then
            p_http_status := 409;
            p_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'IDEMPOTENCY_CONFLICT', 'ACTION_REQUEST_ID already exists with a different business payload hash.');
            return;
        elsif l_result = 'EXECUTING' then
            p_http_status := 409;
            p_response := simple_error(l_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            return;
        elsif l_result = 'EXISTING' and l_existing_response is not null then
            p_http_status := response_status_to_http(l_status, l_existing_response);
            p_response := l_existing_response;
            return;
        end if;

        l_valid := office_mfcs_validation_pkg.validate_request(p_payload, l_errors);

        if not l_valid then
            p_response := '{"ACTION_REQUEST_ID":"' || replace(l_action_request_id, '"', '\"') || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":false,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":' || l_errors || '}';
            office_mfcs_request_pkg.set_request_status(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', p_response);
            p_http_status := 422;
            return;
        end if;

        office_mfcs_request_pkg.initialize_steps(l_action_request_id, l_operation);
        office_mfcs_request_pkg.set_request_status(l_action_request_id, 'VALIDATED');
        office_mfcs_orchestrator_pkg.execute_request(l_action_request_id);

        select request_status, response_payload
          into l_status, l_existing_response
          from office_mfcs_request
         where action_request_id = l_action_request_id;

        if l_existing_response is not null then
            p_response := l_existing_response;
        else
            p_response := office_mfcs_request_pkg.build_status_response(l_action_request_id);
        end if;

        p_http_status := response_status_to_http(l_status, p_response);
        office_mfcs_log_pkg.info(c_package_name, 'SUBMIT_TRANSACTION', l_action_request_id, 'Completed with status ' || l_status);
    exception
        when others then
            office_mfcs_log_pkg.error(c_package_name, 'SUBMIT_TRANSACTION', l_action_request_id, 'Unhandled integration error', sqlerrm);
            p_http_status := 500;
            p_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'true', 'INTEGRATION', to_char(sqlcode), sqlerrm);
    end;

    procedure validate_transaction(
        p_payload      in clob,
        p_http_status  out number,
        p_response     out clob
    ) is
        l_action_request_id varchar2(80);
        l_errors clob;
        l_valid boolean;
    begin
        select json_value(p_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error)
          into l_action_request_id
          from dual;

        l_valid := office_mfcs_validation_pkg.validate_request(p_payload, l_errors);

        if l_valid then
            p_http_status := 200;
            p_response := '{"ACTION_REQUEST_ID":"' || replace(l_action_request_id, '"', '\"') || '","STATUS":"VALIDATED","RETRYABLE":false,"COMPLETED_STEPS":["VALIDATE_REQUEST"],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":[]}';
        else
            p_http_status := 422;
            p_response := '{"ACTION_REQUEST_ID":' || case when l_action_request_id is null then 'null' else '"' || replace(l_action_request_id, '"', '\"') || '"' end || ',"STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":false,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":' || l_errors || '}';
        end if;
        office_mfcs_log_pkg.info(c_package_name, 'VALIDATE_TRANSACTION', l_action_request_id, case when l_valid then 'Validation succeeded' else 'Validation failed' end);
    exception
        when others then
            office_mfcs_log_pkg.error(c_package_name, 'VALIDATE_TRANSACTION', l_action_request_id, 'Validation raised an exception', sqlerrm);
            p_http_status := 400;
            p_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', '$', 'INVALID_JSON', sqlerrm);
    end;

    procedure get_transaction(
        p_action_request_id in varchar2,
        p_http_status       out number,
        p_response          out clob
    ) is
        l_status varchar2(30);
        l_response_payload clob;
    begin
        select request_status, response_payload
          into l_status, l_response_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;

        p_http_status := 200;
        if l_response_payload is not null then
            p_response := l_response_payload;
        else
            p_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
        end if;
        office_mfcs_log_pkg.info(c_package_name, 'GET_TRANSACTION', p_action_request_id, 'Transaction state returned');
    exception
        when no_data_found then
            office_mfcs_log_pkg.info(c_package_name, 'GET_TRANSACTION', p_action_request_id, 'Transaction was not found');
            p_http_status := 404;
            p_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'NOT_FOUND', 'Transaction was not found.');
    end;

    procedure resume_transaction(
        p_action_request_id in varchar2,
        p_http_status       out number,
        p_response          out clob
    ) is
        l_status varchar2(30);
        l_response_payload clob;
    begin
        select request_status
          into l_status
          from office_mfcs_request
         where action_request_id = p_action_request_id
         for update nowait;

        if l_status = 'IN_PROGRESS' then
            rollback;
            p_http_status := 409;
            p_response := simple_error(p_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            return;
        elsif l_status = 'COMPLETED' then
            commit;
            p_http_status := 200;
            select response_payload
              into l_response_payload
              from office_mfcs_request
             where action_request_id = p_action_request_id;
            if l_response_payload is not null then
                p_response := l_response_payload;
            else
                p_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
            end if;
            return;
        end if;

        update office_mfcs_request
           set request_status = 'IN_PROGRESS',
               started_at = coalesce(started_at, systimestamp),
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;
        commit;

        office_mfcs_orchestrator_pkg.resume_request(p_action_request_id);
        select request_status, response_payload
          into l_status, l_response_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;

        if l_response_payload is not null then
            p_response := l_response_payload;
        else
            p_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
        end if;
        p_http_status := response_status_to_http(l_status, p_response);
        office_mfcs_log_pkg.info(c_package_name, 'RESUME_TRANSACTION', p_action_request_id, 'Resume completed with status ' || l_status);
    exception
        when no_data_found then
            office_mfcs_log_pkg.info(c_package_name, 'RESUME_TRANSACTION', p_action_request_id, 'Transaction was not found');
            p_http_status := 404;
            p_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'NOT_FOUND', 'Transaction was not found.');
        when others then
            office_mfcs_log_pkg.error(c_package_name, 'RESUME_TRANSACTION', p_action_request_id, 'Resume failed', sqlerrm);
            if sqlcode = -54 then
                p_http_status := 409;
                p_response := simple_error(p_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            else
                p_http_status := 500;
                p_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'true', 'INTEGRATION', to_char(sqlcode), sqlerrm);
            end if;
    end;
end office_mfcs_api_pkg;
/

show errors

prompt OFFICE MFCS package bodies created

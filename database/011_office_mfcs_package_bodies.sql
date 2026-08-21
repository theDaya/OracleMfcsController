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
        o_result            out varchar2,
        o_status            out varchar2,
        o_response_payload  out clob
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
            o_result := 'NEW';
            o_status := 'RECEIVED';
            o_response_payload := null;
            return;
        exception
            when dup_val_on_index then
                null;
        end;

        begin
            select payload_hash, request_status, response_payload
              into l_existing_hash, l_status, o_response_payload
              from office_mfcs_request
             where action_request_id = p_action_request_id
             for update nowait;
        exception
            when others then
                if sqlcode = -54 then
                    o_result := 'EXECUTING';
                    o_status := 'IN_PROGRESS';
                    o_response_payload := null;
                    rollback;
                    return;
                end if;
                raise;
        end;

        if l_existing_hash <> p_payload_hash then
            o_result := 'CONFLICT';
            o_status := l_status;
        elsif l_status = 'IN_PROGRESS' then
            o_result := 'EXECUTING';
            o_status := l_status;
        elsif l_status = 'FAILED_NO_SIDE_EFFECT'
              and o_response_payload is not null
              and dbms_lob.instr(o_response_payload, 'MFCS_BATCH_WINDOW_ACTIVE') > 0 then
            update office_mfcs_request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            o_result := 'RESUME';
            o_status := 'IN_PROGRESS';
        elsif l_status in ('COMPLETED', 'FAILED_NO_SIDE_EFFECT', 'MANUAL_REVIEW') then
            o_result := 'EXISTING';
            o_status := l_status;
        else
            update office_mfcs_request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            o_result := 'RESUME';
            o_status := 'IN_PROGRESS';
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
            add_step(p_action_request_id, 'CREATE_PARENT_ITEM_HIERARCHY', 30);
            add_step(p_action_request_id, 'CREATE_PARENT_ITEM_SOURCING', 35);
            add_step(p_action_request_id, 'CREATE_CHILD_ITEM_HIERARCHY', 40);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 50);
            add_step(p_action_request_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE', 55);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 60);
            if get_config('FEATURE_ITEM_LOCATIONS_YN', 'N') = 'Y' then
                add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 70);
            end if;
            add_step(p_action_request_id, 'APPROVE_ITEMS', 80);
        elsif p_operation_name = 'MODIFY_STYLE' then
            add_step(p_action_request_id, 'CREATE_ITEM_HIERARCHY', 30);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 40);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 50);
            if get_config('FEATURE_ITEM_LOCATIONS_YN', 'N') = 'Y' then
                add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 60);
            end if;
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
        o_attempt_id        out number,
        o_correlation_id    out varchar2
    ) is
        pragma autonomous_transaction;
        l_attempt_number number;
        l_guid varchar2(32);
    begin
        select nvl(max(attempt_number), 0) + 1
          into l_attempt_number
          from office_mfcs_attempt
         where action_request_id = p_action_request_id
           and step_code = p_step_code;

        l_guid := lower(rawtohex(sys_guid()));
        o_correlation_id := substr(l_guid, 1, 8) || '-'
                         || substr(l_guid, 9, 4) || '-'
                         || substr(l_guid, 13, 4) || '-'
                         || substr(l_guid, 17, 4) || '-'
                         || substr(l_guid, 21);

        o_attempt_id := office_mfcs_attempt_seq.nextval;

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
            o_attempt_id,
            p_action_request_id,
            p_step_code,
            l_attempt_number,
            o_correlation_id,
            p_http_method,
            p_endpoint,
            p_request_payload,
            'IN_PROGRESS'
        );

        log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'ATTEMPT_BEGIN',
            p_step_code => p_step_code,
            p_attempt_id => o_attempt_id,
            p_message => 'MFCS attempt opened.',
            p_detail_payload => '{"attemptNumber":' || l_attempt_number
                || ',"correlationId":"' || json_escape(o_correlation_id)
                || '","httpMethod":"' || json_escape(p_http_method)
                || '","endpoint":"' || json_escape(p_endpoint) || '"}'
        );

        commit;
    end;

    procedure complete_attempt(
        p_attempt_id       in number,
        p_attempt_status   in varchar2,
        p_http_status      in number default null,
        p_response_payload in clob default null
    ) is
        pragma autonomous_transaction;
        l_action_request_id varchar2(80);
        l_step_code varchar2(60);
    begin
        update office_mfcs_attempt
           set attempt_status = p_attempt_status,
               http_status = p_http_status,
               response_payload = p_response_payload,
               completed_at = systimestamp
         where attempt_id = p_attempt_id
         returning action_request_id, step_code
              into l_action_request_id, l_step_code;

        log_event(
            p_action_request_id => l_action_request_id,
            p_event_phase => 'ATTEMPT_COMPLETE',
            p_step_code => l_step_code,
            p_attempt_id => p_attempt_id,
            p_event_level => case when p_attempt_status = 'SUCCEEDED' then 'INFO' else 'ERROR' end,
            p_message => 'MFCS attempt completed.',
            p_detail_payload => '{"attemptStatus":"' || json_escape(p_attempt_status)
                || '","httpStatus":' || coalesce(to_char(p_http_status), 'null')
                || ',"responseBytes":' || coalesce(to_char(dbms_lob.getlength(p_response_payload)), '0') || '}'
        );

        commit;
    end;

    procedure log_event(
        p_action_request_id in varchar2,
        p_event_phase       in varchar2,
        p_step_code         in varchar2 default null,
        p_attempt_id        in number default null,
        p_message           in varchar2 default null,
        p_detail_payload    in clob default null,
        p_event_level       in varchar2 default 'INFO'
    ) is
        pragma autonomous_transaction;
    begin
        insert into office_mfcs_event_log (
            log_id,
            action_request_id,
            step_code,
            attempt_id,
            event_level,
            event_phase,
            message,
            detail_payload
        ) values (
            office_mfcs_event_log_seq.nextval,
            p_action_request_id,
            p_step_code,
            p_attempt_id,
            coalesce(p_event_level, 'INFO'),
            p_event_phase,
            substr(p_message, 1, 1000),
            p_detail_payload
        );

        commit;
    exception
        when others then
            rollback;
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

        for r in (
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
                || '{"SOURCE_VARIANT_REF":"' || json_escape(r.source_variant_ref) || '",'
                || '"SKU_SIZE":"' || json_escape(r.sku_size) || '",'
                || '"SKU_WIDTH":"' || json_escape(r.sku_width) || '",'
                || '"SKU_ID":"' || json_escape(r.mfcs_sku_no) || '"}';
        end loop;

        l_response := l_response || '],"COMPLETED_STEPS":[';
        l_first := true;
        for s in (
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
            l_response := l_response || '"' || json_escape(s.step_code) || '"';
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
                      from office_mfcs_entity_map
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

    function build_item_number_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_number_request');
    end;

    function build_parent_item_create_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_parent_item_create_request');
    end;

    function build_child_item_create_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_child_item_create_request');
    end;

    function build_item_create_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_create_request');
    end;

    function build_parent_item_sourcing_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_parent_item_sourcing_request');
    end;

    function build_child_item_sourcing_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_child_item_sourcing_request');
    end;

    function build_item_sourcing_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_sourcing_request');
    end;

    function build_item_country_of_manufacture_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_country_of_manufacture_request');
    end;

    function build_item_uda_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_uda_request');
    end;

    function build_item_location_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_location_request');
    end;

    function build_item_approval_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_item_approval_request');
    end;

    function build_initial_retail_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_initial_retail_request');
    end;

    function build_po_number_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_po_number_request');
    end;

    function build_purchase_order_request(p_action_request_id in varchar2) return clob is
    begin
        -- dataLoadingDestination = RMS is emitted by the payload mapper itself.
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_purchase_order_request');
    end;

    function build_purchase_order_verify_request(p_action_request_id in varchar2) return clob is
    begin
        return office_mfcs_payload_pkg.build_request(p_action_request_id, 'build_purchase_order_verify_request');
    end;
end office_mfcs_mapping_pkg;
/

create or replace package body office_mfcs_client_pkg as
    g_access_token varchar2(32767);
    g_token_expires_at timestamp with time zone;

    function log_escape(p_value in varchar2) return varchar2 is
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

    function get_secret(p_secret_ref in varchar2) return varchar2 is
        l_secret varchar2(32767);
    begin
        begin
            select dbms_lob.substr(secret_value, 32767, 1)
              into l_secret
              from office_mfcs_secret
             where secret_ref = p_secret_ref;
        exception
            when no_data_found then
                l_secret := sys_context('OFFICE_MFCS_CTX', p_secret_ref);
        end;

        if l_secret is null then
            raise_application_error(
                -20890,
                'MFCS secret ' || p_secret_ref || ' is not configured in OFFICE_MFCS_SECRET or OFFICE_MFCS_CTX.'
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

    function access_token return varchar2 is
        l_token_url varchar2(1000);
        l_client_id varchar2(4000);
        l_client_secret varchar2(4000);
        l_secret_ref varchar2(200);
        l_scope varchar2(4000);
        l_response clob;
        l_expires_in number;
        l_static_token varchar2(32767);
    begin
        if office_mfcs_request_pkg.get_config('MFCS_AUTH_MODE', 'OAUTH_CLIENT_CREDENTIALS') = 'STATIC_BEARER' then
            l_static_token := trim(get_secret(office_mfcs_request_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN')));
            if lower(substr(l_static_token, 1, 7)) = 'bearer ' then
                return trim(substr(l_static_token, 8));
            end if;
            return l_static_token;
        end if;

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
        l_order_no varchar2(30);
    begin
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
            o_attempt_id => l_attempt_id,
            o_correlation_id => l_correlation_id
        );

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_PREPARED',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Prepared outbound MFCS call.',
            p_detail_payload => '{"endpointKey":"' || log_escape(p_endpoint_key)
                || '","endpoint":"' || log_escape(l_endpoint)
                || '","method":"' || log_escape(p_http_method)
                || '","requestBytes":' || coalesce(to_char(dbms_lob.getlength(p_request_payload)), '0') || '}'
        );

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

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_START',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Calling remote MFCS endpoint.',
            p_detail_payload => '{"endpointKey":"' || log_escape(p_endpoint_key)
                || '","endpoint":"' || log_escape(l_endpoint)
                || '","timeoutSeconds":' || office_mfcs_request_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45') || '}'
        );

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

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_RESPONSE',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_event_level => case when l_http_status between 200 and 299 then 'INFO' else 'ERROR' end,
            p_message => 'Remote MFCS endpoint returned.',
            p_detail_payload => '{"httpStatus":' || coalesce(to_char(l_http_status), 'null')
                || ',"responseBytes":' || coalesce(to_char(dbms_lob.getlength(l_response)), '0') || '}'
        );

        if l_http_status between 200 and 299 then
            office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
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
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'HTTP_CALL_EXCEPTION',
                p_step_code => p_step_code,
                p_attempt_id => l_attempt_id,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode
                    || ',"endpointKey":"' || log_escape(p_endpoint_key) || '"}'
            );

            if sqlcode in (-20950, -20951, -20952) then
                raise;
            end if;

            if instr(lower(sqlerrm), 'timeout') > 0 then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'OUTCOME_UNKNOWN', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
                raise_application_error(-20952, 'MFCS timeout after request was sent.');
            end if;

            if l_attempt_id is not null then
                office_mfcs_request_pkg.complete_attempt(l_attempt_id, 'FAILED', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
            end if;
            raise_application_error(-20950, sqlerrm);
    end;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob is
        l_response clob;
        l_endpoint varchar2(1000);
        l_http_status number;
    begin
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
    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_payload;
    end;

    function log_escape(p_value in varchar2) return varchar2 is
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
            for v in (
                select ordinality, source_variant_ref, sku_size, sku_width
                  from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                      columns
                          ordinality for ordinality,
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH'
                  )
            ) loop
                l_sku_no := treat(l_items.get(v.ordinality) as json_object_t).get_string('item');
                office_mfcs_request_pkg.save_generated_identifier(
                    p_action_request_id => p_action_request_id,
                    p_source_system => l_source_system,
                    p_source_style_ref => l_source_style_ref,
                    p_mfcs_style_no => l_style_no,
                    p_source_variant_ref => v.source_variant_ref,
                    p_mfcs_sku_no => l_sku_no,
                    p_sku_size => v.sku_size,
                    p_sku_width => v.sku_width
                );
            end loop;
        else
            for v in (
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
                    p_source_variant_ref => v.source_variant_ref,
                    p_mfcs_sku_no => v.sku_id,
                    p_sku_size => v.sku_size,
                    p_sku_width => v.sku_width
                );
            end loop;
        end if;
    end;

    function first_reserved_item(p_response in clob) return varchar2 is
        l_item varchar2(30);
    begin
        select coalesce(
                   json_value(p_response, '$.items[0].item' returning varchar2(30) null on error),
                   json_value(p_response, '$.item' returning varchar2(30) null on error),
                   json_value(p_response, '$.STYLE' returning varchar2(30) null on error)
               )
          into l_item
          from dual;

        if l_item is null then
            raise_application_error(-20830, 'MFCS item-number reservation response did not contain an item number.');
        end if;

        return l_item;
    end;

    procedure reserve_item_numbers_chunked(
        p_action_request_id in varchar2,
        p_user_id           in varchar2
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_source_system varchar2(60) := office_mfcs_mapping_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := office_mfcs_mapping_pkg.source_style_ref(l_payload);
        l_request_payload clob;
        l_response clob;
        l_style_no varchar2(30);
        l_sku_no varchar2(30);
        l_days number := to_number(office_mfcs_request_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_DAYS_UNTIL_EXPIRY', '14'));
    begin
        l_request_payload := '{"itemNumberType":"ITEM","quantity":1,"daysUntilExpiry":' || l_days || '}';

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_CHUNK_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Starting chunked item-number reservation.',
            p_detail_payload => '{"sourceSystem":"' || log_escape(l_source_system)
                || '","sourceStyleRef":"' || log_escape(l_source_style_ref)
                || '","daysUntilExpiry":' || l_days || '}'
        );

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserving MFCS item number for style.'
        );

        l_response := office_mfcs_client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
            p_request_payload => l_request_payload,
            p_user_id => p_user_id
        );

        l_style_no := first_reserved_item(l_response);

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_SUCCEEDED',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserved MFCS style item number.',
            p_detail_payload => '{"mfcsStyleNo":"' || log_escape(l_style_no) || '"}'
        );

        office_mfcs_request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => l_source_system,
            p_source_style_ref => l_source_style_ref,
            p_mfcs_style_no => l_style_no
        );

        for v in (
            select source_variant_ref, sku_size, sku_width
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_size varchar2(60) path '$.SKU_SIZE',
                      sku_width varchar2(60) path '$.SKU_WIDTH'
              )
        ) loop
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_START',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserving MFCS item number for SKU.',
                p_detail_payload => '{"sourceVariantRef":"' || log_escape(v.source_variant_ref)
                    || '","skuSize":"' || log_escape(v.sku_size)
                    || '","skuWidth":"' || log_escape(v.sku_width) || '"}'
            );

            l_response := office_mfcs_client_pkg.call_service(
                p_action_request_id => p_action_request_id,
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_http_method => 'POST',
                p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
                p_request_payload => l_request_payload,
                p_user_id => p_user_id
            );

            l_sku_no := first_reserved_item(l_response);

            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_SUCCEEDED',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserved MFCS SKU item number.',
                p_detail_payload => '{"sourceVariantRef":"' || log_escape(v.source_variant_ref)
                    || '","mfcsSkuNo":"' || log_escape(l_sku_no)
                    || '","mfcsStyleNo":"' || log_escape(l_style_no) || '"}'
            );

            office_mfcs_request_pkg.save_generated_identifier(
                p_action_request_id => p_action_request_id,
                p_source_system => l_source_system,
                p_source_style_ref => l_source_style_ref,
                p_mfcs_style_no => l_style_no,
                p_source_variant_ref => v.source_variant_ref,
                p_mfcs_sku_no => l_sku_no,
                p_sku_size => v.sku_size,
                p_sku_width => v.sku_width
            );
        end loop;

        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_CHUNK_COMPLETE',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Chunked item-number reservation completed.',
            p_detail_payload => '{"mfcsStyleNo":"' || log_escape(l_style_no) || '"}'
        );
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
            when 'CREATE_PARENT_ITEM_HIERARCHY' then return office_mfcs_mapping_pkg.build_parent_item_create_request(p_action_request_id);
            when 'CREATE_CHILD_ITEM_HIERARCHY' then return office_mfcs_mapping_pkg.build_child_item_create_request(p_action_request_id);
            when 'CREATE_ITEM_HIERARCHY' then return office_mfcs_mapping_pkg.build_item_create_request(p_action_request_id);
            when 'CREATE_PARENT_ITEM_SOURCING' then return office_mfcs_mapping_pkg.build_parent_item_sourcing_request(p_action_request_id);
            when 'CREATE_ITEM_SOURCING' then return office_mfcs_mapping_pkg.build_item_sourcing_request(p_action_request_id);
            when 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' then return office_mfcs_mapping_pkg.build_item_country_of_manufacture_request(p_action_request_id);
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
            when 'CREATE_PARENT_ITEM_HIERARCHY' then return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_CHILD_ITEM_HIERARCHY' then return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_ITEM_HIERARCHY' then
                if p_operation = 'MODIFY_STYLE' then
                    return 'ENDPOINT.ITEMS_UPDATE';
                end if;
                return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_PARENT_ITEM_SOURCING' then return 'ENDPOINT.ITEM_SOURCING_CREATE';
            when 'CREATE_ITEM_SOURCING' then
                if p_operation = 'MODIFY_STYLE' then return 'ENDPOINT.ITEM_SOURCING_UPDATE'; end if;
                return 'ENDPOINT.ITEM_SOURCING_CREATE';
            when 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' then return 'ENDPOINT.ITEM_COUNTRIES_OF_MANUFACTURE_CREATE';
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
        elsif p_step_code = 'APPROVE_ITEMS' then
            return 'PUT';
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
        l_verify_retry_count number := to_number(office_mfcs_request_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_COUNT', '12'));
        l_verify_retry_sleep number := to_number(office_mfcs_request_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS', '10'));
    begin
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
        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_EXECUTE_START',
            p_message => 'MFCS orchestration started.',
            p_detail_payload => '{"operationName":"' || log_escape(l_operation)
                || '","userId":"' || log_escape(l_user_id)
                || '","budgetSeconds":' || l_budget_seconds || '}'
        );
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

            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'IN_PROGRESS');
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_START',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step started.',
                p_detail_payload => '{"endpointKey":"' || log_escape(l_endpoint_key)
                    || '","method":"' || log_escape(l_method)
                    || '","requestBytes":' || coalesce(to_char(dbms_lob.getlength(l_request_payload)), '0') || '}'
            );

            if l_step = 'RESERVE_ITEM_NUMBERS'
               and to_number(office_mfcs_request_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_CHUNK_SIZE', '1')) = 1 then
                reserve_item_numbers_chunked(p_action_request_id, l_user_id);
                office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                office_mfcs_request_pkg.log_event(
                    p_action_request_id => p_action_request_id,
                    p_event_phase => 'STEP_SUCCEEDED',
                    p_step_code => l_step,
                    p_message => 'MFCS orchestration step succeeded.'
                );
                continue;
            end if;

            if l_step = 'VERIFY_PURCHASE_ORDER' then
                for i in 1 .. greatest(1, l_verify_retry_count) loop
                    begin
                        l_response := office_mfcs_client_pkg.call_service(
                            p_action_request_id => p_action_request_id,
                            p_step_code => l_step,
                            p_http_method => l_method,
                            p_endpoint_key => l_endpoint_key,
                            p_request_payload => l_request_payload,
                            p_user_id => l_user_id
                        );
                        exit;
                    exception
                        when office_mfcs_client_pkg.e_downstream_failure then
                            if i >= greatest(1, l_verify_retry_count) then
                                raise;
                            end if;
                            office_mfcs_request_pkg.log_event(
                                p_action_request_id => p_action_request_id,
                                p_event_phase => 'VERIFY_RETRY_WAIT',
                                p_step_code => l_step,
                                p_event_level => 'WARN',
                                p_message => 'Purchase order verification failed; waiting before retry.',
                                p_detail_payload => '{"retryNumber":' || i
                                    || ',"maxRetries":' || greatest(1, l_verify_retry_count)
                                    || ',"sleepSeconds":' || l_verify_retry_sleep || '}'
                            );
                            dbms_session.sleep(l_verify_retry_sleep);
                    end;
                end loop;
            else
                l_response := office_mfcs_client_pkg.call_service(
                    p_action_request_id => p_action_request_id,
                    p_step_code => l_step,
                    p_http_method => l_method,
                    p_endpoint_key => l_endpoint_key,
                    p_request_payload => l_request_payload,
                    p_user_id => l_user_id
                );
            end if;

            if l_step = 'RESERVE_ITEM_NUMBERS' then
                persist_item_numbers(p_action_request_id, l_response);
            elsif l_step = 'RESERVE_ORDER_NUMBER' then
                persist_po_number(p_action_request_id, l_response);
            end if;

            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_SUCCEEDED',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step succeeded.'
            );
        end loop;

        office_mfcs_request_pkg.set_request_status(
            p_action_request_id,
            'COMPLETED',
            office_mfcs_request_pkg.build_status_response(p_action_request_id, 'COMPLETED')
        );
        office_mfcs_request_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_COMPLETED',
            p_message => 'MFCS orchestration completed.'
        );
    exception
        when office_mfcs_client_pkg.e_outcome_unknown then
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_OUTCOME_UNKNOWN',
                p_step_code => l_step,
                p_event_level => 'WARN',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', sqlerrm);
            office_mfcs_request_pkg.set_request_status(p_action_request_id, 'OUTCOME_UNKNOWN', office_mfcs_request_pkg.build_status_response(p_action_request_id, 'OUTCOME_UNKNOWN'));
        when others then
            office_mfcs_request_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_EXCEPTION',
                p_step_code => l_step,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            if l_step is not null then
                office_mfcs_request_pkg.set_step_status(p_action_request_id, l_step, 'FAILED', null, to_char(sqlcode), sqlerrm);
            end if;

            if any_succeeded(p_action_request_id) then
                office_mfcs_request_pkg.set_request_status(p_action_request_id, 'PARTIALLY_COMPLETED', office_mfcs_request_pkg.build_status_response(p_action_request_id, 'PARTIALLY_COMPLETED'));
            else
                office_mfcs_request_pkg.set_request_status(
                    p_action_request_id,
                    'FAILED_NO_SIDE_EFFECT',
                    '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":"' || l_step || '","GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"' || l_step || '","CODE":"' || sqlcode || '","MESSAGE":"' || replace(sqlerrm, '"', '\"') || '"}]}'
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
        o_http_status  out number,
        o_response     out clob
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
                o_http_status := 400;
                o_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', '$', 'INVALID_JSON', sqlerrm);
                return;
        end;

        select json_value(p_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error),
               json_value(p_payload, '$.OPERATION_NAME' returning varchar2(30) null on error)
          into l_action_request_id, l_operation
          from dual;

        if trim(l_action_request_id) is null then
            o_http_status := 400;
            o_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'REQUIRED', 'ACTION_REQUEST_ID is required.');
            return;
        end if;

        if trim(l_operation) is null then
            o_http_status := 400;
            o_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'OPERATION_NAME', 'REQUIRED', 'OPERATION_NAME is required.');
            return;
        elsif l_operation not in ('CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            o_http_status := 400;
            o_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'OPERATION_NAME', 'UNSUPPORTED_OPERATION', 'Unsupported OPERATION_NAME.');
            return;
        end if;

        l_hash := office_mfcs_request_pkg.payload_hash(p_payload);
        office_mfcs_request_pkg.register_request(
            p_action_request_id => l_action_request_id,
            p_operation_name => l_operation,
            p_payload_hash => l_hash,
            p_payload => p_payload,
            o_result => l_result,
            o_status => l_status,
            o_response_payload => l_existing_response
        );

        if l_result = 'CONFLICT' then
            o_http_status := 409;
            o_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'IDEMPOTENCY_CONFLICT', 'ACTION_REQUEST_ID already exists with a different business payload hash.');
            return;
        elsif l_result = 'EXECUTING' then
            o_http_status := 409;
            o_response := simple_error(l_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            return;
        elsif l_result = 'EXISTING' and l_existing_response is not null then
            o_http_status := response_status_to_http(l_status, l_existing_response);
            o_response := l_existing_response;
            return;
        end if;

        l_valid := office_mfcs_validation_pkg.validate_request(p_payload, l_errors);

        if not l_valid then
            o_response := '{"ACTION_REQUEST_ID":"' || replace(l_action_request_id, '"', '\"') || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":false,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":' || l_errors || '}';
            office_mfcs_request_pkg.set_request_status(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', o_response);
            o_http_status := 422;
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
            o_response := l_existing_response;
        else
            o_response := office_mfcs_request_pkg.build_status_response(l_action_request_id);
        end if;

        o_http_status := response_status_to_http(l_status, o_response);
    exception
        when others then
            o_http_status := 500;
            o_response := simple_error(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'true', 'INTEGRATION', to_char(sqlcode), sqlerrm);
    end;

    procedure validate_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
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
            o_http_status := 200;
            o_response := '{"ACTION_REQUEST_ID":"' || replace(l_action_request_id, '"', '\"') || '","STATUS":"VALIDATED","RETRYABLE":false,"COMPLETED_STEPS":["VALIDATE_REQUEST"],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":[]}';
        else
            o_http_status := 422;
            o_response := '{"ACTION_REQUEST_ID":' || case when l_action_request_id is null then 'null' else '"' || replace(l_action_request_id, '"', '\"') || '"' end || ',"STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":false,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":' || l_errors || '}';
        end if;
    exception
        when others then
            o_http_status := 400;
            o_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', '$', 'INVALID_JSON', sqlerrm);
    end;

    procedure get_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
    ) is
        l_status varchar2(30);
        l_response_payload clob;
    begin
        select request_status, response_payload
          into l_status, l_response_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;

        o_http_status := 200;
        if l_response_payload is not null then
            o_response := l_response_payload;
        else
            o_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
        end if;
    exception
        when no_data_found then
            o_http_status := 404;
            o_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'NOT_FOUND', 'Transaction was not found.');
    end;

    procedure resume_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
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
            o_http_status := 409;
            o_response := simple_error(p_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            return;
        elsif l_status = 'COMPLETED' then
            commit;
            o_http_status := 200;
            select response_payload
              into l_response_payload
              from office_mfcs_request
             where action_request_id = p_action_request_id;
            if l_response_payload is not null then
                o_response := l_response_payload;
            else
                o_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
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
            o_response := l_response_payload;
        else
            o_response := office_mfcs_request_pkg.build_status_response(p_action_request_id);
        end if;
        o_http_status := response_status_to_http(l_status, o_response);
    exception
        when no_data_found then
            o_http_status := 404;
            o_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'false', 'ACTION_REQUEST_ID', 'NOT_FOUND', 'Transaction was not found.');
        when others then
            if sqlcode = -54 then
                o_http_status := 409;
                o_response := simple_error(p_action_request_id, 'IN_PROGRESS', 'true', 'ACTION_REQUEST_ID', 'ALREADY_EXECUTING', 'Request is currently executing.');
            else
                o_http_status := 500;
                o_response := simple_error(p_action_request_id, 'FAILED_NO_SIDE_EFFECT', 'true', 'INTEGRATION', to_char(sqlcode), sqlerrm);
            end if;
    end;
end office_mfcs_api_pkg;
/

show errors

prompt OFFICE MFCS package bodies created

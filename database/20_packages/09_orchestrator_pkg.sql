set define off

-- Step graph, endpoint resolution and request execution.

prompt Creating orchestrator_pkg

create or replace package orchestrator_pkg authid definer as
    procedure execute_request(
        p_action_request_id in varchar2
    );

    procedure resume_request(
        p_action_request_id in varchar2
    );

    -- Pure resolvers, exposed so the preview layer can describe the planned MFCS
    -- calls without duplicating the step-to-endpoint mapping. No side effects.
    function endpoint_for_step(
        p_step_code in varchar2,
        p_operation in varchar2
    ) return varchar2;

    function method_for_step(
        p_step_code in varchar2,
        p_operation in varchar2
    ) return varchar2;

    function payload_for_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return clob;
end orchestrator_pkg;
/

show errors

create or replace package body orchestrator_pkg as
    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from request
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
          from request
         where action_request_id = p_action_request_id;
        return l_operation;
    end;

    function any_succeeded(p_action_request_id in varchar2) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from step
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
        l_source_system varchar2(60) := payload_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := payload_pkg.source_style_ref(l_payload);
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

        request_pkg.save_generated_identifier(
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
                request_pkg.save_generated_identifier(
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
                request_pkg.save_generated_identifier(
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
        l_source_system varchar2(60) := payload_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := payload_pkg.source_style_ref(l_payload);
        l_request_payload clob;
        l_response clob;
        l_style_no varchar2(30);
        l_sku_no varchar2(30);
        l_days number := to_number(config_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_DAYS_UNTIL_EXPIRY', '14'));
    begin
        l_request_payload := '{"itemNumberType":"ITEM","quantity":1,"daysUntilExpiry":' || l_days || '}';

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_CHUNK_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Starting chunked item-number reservation.',
            p_detail_payload => '{"sourceSystem":"' || log_escape(l_source_system)
                || '","sourceStyleRef":"' || log_escape(l_source_style_ref)
                || '","daysUntilExpiry":' || l_days || '}'
        );

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserving MFCS item number for style.'
        );

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
            p_request_payload => l_request_payload,
            p_user_id => p_user_id
        );

        l_style_no := first_reserved_item(l_response);

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_SUCCEEDED',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserved MFCS style item number.',
            p_detail_payload => '{"mfcsStyleNo":"' || log_escape(l_style_no) || '"}'
        );

        request_pkg.save_generated_identifier(
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
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_START',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserving MFCS item number for SKU.',
                p_detail_payload => '{"sourceVariantRef":"' || log_escape(v.source_variant_ref)
                    || '","skuSize":"' || log_escape(v.sku_size)
                    || '","skuWidth":"' || log_escape(v.sku_width) || '"}'
            );

            l_response := client_pkg.call_service(
                p_action_request_id => p_action_request_id,
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_http_method => 'POST',
                p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
                p_request_payload => l_request_payload,
                p_user_id => p_user_id
            );

            l_sku_no := first_reserved_item(l_response);

            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_SUCCEEDED',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserved MFCS SKU item number.',
                p_detail_payload => '{"sourceVariantRef":"' || log_escape(v.source_variant_ref)
                    || '","mfcsSkuNo":"' || log_escape(l_sku_no)
                    || '","mfcsStyleNo":"' || log_escape(l_style_no) || '"}'
            );

            request_pkg.save_generated_identifier(
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

        event_pkg.log_event(
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

        request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => payload_pkg.source_system(l_payload),
            p_source_style_ref => payload_pkg.source_style_ref(l_payload),
            p_mfcs_style_no => null,
            p_source_order_ref => payload_pkg.source_order_ref(l_payload),
            p_mfcs_order_no => l_order_no
        );
    end;

    function payload_for_step(
        p_action_request_id in varchar2,
        p_step_code in varchar2
    ) return clob is
    begin
        case p_step_code
            when 'RESERVE_ITEM_NUMBERS' then return payload_pkg.build_request(p_action_request_id, 'build_item_number_request');
            when 'CREATE_PARENT_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_parent_item_create_request');
            when 'CREATE_CHILD_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_child_item_create_request');
            when 'CREATE_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_item_create_request');
            when 'CREATE_PARENT_ITEM_SOURCING' then return payload_pkg.build_request(p_action_request_id, 'build_parent_item_sourcing_request');
            when 'CREATE_ITEM_SOURCING' then return payload_pkg.build_request(p_action_request_id, 'build_item_sourcing_request');
            when 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' then return payload_pkg.build_request(p_action_request_id, 'build_item_country_of_manufacture_request');
            when 'CREATE_ITEM_UDAS' then return payload_pkg.build_request(p_action_request_id, 'build_item_uda_request');
            when 'CREATE_ITEM_LOCATIONS' then return payload_pkg.build_request(p_action_request_id, 'build_item_location_request');
            when 'APPROVE_ITEMS' then return payload_pkg.build_request(p_action_request_id, 'build_item_approval_request');
            when 'APPLY_INITIAL_RETAIL' then return payload_pkg.build_request(p_action_request_id, 'build_initial_retail_request');
            when 'RESERVE_ORDER_NUMBER' then return payload_pkg.build_request(p_action_request_id, 'build_po_number_request');
            when 'CREATE_PURCHASE_ORDER' then return payload_pkg.build_request(p_action_request_id, 'build_purchase_order_request');
            when 'VERIFY_PURCHASE_ORDER' then return payload_pkg.build_request(p_action_request_id, 'build_purchase_order_verify_request');
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
        l_user_id varchar2(120) := payload_pkg.user_id(l_payload);
        l_request_payload clob;
        l_response clob;
        l_endpoint_key varchar2(200);
        l_method varchar2(10);
        l_recovery_status varchar2(30);
        l_started_at timestamp with time zone := systimestamp;
        l_budget_seconds number := to_number(config_pkg.get_config('INTERNAL_TIME_BUDGET_SECONDS', '240'));
        l_verify_retry_count number := to_number(config_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_COUNT', '12'));
        l_verify_retry_sleep number := to_number(config_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS', '10'));
    begin
        if l_operation = 'CREATE_ALL'
           and config_pkg.get_config('BATCH_WINDOW_ACTIVE_YN', 'N') = 'Y'
           and not any_succeeded(p_action_request_id) then
            request_pkg.set_request_status(
                p_action_request_id,
                'FAILED_NO_SIDE_EFFECT',
                '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"MFCS_BATCH_WINDOW","CODE":"MFCS_BATCH_WINDOW_ACTIVE","MESSAGE":"Required MFCS services are unavailable during the configured batch window."}]}'
            );
            return;
        end if;

        request_pkg.set_request_status(p_action_request_id, 'IN_PROGRESS');
        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_EXECUTE_START',
            p_message => 'MFCS orchestration started.',
            p_detail_payload => '{"operationName":"' || log_escape(l_operation)
                || '","userId":"' || log_escape(l_user_id)
                || '","budgetSeconds":' || l_budget_seconds || '}'
        );
        step_pkg.set_step_status(p_action_request_id, 'VALIDATE_REQUEST', 'SUCCEEDED');

        loop
            l_step := step_pkg.first_runnable_step(p_action_request_id);
            exit when l_step is null;

            if l_step = 'VALIDATE_REQUEST' then
                step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                continue;
            end if;

            if (cast(systimestamp as date) - cast(l_started_at as date)) * 86400 >= l_budget_seconds then
                request_pkg.set_request_status(
                    p_action_request_id,
                    case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end,
                    request_pkg.build_status_response(
                        p_action_request_id,
                        case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end
                    )
                );
                return;
            end if;

            select step_status
              into l_recovery_status
              from step
             where action_request_id = p_action_request_id
               and step_code = l_step;

            if l_recovery_status = 'OUTCOME_UNKNOWN' then
                l_recovery_status := recovery_pkg.resolve_step(p_action_request_id, l_step);
                if l_recovery_status = 'SUCCEEDED' then
                    continue;
                elsif l_recovery_status = 'MANUAL_REVIEW' then
                    return;
                end if;
            end if;

            l_endpoint_key := endpoint_for_step(l_step, l_operation);
            l_method := method_for_step(l_step, l_operation);
            l_request_payload := payload_for_step(p_action_request_id, l_step);

            step_pkg.set_step_status(p_action_request_id, l_step, 'IN_PROGRESS');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_START',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step started.',
                p_detail_payload => '{"endpointKey":"' || log_escape(l_endpoint_key)
                    || '","method":"' || log_escape(l_method)
                    || '","requestBytes":' || coalesce(to_char(dbms_lob.getlength(l_request_payload)), '0') || '}'
            );

            if l_step = 'RESERVE_ITEM_NUMBERS'
               and to_number(config_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_CHUNK_SIZE', '1')) = 1 then
                reserve_item_numbers_chunked(p_action_request_id, l_user_id);
                step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                event_pkg.log_event(
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
                        l_response := client_pkg.call_service(
                            p_action_request_id => p_action_request_id,
                            p_step_code => l_step,
                            p_http_method => l_method,
                            p_endpoint_key => l_endpoint_key,
                            p_request_payload => l_request_payload,
                            p_user_id => l_user_id
                        );
                        exit;
                    exception
                        when client_pkg.e_downstream_failure then
                            if i >= greatest(1, l_verify_retry_count) then
                                raise;
                            end if;
                            event_pkg.log_event(
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
                l_response := client_pkg.call_service(
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

            step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_SUCCEEDED',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step succeeded.'
            );
        end loop;

        request_pkg.set_request_status(
            p_action_request_id,
            'COMPLETED',
            request_pkg.build_status_response(p_action_request_id, 'COMPLETED')
        );
        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_COMPLETED',
            p_message => 'MFCS orchestration completed.'
        );
    exception
        when client_pkg.e_outcome_unknown then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_OUTCOME_UNKNOWN',
                p_step_code => l_step,
                p_event_level => 'WARN',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            step_pkg.set_step_status(p_action_request_id, l_step, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', sqlerrm);
            request_pkg.set_request_status(p_action_request_id, 'OUTCOME_UNKNOWN', request_pkg.build_status_response(p_action_request_id, 'OUTCOME_UNKNOWN'));
        when others then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_EXCEPTION',
                p_step_code => l_step,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            if l_step is not null then
                step_pkg.set_step_status(p_action_request_id, l_step, 'FAILED', null, to_char(sqlcode), sqlerrm);
            end if;

            if any_succeeded(p_action_request_id) then
                request_pkg.set_request_status(p_action_request_id, 'PARTIALLY_COMPLETED', request_pkg.build_status_response(p_action_request_id, 'PARTIALLY_COMPLETED'));
            else
                request_pkg.set_request_status(
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
end orchestrator_pkg;
/

show errors

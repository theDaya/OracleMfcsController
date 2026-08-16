set define off

prompt Creating OFFICE MFCS mock package

create or replace package office_mfcs_mock_pkg authid definer as
    function invoke(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        p_correlation_id    in varchar2,
        p_user_id           in varchar2
    ) return clob;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob;
end office_mfcs_mock_pkg;
/

create or replace package body office_mfcs_mock_pkg as
    function cfg(p_key in varchar2, p_default in varchar2 default null) return varchar2 is
    begin
        return office_mfcs_request_pkg.get_config(p_key, p_default);
    end;

    function json_escape(p_value in varchar2) return varchar2 is
    begin
        return replace(replace(p_value, '\', '\\'), '"', '\"');
    end;

    function hash_number(p_value in varchar2, p_base in number, p_span in number) return number is
        l_hash number;
    begin
        select ora_hash(p_value, p_span) + p_base
          into l_hash
          from dual;
        return l_hash;
    end;

    function failure_response(
        p_step_code in varchar2,
        p_http_status in number,
        p_attempt_status in varchar2
    ) return clob is
    begin
        return '{"mock":{"httpStatus":' || p_http_status || ',"attemptStatus":"' || p_attempt_status || '"},'
            || '"STEP_CODE":"' || json_escape(p_step_code) || '",'
            || '"ERROR":{"CODE":"MOCK_FORCED_' || json_escape(p_step_code) || '","MESSAGE":"Mock forced response for ' || json_escape(p_step_code) || '."}}';
    end;

    function invoke(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        p_correlation_id    in varchar2,
        p_user_id           in varchar2
    ) return clob is
        l_style varchar2(30);
        l_order varchar2(30);
        l_response clob;
        l_first boolean := true;
        l_fail_step varchar2(60) := cfg('MOCK_FAIL_STEP');
        l_timeout_step varchar2(60) := cfg('MOCK_TIMEOUT_STEP');
        l_http_status number := to_number(cfg('MOCK_FAIL_HTTP_STATUS', '500'));
    begin
        insert into office_mfcs_config (environment, config_key, config_value, enabled_ind)
        values ('DEFAULT', 'MOCK_LAST_CORRELATION.' || p_correlation_id, p_step_code, 'Y');
        commit;

        if l_timeout_step = p_step_code then
            return failure_response(p_step_code, 408, 'OUTCOME_UNKNOWN');
        end if;

        if l_fail_step = p_step_code then
            return failure_response(p_step_code, l_http_status, 'FAILED');
        end if;

        if p_step_code = 'RESERVE_ITEM_NUMBERS' then
            l_style := to_char(hash_number(p_action_request_id || ':STYLE', 3000000, 999999));
            l_response := '{"mock":{"httpStatus":200,"attemptStatus":"SUCCEEDED"},'
                || '"STYLE":"' || l_style || '","PLMSizeCurveDtl":[';

            for v in (
                select row_number() over (order by source_variant_ref) rn,
                       source_variant_ref,
                       sku_size,
                       sku_width,
                       sku_qty
                  from json_table(p_request_payload, '$.sourcePayload.PLMSizeCurveDtl[*]'
                      columns
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH',
                          sku_qty number path '$.SKU_QTY'
                  )
            ) loop
                if l_first then
                    l_first := false;
                else
                    l_response := l_response || ',';
                end if;

                l_response := l_response
                    || '{"SOURCE_VARIANT_REF":"' || json_escape(v.source_variant_ref) || '",'
                    || '"SKU_SIZE":"' || json_escape(v.sku_size) || '",'
                    || '"SKU_WIDTH":"' || json_escape(v.sku_width) || '",'
                    || '"SKU_QTY":' || to_char(v.sku_qty) || ','
                    || '"SKU_ID":"' || to_char(hash_number(p_action_request_id || ':SKU:' || v.rn, 10000000, 999999)) || '"}';
            end loop;

            return l_response || ']}';
        elsif p_step_code = 'RESERVE_ORDER_NUMBER' then
            l_order := to_char(hash_number(p_action_request_id || ':ORDER', 10700000, 999999));
            return '{"mock":{"httpStatus":200,"attemptStatus":"SUCCEEDED"},"ORDER_NO":"' || l_order || '"}';
        elsif p_step_code = 'CREATE_PURCHASE_ORDER' then
            return '{"mock":{"httpStatus":200,"attemptStatus":"SUCCEEDED"},"dataLoadingDestination":"RMS","RESULT":"PURCHASE_ORDER_CREATED"}';
        elsif p_step_code = 'VERIFY_PURCHASE_ORDER' then
            return '{"mock":{"httpStatus":200,"attemptStatus":"SUCCEEDED"},"RESULT":"PURCHASE_ORDER_APPROVED"}';
        else
            return '{"mock":{"httpStatus":200,"attemptStatus":"SUCCEEDED"},"RESULT":"' || json_escape(p_step_code) || '_OK"}';
        end if;
    end;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob is
        l_status varchar2(30) := cfg('MOCK_TIMEOUT_STATUS', 'SUCCESS');
    begin
        if l_status in ('SUCCESS', 'FAILURE', 'NO_RECORD', 'UNKNOWN') then
            return '{"status":"' || l_status || '","xCorrelationId":"' || json_escape(p_correlation_id) || '"}';
        end if;

        return '{"status":"UNKNOWN","xCorrelationId":"' || json_escape(p_correlation_id) || '"}';
    end;
end office_mfcs_mock_pkg;
/

show errors

prompt OFFICE MFCS mock package created

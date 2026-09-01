set define off

-- Public entry points behind the ORDS handlers.
--
-- The only package ORDS calls for transaction work. Each procedure returns the
-- HTTP status and the response body; the handlers emit them verbatim, so
-- everything the console or Office sees is decided here, not in the handler.
--
-- Application error codes used across the packages:
--   -20820        unknown payload mapper (a compile-time wiring bug)
--   -20830        MFCS reservation response carried no item number
--   -20950        MFCS rejected a call (HTTP 4xx/5xx with a readable body)
--   -20951        MFCS unavailable: HTTP 503 or the nightly batch window
--   -20952        transport failed after the request may have been sent;
--                 the outcome is unknown until recovery_pkg resolves it
--   -20960..20965 ENSURE_STYLE_SKUS: lookup failed, combinations missing,
--                 parent unreadable, unmapped size, no sourcing, verify failed

prompt Creating api_pkg

create or replace package api_pkg authid definer as
    -- Validates, registers and executes an Office document. Replays the stored
    -- outcome for a duplicate, 409s a conflicting reuse of the id, 422s a
    -- document that fails validation.
    procedure submit_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    );

    -- Runs validation only. Nothing is registered and nothing reaches MFCS.
    procedure validate_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    );

    -- Returns the current status document for a registered request.
    procedure get_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
    );

    -- Re-enters a partially completed request: succeeded steps are skipped,
    -- the failed or unknown step is retried, and execution continues from
    -- there. A request that failed on a bad stored value needs a fresh
    -- request instead - resume replays the stored payload.
    procedure resume_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
    );
end api_pkg;
/

show errors

create or replace package body api_pkg as
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
        l_payload clob;
    begin
        begin
            l_parsed := json_element_t.parse(p_payload);
        exception
            when others then
                o_http_status := 400;
                o_response := simple_error(null, 'FAILED_NO_SIDE_EFFECT', 'false', '$', 'INVALID_JSON', sqlerrm);
                return;
        end;

        -- Everything below this line works on the canonical document, including
        -- the hash and the row that gets stored. See request_pkg.normalise_payload.
        l_payload := request_pkg.normalise_payload(p_payload);

        select json_value(l_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error),
               json_value(l_payload, '$.OPERATION_NAME' returning varchar2(30) null on error)
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

        l_hash := request_pkg.payload_hash(l_payload);
        request_pkg.register_request(
            p_action_request_id => l_action_request_id,
            p_operation_name => l_operation,
            p_payload_hash => l_hash,
            p_payload => l_payload,
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

        l_valid := validation_pkg.validate_request(l_payload, l_errors);

        if not l_valid then
            o_response := '{"ACTION_REQUEST_ID":"' || replace(l_action_request_id, '"', '\"') || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":false,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":' || l_errors || '}';
            request_pkg.set_request_status(l_action_request_id, 'FAILED_NO_SIDE_EFFECT', o_response);
            o_http_status := 422;
            return;
        end if;

        step_pkg.initialize_steps(l_action_request_id, l_operation);
        request_pkg.set_request_status(l_action_request_id, 'VALIDATED');
        orchestrator_pkg.execute_request(l_action_request_id);

        select request_status, response_payload
          into l_status, l_existing_response
          from request
         where action_request_id = l_action_request_id;

        if l_existing_response is not null then
            o_response := l_existing_response;
        else
            o_response := request_pkg.build_status_response(l_action_request_id);
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
        l_payload clob;
    begin
        -- Validate the same document the submit path would store.
        l_payload := request_pkg.normalise_payload(p_payload);
        select json_value(l_payload, '$.ACTION_REQUEST_ID' returning varchar2(80) null on error)
          into l_action_request_id
          from dual;

        l_valid := validation_pkg.validate_request(l_payload, l_errors);

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
          from request
         where action_request_id = p_action_request_id;

        o_http_status := 200;
        if l_response_payload is not null then
            o_response := l_response_payload;
        else
            o_response := request_pkg.build_status_response(p_action_request_id);
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
          from request
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
              from request
             where action_request_id = p_action_request_id;
            if l_response_payload is not null then
                o_response := l_response_payload;
            else
                o_response := request_pkg.build_status_response(p_action_request_id);
            end if;
            return;
        end if;

        update request
           set request_status = 'IN_PROGRESS',
               started_at = coalesce(started_at, systimestamp),
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;
        commit;

        orchestrator_pkg.resume_request(p_action_request_id);
        select request_status, response_payload
          into l_status, l_response_payload
          from request
         where action_request_id = p_action_request_id;

        if l_response_payload is not null then
            o_response := l_response_payload;
        else
            o_response := request_pkg.build_status_response(p_action_request_id);
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
end api_pkg;
/

show errors

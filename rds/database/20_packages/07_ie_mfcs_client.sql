-- Outbound MFCS calls: credentials, HTTP, attempt journalling.
--
-- The only package that resolves a credential or makes an outbound call.
-- Keep it that way: a second HTTP path is how a stale token once survived in
-- one code path and not another.
--
-- Credentials live in the APEX credential store, not in this schema. The
-- client id and secret are entered once, as a Web Credential in the workspace,
-- and are then unreadable: no view returns either, and they are excluded from
-- application exports. apex_web_service fetches the bearer token, caches it in
-- the database and refetches it on expiry, so nothing here holds a token.
--
-- There is one mode. The original layer also had STATIC_BEARER - a token
-- pasted by hand into a SECRET table, which expired hourly - kept as a
-- fallback while the credential store was new. It was deliberately not
-- carried into RDS: a table holding a plain secret is exactly what the
-- credential store replaced, and nothing here should start life with one.
--
-- That last point is not only about secrecy. This package used to cache the
-- token in a package global while the comment here claimed it did not, and
-- the rule exists for a reason: ORDS pools sessions, so a cached token
-- outlives the request that fetched it and survives a change of tenant -
-- which surfaces as the 403 documented in CLAUDE.md rather than as anything
-- that names a token.
--
-- Failure classification matters more than it looks. An HTTP error with a
-- readable body is a failure (-20950); HTTP 503 and the tenant's nightly
-- batch refusal are unavailability (-20951); a transport error after the
-- request may have been sent is an unknown outcome (-20952), resolved later
-- by ie_mfcs_recovery - never assume a send that errored did not land.

create or replace package ie_mfcs_client authid definer as
    e_downstream_failure exception;
    pragma exception_init(e_downstream_failure, -20950);

    e_downstream_unavailable exception;
    pragma exception_init(e_downstream_unavailable, -20951);

    e_outcome_unknown exception;
    pragma exception_init(e_outcome_unknown, -20952);

    -- Authenticated GET against the MFCS tenant. Exposed so the master-data and
    -- browse packages share one implementation of credential handling and headers
    -- rather than each keeping a copy of it.
    function get_json(
        p_path   in varchar2,
        o_status out number
    ) return clob;

    -- Says whether the credential is registered and what it points at. Never
    -- returns the id, the secret or a token - none of them can be read back.
    function token_status return clob;

    function call_service(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint_key      in varchar2,
        p_request_payload   in clob,
        p_user_id           in varchar2
    ) return clob;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob;
end ie_mfcs_client;
/

create or replace package body ie_mfcs_client as

    -- No wallet arguments anywhere in this package. The original read a wallet
    -- path, password and host from config, never seeded any of them, and so
    -- always passed nulls; on Autonomous Database the built-in certificate store
    -- is what a null wallet means, which is the behaviour wanted.

    function credential_static_id return varchar2 is
    begin
        return ie_mfcs_config.get_config('MFCS_CREDENTIAL_STATIC_ID', 'MFCS_OAUTH');
    end;

    function token_url return varchar2 is
    begin
        return ie_mfcs_config.get_config('MFCS_TOKEN_URL');
    end;

    function oauth_scope return varchar2 is
    begin
        return ie_mfcs_config.get_config('MFCS_SCOPE');
    end;

    function workspace return varchar2 is
    begin
        return ie_mfcs_config.get_config('MFCS_APEX_WORKSPACE', 'MFCS');
    end;

    -- An APEX credential is workspace-scoped, and PL/SQL invoked through ORDS is
    -- not inside an APEX session, so the workspace has to be named before the
    -- credential can be resolved. Without this the call goes out with no
    -- Authorization header at all and MFCS answers 401 - a failure that looks
    -- exactly like a bad secret and is not one.
    procedure ensure_workspace is
    begin
        apex_util.set_workspace(p_workspace => workspace);
    end;

    -- Every outbound call goes through here, so that no call can be made
    -- without the workspace named and the credential attached. apex_web_service
    -- sets Authorization itself from the credential; setting it in the headers
    -- as well would win and defeat the point.
    function make_request(
        p_url         in varchar2,
        p_http_method in varchar2,
        p_body        in clob default null
    ) return clob is
    begin
        ensure_workspace;
        return apex_web_service.make_rest_request(
            p_url => p_url,
            p_http_method => p_http_method,
            p_body => p_body,
            p_transfer_timeout => to_number(ie_mfcs_config.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45')),
            p_credential_static_id => credential_static_id,
            p_token_url => token_url,
            p_oauth_scope => oauth_scope
        );
    end;

    function get_json(
        p_path   in varchar2,
        o_status out number
    ) return clob is
        l_response clob;
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Accept';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(2).value := lower(rawtohex(sys_guid()));

        l_response := make_request(
            rtrim(ie_mfcs_config.get_config('MFCS_BASE_URL'), '/') || p_path, 'GET');
        o_status := apex_web_service.g_status_code;
        return l_response;
    end;

    -- There is no token here to decode: apex_web_service holds it, and
    -- deliberately exposes neither it nor the secret behind it. Report what can
    -- be known - that the credential exists and what it points at - rather than
    -- nothing, since this is the first thing checked when calls start failing.
    function token_status return clob is
        l_root json_object_t := json_object_t();
        l_ref varchar2(200) := credential_static_id;
        l_count number;
    begin
        l_root.put('mode', 'OAUTH_CLIENT_CREDENTIALS');
        l_root.put('workspace', workspace);
        l_root.put('credentialStaticId', l_ref);
        l_root.put('tokenUrl', token_url);
        l_root.put('scope', oauth_scope);

        begin
            ensure_workspace;
            select count(*) into l_count
              from apex_workspace_credentials
             where static_id = l_ref;
        exception
            when others then
                l_count := 0;
                l_root.put('error', substr(sqlerrm, 1, 400));
        end;

        l_root.put('present', l_count > 0);
        if l_count > 0 then
            -- Not 'valid'. It says a credential is registered, not that the id
            -- and secret in it are right - only a call can show that.
            l_root.put('expired', false);
            l_root.put('message',
                'Credential ' || l_ref || ' is registered. '
                || 'The bearer token is fetched and refreshed automatically.');
        else
            l_root.put('expired', true);
            l_root.put('message',
                'No APEX credential ' || l_ref || ' in workspace ' || workspace
                || '. Create it under Workspace Utilities > Web Credentials: '
                || 'OAuth2 Client Credentials, static id ' || l_ref || '.');
        end if;
        return l_root.to_clob;
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
        l_base_url := ie_mfcs_config.get_config('MFCS_BASE_URL');
        l_endpoint_path := ie_mfcs_config.get_config(p_endpoint_key);

        if instr(l_endpoint_path, '{orderNo}') > 0 then
            select order_no
              into l_order_no
              from ie_mfcs_prd_request
             where action_request_id = p_action_request_id;
            l_endpoint_path := replace(l_endpoint_path, '{orderNo}', l_order_no);
        end if;

        l_endpoint := rtrim(l_base_url, '/') || l_endpoint_path;

        ie_mfcs_step.begin_attempt(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => p_http_method,
            p_endpoint => l_endpoint,
            p_request_payload => p_request_payload,
            o_attempt_id => l_attempt_id,
            o_correlation_id => l_correlation_id
        );

        ie_mfcs_event.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_PREPARED',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Prepared outbound MFCS call.',
            p_detail_payload => '{"endpointKey":"' || ie_mfcs_event.escape_json(p_endpoint_key)
                || '","endpoint":"' || ie_mfcs_event.escape_json(l_endpoint)
                || '","method":"' || ie_mfcs_event.escape_json(p_http_method)
                || '","requestBytes":' || coalesce(to_char(dbms_lob.getlength(p_request_payload)), '0') || '}'
        );

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Accept';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Content-Type';
        apex_web_service.g_request_headers(2).value := 'application/json';
        apex_web_service.g_request_headers(3).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(3).value := l_correlation_id;
        apex_web_service.g_request_headers(4).name := 'X-Client-Principal-User';
        apex_web_service.g_request_headers(4).value := p_user_id;

        ie_mfcs_event.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_START',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Calling remote MFCS endpoint.',
            p_detail_payload => '{"endpointKey":"' || ie_mfcs_event.escape_json(p_endpoint_key)
                || '","endpoint":"' || ie_mfcs_event.escape_json(l_endpoint)
                || '","timeoutSeconds":' || ie_mfcs_config.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45') || '}'
        );

        l_response := make_request(l_endpoint, p_http_method, p_request_payload);
        l_http_status := apex_web_service.g_status_code;

        ie_mfcs_event.log_event(
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
            ie_mfcs_step.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
            return l_response;
        elsif l_http_status = 503 then
            ie_mfcs_step.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20951, 'MFCS service unavailable at ' || p_endpoint_key);
        elsif instr(lower(dbms_lob.substr(l_response, 4000, 1)), 'batch running indicator is on') > 0 then
            -- The tenant's nightly batch. It arrives as a plain HTTP 400 with a
            -- business message, so without this it reads as a rejected payload and
            -- sends you looking for a bug in the request. It is the same condition
            -- BATCH_WINDOW_ACTIVE_YN describes, except the tenant is saying so
            -- itself, which beats a flag somebody has to remember to set.
            ie_mfcs_step.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20951,
                'MFCS is in its nightly batch window and is refusing writes. Retry afterwards.');
        else
            ie_mfcs_step.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20950, 'MFCS returned HTTP ' || l_http_status || ' at ' || p_endpoint_key);
        end if;
    exception
        when others then
            ie_mfcs_event.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'HTTP_CALL_EXCEPTION',
                p_step_code => p_step_code,
                p_attempt_id => l_attempt_id,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode
                    || ',"endpointKey":"' || ie_mfcs_event.escape_json(p_endpoint_key) || '"}'
            );

            if sqlcode in (-20950, -20951, -20952) then
                raise;
            end if;

            -- A transport failure has an *unknown* outcome, not a failed one.
            -- Learned the expensive way: ORA-29273 was classified FAILED, but MFCS
            -- had in fact created the purchase order. The resume then replayed the
            -- create and was told the order number already existed - a reserved
            -- number burned for nothing, and a request stuck at PARTIALLY_COMPLETED
            -- while the order it claimed to have failed to place sat in the tenant.
            --
            -- Classify on SQLCODE, not on the wording of the message. The old test
            -- matched only messages containing "timeout", which ORA-29273 does not.
            -- Codes that never landed resolve to NO_RECORD and the step simply runs
            -- again, so treating a connection error as unknown costs nothing.
            if sqlcode in (-29273,   -- UTL_HTTP: HTTP request failed
                           -29276,   -- UTL_HTTP: transfer timeout
                           -29259,   -- UTL_HTTP: end-of-input reached
                           -12535,   -- TNS: operation timed out
                           -12570)   -- TNS: packet reader failure
               or instr(lower(sqlerrm), 'timeout') > 0 then
                ie_mfcs_step.complete_attempt(l_attempt_id, 'OUTCOME_UNKNOWN', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
                raise_application_error(-20952,
                    'MFCS transport failed after the request was sent; outcome unknown. ' || sqlerrm);
            end if;

            if l_attempt_id is not null then
                ie_mfcs_step.complete_attempt(l_attempt_id, 'FAILED', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
            end if;
            raise_application_error(-20950, sqlerrm);
    end;

    -- Two defects in the original, and together they were dangerous.
    --
    -- It was the one call that bypassed the credential: it set 'Bearer ' || the
    -- static token by hand and passed no credential arguments, so in OAuth mode
    -- it sent an empty bearer and was always answered 401. Routing it through
    -- make_request fixes that, and is the reason make_request exists.
    --
    -- And it returned whatever came back regardless of status. ie_mfcs_recovery
    -- reads a body with no "count" as NO_RECORD and puts the step back to
    -- PENDING, so a 401 - or any failed lookup - re-ran a write that may well
    -- have landed: the duplicate this whole recovery path exists to prevent.
    -- A lookup that did not answer is not evidence that nothing happened, so it
    -- now reports UNKNOWN, which recovery sends to MANUAL_REVIEW.
    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob is
        l_endpoint varchar2(1000);
        l_response clob;
        l_http_status number;
    begin
        l_endpoint := rtrim(ie_mfcs_config.get_config('MFCS_BASE_URL'), '/')
            || ie_mfcs_config.get_config('ENDPOINT.REST_SERVICE_STATUS')
            || '?xCorrelationId=' || p_correlation_id
            || '&includePayload=Y';

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Accept';
        apex_web_service.g_request_headers(1).value := 'application/json';

        l_response := make_request(l_endpoint, 'GET');
        l_http_status := apex_web_service.g_status_code;

        if l_http_status not between 200 and 299 then
            ie_mfcs_event.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'CORRELATION_LOOKUP_FAILED',
                p_event_level => 'ERROR',
                p_message => 'Operation-status lookup answered HTTP ' || l_http_status
                    || '; the outcome stays unknown.',
                p_detail_payload => '{"correlationId":"' || ie_mfcs_event.escape_json(p_correlation_id)
                    || '","httpStatus":' || coalesce(to_char(l_http_status), 'null') || '}'
            );
            return '{"status":"UNKNOWN","httpStatus":' || coalesce(to_char(l_http_status), 'null') || '}';
        end if;

        return l_response;
    end;
end ie_mfcs_client;
/

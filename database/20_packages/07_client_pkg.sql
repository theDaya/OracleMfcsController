set define off

-- Outbound MFCS calls: credentials, HTTP, attempt journalling.
--
-- The only package that resolves a credential or makes an outbound call.
-- Keep it that way: a second HTTP path is how a stale token once survived in
-- one code path and not another. The token is read from SECRET on every call,
-- never cached in a package global - ORDS pools sessions, and a cached
-- credential outlives the request that read it.
--
-- Failure classification matters more than it looks. An HTTP error with a
-- readable body is a failure (-20950); HTTP 503 and the tenant's nightly
-- batch refusal are unavailability (-20951); a transport error after the
-- request may have been sent is an unknown outcome (-20952), resolved later
-- by recovery_pkg - never assume a send that errored did not land.

prompt Creating client_pkg

create or replace package client_pkg authid definer as
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

    -- Decodes the stored bearer token's JWT claims so an expired credential is
    -- diagnosable. Never returns the token itself.
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
end client_pkg;
/

show errors

create or replace package body client_pkg as
    g_access_token varchar2(32767);
    g_token_expires_at timestamp with time zone;

    function get_secret(p_secret_ref in varchar2) return varchar2 is
        l_secret varchar2(32767);
    begin
        begin
            select dbms_lob.substr(secret_value, 32767, 1)
              into l_secret
              from secret
             where secret_ref = p_secret_ref;
        exception
            when no_data_found then
                l_secret := sys_context('MFCS_INTEGRATION_CTX', p_secret_ref);
        end;

        if l_secret is null then
            raise_application_error(
                -20890,
                'MFCS secret ' || p_secret_ref || ' is not configured in SECRET or MFCS_INTEGRATION_CTX.'
            );
        end if;

        return l_secret;
    end;

    function wallet_path return varchar2 is
    begin
        return config_pkg.get_config('MFCS_WALLET_PATH', null);
    end;

    function wallet_password return varchar2 is
        l_secret_ref varchar2(200);
    begin
        l_secret_ref := config_pkg.get_config('MFCS_WALLET_PASSWORD_REF', null);
        if l_secret_ref is null then
            return null;
        end if;
        return get_secret(l_secret_ref);
    end;

    function https_host return varchar2 is
    begin
        return config_pkg.get_config('MFCS_HTTPS_HOST', null);
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
        if config_pkg.get_config('MFCS_AUTH_MODE', 'OAUTH_CLIENT_CREDENTIALS') = 'STATIC_BEARER' then
            l_static_token := trim(get_secret(config_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN')));
            if lower(substr(l_static_token, 1, 7)) = 'bearer ' then
                return trim(substr(l_static_token, 8));
            end if;
            return l_static_token;
        end if;

        if g_access_token is not null
           and g_token_expires_at > systimestamp + interval '60' second then
            return g_access_token;
        end if;

        l_token_url := config_pkg.get_config('MFCS_TOKEN_URL');
        l_client_id := config_pkg.get_config('MFCS_CLIENT_ID');
        l_secret_ref := config_pkg.get_config('MFCS_CLIENT_SECRET_REF');
        l_scope := config_pkg.get_config('MFCS_SCOPE');
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
            p_transfer_timeout => to_number(config_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
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

    function get_json(
        p_path   in varchar2,
        o_status out number
    ) return clob is
        l_response clob;
    begin
        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Bearer ' || access_token;
        apex_web_service.g_request_headers(2).name := 'Accept';
        apex_web_service.g_request_headers(2).value := 'application/json';
        apex_web_service.g_request_headers(3).name := 'X-Correlation-ID';
        apex_web_service.g_request_headers(3).value := lower(rawtohex(sys_guid()));

        l_response := apex_web_service.make_rest_request(
            p_url => rtrim(config_pkg.get_config('MFCS_BASE_URL'), '/') || p_path,
            p_http_method => 'GET',
            p_wallet_path => wallet_path,
            p_wallet_pwd => wallet_password,
            p_https_host => https_host,
            p_transfer_timeout => to_number(config_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );
        o_status := apex_web_service.g_status_code;
        return l_response;
    end;

    function token_status return clob is
        l_root json_object_t := json_object_t();
        l_ref varchar2(200);
        l_token varchar2(32767);
        l_seg varchar2(32767);
        l_json varchar2(32767);
        l_claims json_object_t;
        l_exp number;
        l_iat number;
        l_now number;
    begin
        l_ref := config_pkg.get_config('MFCS_BEARER_TOKEN_REF', 'MFCS_BEARER_TOKEN');
        l_root.put('secretRef', l_ref);

        begin
            select dbms_lob.substr(secret_value, 32767, 1) into l_token
              from secret where secret_ref = l_ref;
        exception
            when no_data_found then
                l_root.put('present', false);
                l_root.put('message', 'No row in SECRET under ref ' || l_ref || '.');
                return l_root.to_clob;
        end;

        l_token := trim(l_token);
        if lower(substr(l_token, 1, 7)) = 'bearer ' then
            l_token := trim(substr(l_token, 8));
        end if;

        l_root.put('present', true);
        l_root.put('length', length(l_token));
        l_root.put('segments', length(l_token) - length(replace(l_token, '.', '')) + 1);

        -- Middle JWT segment, base64url-decoded.
        l_seg := regexp_substr(l_token, '[^.]+', 1, 2);
        if l_seg is null then
            l_root.put('message', 'Not a JWT; cannot read expiry.');
            return l_root.to_clob;
        end if;

        l_seg := replace(replace(l_seg, '-', '+'), '_', '/');
        l_seg := l_seg || rpad('=', mod(4 - mod(length(l_seg), 4), 4), '=');

        begin
            l_json := utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(l_seg)));
            l_claims := json_object_t.parse(l_json);
            l_exp := l_claims.get_number('exp');
            l_iat := l_claims.get_number('iat');
        exception
            when others then
                l_root.put('message', 'Could not decode JWT claims: ' || substr(sqlerrm, 1, 200));
                return l_root.to_clob;
        end;

        l_now := (cast(systimestamp at time zone 'UTC' as date) - date '1970-01-01') * 86400;

        if l_iat is not null then
            l_root.put('issuedAt', to_char(date '1970-01-01' + l_iat / 86400, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
        end if;
        if l_exp is not null then
            l_root.put('expiresAt', to_char(date '1970-01-01' + l_exp / 86400, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
            l_root.put('expired', l_exp < l_now);
            l_root.put('secondsRemaining', round(l_exp - l_now));
            l_root.put('message',
                case when l_exp < l_now
                     then 'Token expired ' || round((l_now - l_exp) / 60) || ' minute(s) ago. Re-issue it in Postman.'
                     else 'Token valid for a further ' || round((l_exp - l_now) / 60) || ' minute(s).'
                end);
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
        l_base_url := config_pkg.get_config('MFCS_BASE_URL');
        l_endpoint_path := config_pkg.get_config(p_endpoint_key);

        if instr(l_endpoint_path, '{orderNo}') > 0 then
            select order_no
              into l_order_no
              from request
             where action_request_id = p_action_request_id;
            l_endpoint_path := replace(l_endpoint_path, '{orderNo}', l_order_no);
        end if;

        l_endpoint := rtrim(l_base_url, '/') || l_endpoint_path;

        step_pkg.begin_attempt(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => p_http_method,
            p_endpoint => l_endpoint,
            p_request_payload => p_request_payload,
            o_attempt_id => l_attempt_id,
            o_correlation_id => l_correlation_id
        );

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_PREPARED',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Prepared outbound MFCS call.',
            p_detail_payload => '{"endpointKey":"' || event_pkg.escape_json(p_endpoint_key)
                || '","endpoint":"' || event_pkg.escape_json(l_endpoint)
                || '","method":"' || event_pkg.escape_json(p_http_method)
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

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'HTTP_CALL_START',
            p_step_code => p_step_code,
            p_attempt_id => l_attempt_id,
            p_message => 'Calling remote MFCS endpoint.',
            p_detail_payload => '{"endpointKey":"' || event_pkg.escape_json(p_endpoint_key)
                || '","endpoint":"' || event_pkg.escape_json(l_endpoint)
                || '","timeoutSeconds":' || config_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45') || '}'
        );

        l_response := apex_web_service.make_rest_request(
            p_url => l_endpoint,
            p_http_method => p_http_method,
            p_body => p_request_payload,
            p_wallet_path => wallet_path,
            p_wallet_pwd => wallet_password,
            p_https_host => https_host,
            p_transfer_timeout => to_number(config_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );
        l_http_status := apex_web_service.g_status_code;

        event_pkg.log_event(
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
            step_pkg.complete_attempt(l_attempt_id, 'SUCCEEDED', l_http_status, l_response);
            return l_response;
        elsif l_http_status = 503 then
            step_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20951, 'MFCS service unavailable at ' || p_endpoint_key);
        elsif instr(lower(dbms_lob.substr(l_response, 4000, 1)), 'batch running indicator is on') > 0 then
            -- The tenant's nightly batch. It arrives as a plain HTTP 400 with a
            -- business message, so without this it reads as a rejected payload and
            -- sends you looking for a bug in the request. It is the same condition
            -- BATCH_WINDOW_ACTIVE_YN describes, except the tenant is saying so
            -- itself, which beats a flag somebody has to remember to set.
            step_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20951,
                'MFCS is in its nightly batch window and is refusing writes. Retry afterwards.');
        else
            step_pkg.complete_attempt(l_attempt_id, 'FAILED', l_http_status, l_response);
            raise_application_error(-20950, 'MFCS returned HTTP ' || l_http_status || ' at ' || p_endpoint_key);
        end if;
    exception
        when others then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'HTTP_CALL_EXCEPTION',
                p_step_code => p_step_code,
                p_attempt_id => l_attempt_id,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode
                    || ',"endpointKey":"' || event_pkg.escape_json(p_endpoint_key) || '"}'
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
                step_pkg.complete_attempt(l_attempt_id, 'OUTCOME_UNKNOWN', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
                raise_application_error(-20952,
                    'MFCS transport failed after the request was sent; outcome unknown. ' || sqlerrm);
            end if;

            if l_attempt_id is not null then
                step_pkg.complete_attempt(l_attempt_id, 'FAILED', null, '{"ERROR":"' || replace(sqlerrm, '"', '\"') || '"}');
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
        l_endpoint := rtrim(config_pkg.get_config('MFCS_BASE_URL'), '/')
            || config_pkg.get_config('ENDPOINT.REST_SERVICE_STATUS')
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
            p_transfer_timeout => to_number(config_pkg.get_config('HTTP_TRANSFER_TIMEOUT_SECONDS', '45'))
        );

        return l_response;
    end;
end client_pkg;
/

show errors

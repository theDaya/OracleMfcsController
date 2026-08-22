set define off

-- Builds the MFCS call plan without sending anything.

prompt Creating preview_pkg

create or replace package preview_pkg authid definer as
    -- Builds, but does not send, the full MFCS call plan for an Office payload.
    --
    -- Returns both halves of the picture in one response:
    --   INBOUND_PAYLOAD - the Office/PLM-shaped request as received by this layer
    --   MFCS_CALLS      - the ordered per-endpoint payloads the orchestrator would send
    --
    -- Nothing is sent to MFCS and no request survives the call: a throwaway
    -- PREVIEW- request is registered so the existing mappers can run against it,
    -- then removed. Reuses the orchestrator's own step graph and endpoint
    -- resolution, so a preview cannot drift from what execution would actually do.
    procedure preview_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    );
end preview_pkg;
/

show errors

create or replace package body preview_pkg as

    procedure purge_preview(p_action_request_id in varchar2) is
    begin
        delete from event_log where action_request_id = p_action_request_id;
        delete from attempt where action_request_id = p_action_request_id;
        delete from step where action_request_id = p_action_request_id;
        delete from request where action_request_id = p_action_request_id;
        commit;
    exception
        when others then
            null;
    end;

    -- Embed a built payload as real JSON where possible, or as a diagnostic
    -- object when a mapper emits something that is not parseable JSON.
    function as_json(p_clob in clob) return json_element_t is
        l_obj json_object_t;
    begin
        if p_clob is null or dbms_lob.getlength(p_clob) = 0 then
            return json_object_t();
        end if;
        return json_element_t.parse(p_clob);
    exception
        when others then
            l_obj := json_object_t();
            l_obj.put('unparseable', true);
            l_obj.put('raw', dbms_lob.substr(p_clob, 4000, 1));
            return l_obj;
    end;

    procedure preview_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    ) is
        l_operation varchar2(30);
        l_action_request_id varchar2(100);
        l_preview_id varchar2(100);
        l_valid boolean;
        l_errors clob;
        l_result varchar2(30);
        l_status varchar2(40);
        l_existing clob;
        l_root json_object_t := json_object_t();
        l_calls json_array_t := json_array_t();
        l_call json_object_t;
        l_base varchar2(400);
        l_resolution orchestrator_pkg.t_step_resolution;
        l_endpoint_key varchar2(200);
        l_endpoint_path varchar2(1000);
        l_method varchar2(10);
        l_step_payload clob;
    begin
        select json_value(p_payload, '$.OPERATION_NAME' returning varchar2(30) null on error),
               json_value(p_payload, '$.ACTION_REQUEST_ID' returning varchar2(100) null on error)
          into l_operation, l_action_request_id
          from dual;

        l_root.put('ACTION_REQUEST_ID', l_action_request_id);
        l_root.put('OPERATION_NAME', l_operation);

        if trim(l_operation) is null
           or l_operation not in ('CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL') then
            l_root.put('VALID', false);
            l_root.put('ERRORS', json_element_t.parse(
                '[{"FIELD":"OPERATION_NAME","CODE":"UNSUPPORTED_OPERATION",'
                || '"MESSAGE":"OPERATION_NAME must be one of CREATE_STYLE, MODIFY_STYLE, CREATE_ORDER, MODIFY_ORDER, CREATE_ALL."}]'));
            l_root.put('MFCS_CALLS', json_array_t());
            o_http_status := 400;
            o_response := l_root.to_clob;
            return;
        end if;

        -- Validate before touching any table.
        l_valid := validation_pkg.validate_request(p_payload, l_errors);
        if not l_valid then
            l_root.put('VALID', false);
            l_root.put('ERRORS', as_json(l_errors));
            l_root.put('INBOUND_PAYLOAD', as_json(p_payload));
            l_root.put('MFCS_CALLS', json_array_t());
            o_http_status := 422;
            o_response := l_root.to_clob;
            return;
        end if;

        -- Register under a throwaway id so the real request table is untouched
        -- and an existing ACTION_REQUEST_ID is never disturbed.
        l_preview_id := 'PREVIEW-' || lower(rawtohex(sys_guid()));

        request_pkg.register_request(
            p_action_request_id => l_preview_id,
            p_operation_name => l_operation,
            p_payload_hash => request_pkg.payload_hash(p_payload),
            p_payload => p_payload,
            o_result => l_result,
            o_status => l_status,
            o_response_payload => l_existing
        );

        step_pkg.initialize_steps(l_preview_id, l_operation);

        l_base := rtrim(config_pkg.get_config('MFCS_BASE_URL'), '/');

        for s in (
            select step_code, step_sequence
              from step
             where action_request_id = l_preview_id
             order by step_sequence
        ) loop
            l_resolution := orchestrator_pkg.resolve_step(s.step_code, l_operation);
            l_endpoint_key := l_resolution.endpoint_key;

            l_call := json_object_t();
            l_call.put('sequence', s.step_sequence);
            l_call.put('stepCode', s.step_code);

            if l_endpoint_key is null then
                -- No endpoint the plan can name. Either the step is local, or - for
                -- ENSURE_STYLE_SKUS - which calls it makes depends on what the tenant
                -- already holds, which a preview deliberately does not go and look at.
                l_call.put('local', true);
                l_call.put('method', 'LOCAL');
                if s.step_code = 'SYNC_ORDER_LINES' then
                    l_call.put('description',
                        'Reads the order back and brings its lines to what the document says: '
                        || 'updates through purchaseOrder/details/update, additions through '
                        || 'details/create, and this style''s no-longer-named lines cancelled with '
                        || 'cancelInd. The bulk purchaseOrders/update ignores its details array on '
                        || 'this tenant, so the header step cannot do this work.');
                elsif s.step_code = 'ENSURE_STYLE_SKUS' then
                    l_call.put('description',
                        'Reads the style back and compares it against the requested colour and '
                        || 'size curve. Any combination the style lacks is created here - reserve '
                        || 'a number, create the child, add sourcing and country of manufacture, '
                        || 'approve - then the style is read again to confirm it took. The calls '
                        || 'depend on what the tenant already has, so they cannot be planned ahead.');
                else
                    l_call.put('description', 'Performed inside the integration layer; no MFCS call.');
                end if;
            else
                l_method := l_resolution.http_method;
                l_endpoint_path := config_pkg.get_config(l_endpoint_key);

                begin
                    l_step_payload := orchestrator_pkg.payload_for_step(l_preview_id, s.step_code);
                exception
                    when others then
                        l_step_payload := null;
                end;

                l_call.put('local', false);
                l_call.put('method', l_method);
                l_call.put('endpointKey', l_endpoint_key);
                l_call.put('endpointPath', l_endpoint_path);
                l_call.put('url', l_base || l_endpoint_path);
                l_call.put('payload', as_json(l_step_payload));
            end if;

            l_calls.append(l_call);
        end loop;

        purge_preview(l_preview_id);

        l_root.put('VALID', true);
        l_root.put('ERRORS', json_array_t());
        l_root.put('INBOUND_PAYLOAD', as_json(p_payload));
        l_root.put('MFCS_CALLS', l_calls);
        l_root.put('NOTE',
            'Preview only - nothing was sent to MFCS. Identifiers that MFCS generates '
            || '(item numbers, order numbers) are not known until the request actually runs, '
            || 'so they appear null or unresolved here.');

        o_http_status := 200;
        o_response := l_root.to_clob;
    exception
        when others then
            if l_preview_id is not null then
                purge_preview(l_preview_id);
            end if;
            o_http_status := 500;
            o_response := '{"VALID":false,"ERRORS":[{"FIELD":null,"CODE":"PREVIEW_FAILED","MESSAGE":"'
                || replace(replace(substr(sqlerrm, 1, 500), '\', '\\'), '"', '\"') || '"}],"MFCS_CALLS":[]}';
    end;
end preview_pkg;
/

show errors

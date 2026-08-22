set define off

prompt Creating OFFICE MFCS preview and UI-support ORDS handlers

declare
    l_origins owa.vc_arr;
begin
    -- Adds to the existing mfcs-v1 module rather than defining a new one.
    ords.define_template(
        p_module_name => 'mfcs-v1',
        p_pattern => 'transactions/preview'
    );

    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'transactions/preview',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    preview_pkg.preview_transaction(:body_text, l_http_status, l_response);
    :status_code := l_http_status;
    ords_util_pkg.emit_json(l_response);
end;
]'
    );

    -- Reference data for the entry form, read straight from CONFIG so
    -- the UI offers exactly the values this environment can actually map.
    ords.define_template(
        p_module_name => 'mfcs-v1',
        p_pattern => 'reference-data'
    );

    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'reference-data',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_arr json_array_t;
    l_item json_object_t;

    procedure collect(p_prefix in varchar2, p_name in varchar2) is
        l_local json_array_t := json_array_t();
        l_entry json_object_t;
    begin
        for c in (
            select substr(config_key, length(p_prefix) + 1) code,
                   dbms_lob.substr(config_value, 400, 1) mapped
              from config
             where config_key like p_prefix || '%'
               and environment = 'DEFAULT'
               and enabled_ind = 'Y'
             order by 1
        ) loop
            l_entry := json_object_t();
            l_entry.put('code', c.code);
            l_entry.put('mapped', c.mapped);
            l_local.append(l_entry);
        end loop;
        l_root.put(p_name, l_local);
    end;
begin
    collect('MAP.DEPARTMENT.', 'departments');
    collect('MAP.CLASS.', 'classes');
    collect('MAP.SUBCLASS.', 'subclasses');
    collect('MAP.SUPPLIER.', 'suppliers');
    collect('MAP.COUNTRY.', 'countries');
    collect('MAP.CURRENCY.', 'currencies');
    collect('MAP.COLOUR.', 'colours');
    collect('MAP.SIZE.', 'sizes');
    collect('MAP.WIDTH.', 'widths');
    collect('MAP.ORDER_LOCATION.', 'orderLocations');
    collect('ENDPOINT.', 'endpoints');

    l_arr := json_array_t();
    for o in (
        select column_value op from table(sys.odcivarchar2list(
            'CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL', 'MODIFY_STYLE', 'MODIFY_ORDER'))
    ) loop
        l_arr.append(o.op);
    end loop;
    l_root.put('operations', l_arr);

    l_item := json_object_t();
    for c in (
        select config_key, dbms_lob.substr(config_value, 400, 1) v
          from config
         where environment = 'DEFAULT'
           and enabled_ind = 'Y'
           and config_key in ('MFCS_AUTH_MODE', 'MFCS_BASE_URL',
                              'FEATURE_ITEM_LOCATIONS_YN', 'FEATURE_INITIAL_RETAIL_YN',
                              'BATCH_WINDOW_ACTIVE_YN')
    ) loop
        l_item.put(c.config_key, c.v);
    end loop;
    l_root.put('runtime', l_item);

    ords_util_pkg.emit_json(l_root.to_clob);
end;
]'
    );

    -- Recent requests, so the UI can show what has been submitted and its outcome.
    ords.define_template(
        p_module_name => 'mfcs-v1',
        p_pattern => 'requests'
    );

    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'requests',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_arr json_array_t := json_array_t();
    l_row json_object_t;
begin
    for r in (
        select q.action_request_id, q.operation_name, q.request_status,
               q.style_no, q.order_no,
               to_char(q.last_updated_at, 'YYYY-MM-DD"T"HH24:MI:SS') updated,
               (select count(*) from step s where s.action_request_id = q.action_request_id) steps,
               (select count(*) from step s where s.action_request_id = q.action_request_id
                                              and s.step_status = 'SUCCEEDED') done,
               (select max(s.step_code) from step s where s.action_request_id = q.action_request_id
                                              and s.step_status in ('FAILED', 'OUTCOME_UNKNOWN')) failed_step
          from request q
         where q.action_request_id not like 'PREVIEW-%'
         order by q.last_updated_at desc
         fetch first 100 rows only
    ) loop
        l_row := json_object_t();
        l_row.put('actionRequestId', r.action_request_id);
        l_row.put('operationName', r.operation_name);
        l_row.put('requestStatus', r.request_status);
        l_row.put('styleNo', r.style_no);
        l_row.put('orderNo', r.order_no);
        l_row.put('lastUpdatedAt', r.updated);
        l_row.put('stepCount', r.steps);
        l_row.put('stepsSucceeded', r.done);
        l_row.put('failedStep', r.failed_step);
        l_arr.append(l_row);
    end loop;
    l_root.put('items', l_arr);
    ords_util_pkg.emit_json(l_root.to_clob);
end;
]'
    );

    -- Everything recorded about one request: the step graph, every HTTP attempt
    -- with its payloads, and the autonomous event log. This is what turns a
    -- PARTIALLY_COMPLETED status into an explanation.
    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'requests/:id');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'requests/:id',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_arr json_array_t;
    l_row json_object_t;
    l_found number := 0;
begin
    for r in (
        select action_request_id, operation_name, request_status, style_no, order_no,
               request_payload, response_payload,
               to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS') created,
               to_char(last_updated_at, 'YYYY-MM-DD"T"HH24:MI:SS') updated
          from request where action_request_id = :id
    ) loop
        l_found := 1;
        l_root.put('actionRequestId', r.action_request_id);
        l_root.put('operationName', r.operation_name);
        l_root.put('requestStatus', r.request_status);
        l_root.put('styleNo', r.style_no);
        l_root.put('orderNo', r.order_no);
        l_root.put('createdAt', r.created);
        l_root.put('lastUpdatedAt', r.updated);
        begin
            l_root.put('requestPayload', json_element_t.parse(r.request_payload));
        exception when others then null; end;
        begin
            l_root.put('responsePayload', json_element_t.parse(r.response_payload));
        exception when others then null; end;
    end loop;

    if l_found = 0 then
        :status_code := 404;
        ords_util_pkg.emit_json('{"error":"No such request."}');
        return;
    end if;

    l_arr := json_array_t();
    for st in (select step_sequence, step_code, step_status, entity_identifier,
                      last_error_code, last_error_message
                 from step where action_request_id = :id order by step_sequence) loop
        l_row := json_object_t();
        l_row.put('sequence', st.step_sequence);
        l_row.put('stepCode', st.step_code);
        l_row.put('stepStatus', st.step_status);
        l_row.put('entityIdentifier', st.entity_identifier);
        l_row.put('lastErrorCode', st.last_error_code);
        l_row.put('lastErrorMessage', st.last_error_message);
        l_arr.append(l_row);
    end loop;
    l_root.put('steps', l_arr);

    l_arr := json_array_t();
    for a in (select attempt_id, attempt_number, step_code, http_method, endpoint,
                     http_status, attempt_status, correlation_id,
                     request_payload, response_payload,
                     to_char(started_at, 'YYYY-MM-DD"T"HH24:MI:SS') started
                from attempt where action_request_id = :id order by attempt_id) loop
        l_row := json_object_t();
        l_row.put('attemptId', a.attempt_id);
        l_row.put('attemptNumber', a.attempt_number);
        l_row.put('stepCode', a.step_code);
        l_row.put('method', a.http_method);
        l_row.put('endpoint', a.endpoint);
        l_row.put('httpStatus', a.http_status);
        l_row.put('attemptStatus', a.attempt_status);
        l_row.put('correlationId', a.correlation_id);
        l_row.put('startedAt', a.started);
        begin
            l_row.put('requestPayload', json_element_t.parse(a.request_payload));
        exception when others then
            l_row.put('requestPayload', substr(dbms_lob.substr(a.request_payload, 4000, 1), 1, 4000));
        end;
        begin
            l_row.put('responsePayload', json_element_t.parse(a.response_payload));
        exception when others then
            l_row.put('responsePayload', substr(dbms_lob.substr(a.response_payload, 4000, 1), 1, 4000));
        end;
        l_arr.append(l_row);
    end loop;
    l_root.put('attempts', l_arr);

    l_arr := json_array_t();
    for e in (select log_id, event_phase, event_level, step_code, message,
                     to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS') logged
                from event_log where action_request_id = :id order by log_id) loop
        l_row := json_object_t();
        l_row.put('logId', e.log_id);
        l_row.put('phase', e.event_phase);
        l_row.put('level', e.event_level);
        l_row.put('stepCode', e.step_code);
        l_row.put('message', e.message);
        l_row.put('loggedAt', e.logged);
        l_arr.append(l_row);
    end loop;
    l_root.put('events', l_arr);

    ords_util_pkg.emit_json(l_root.to_clob);
end;
]'
    );

    commit;
end;
/


-- Allow the React dev server to call these handlers.
begin
    ords.delete_privilege_mapping(
        p_privilege_name => 'mfcs-resume-support',
        p_pattern => '/mfcs/v1/transactions/preview'
    );
exception
    when others then null;
end;
/

prompt OFFICE MFCS preview and UI-support ORDS handlers created

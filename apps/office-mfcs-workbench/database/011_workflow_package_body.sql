set define off

create or replace package body office_workflow_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_WORKFLOW_PKG';

    -- JSON and error helpers keep transport formatting out of workflow actions.
    function iso_now return varchar2 is
    begin
        return to_char(systimestamp at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"');
    end;

    function parse_timestamp(p_value in varchar2) return timestamp with time zone is
    begin
        return to_timestamp_tz(replace(p_value, 'Z', '+00:00'), 'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM');
    exception when others then
        return systimestamp;
    end;

    procedure fail(p_code in varchar2, p_message in varchar2) is
    begin
        raise_application_error(-20001, p_code || '|' || p_message);
    end;

    function error_json(p_code in varchar2, p_message in varchar2) return clob is
    begin
        return office_workflow_http_pkg.error_json(p_code, p_message);
    end;

    procedure response_error(
        p_operation_name in varchar2,
        p_request_id     in varchar2,
        p_http_status    out number,
        p_response       out clob
    ) is
        l_error varchar2(4000) := sqlerrm;
        l_sql_code number := sqlcode;
        l_separator number;
        l_code varchar2(100);
        l_message varchar2(4000);
    begin
        rollback;
        if l_sql_code = -20001 then
            l_error := substr(l_error, instr(l_error, ': ') + 2);
            l_separator := instr(l_error, '|');
            l_code := substr(l_error, 1, l_separator - 1);
            l_message := substr(l_error, l_separator + 1);
            p_http_status := case when l_code = 'NOT_FOUND' then 404 when l_code = 'CONFLICT' then 409 else 422 end;
        else
            l_code := 'INTERNAL_ERROR';
            l_message := l_error;
            p_http_status := 500;
        end if;
        p_response := error_json(l_code, l_message);
        office_workflow_log_pkg.error(
            c_package_name, p_operation_name, p_request_id,
            l_code || ': ' || l_message, dbms_utility.format_error_backtrace
        );
    end;

    procedure actor_values(
        p_actor_json in clob,
        p_actor_id out varchar2,
        p_actor_name out varchar2,
        p_actor_role out varchar2
    ) is
    begin
        select json_value(p_actor_json, '$.id' returning varchar2(200)),
               json_value(p_actor_json, '$.name' returning varchar2(200)),
               json_value(p_actor_json, '$.role' returning varchar2(20))
          into p_actor_id, p_actor_name, p_actor_role
          from dual;
        if p_actor_id is null or p_actor_name is null or p_actor_role not in ('BUYER', 'MANAGER') then
            fail('INVALID_ACTOR', 'A valid simulated user is required.');
        end if;
    end;

    -- Persistence helpers own row locking, JSON state, and history writes.
    procedure add_history(
        p_request_id in varchar2,
        p_request in out nocopy json_object_t,
        p_action in varchar2,
        p_actor_id in varchar2,
        p_actor_name in varchar2,
        p_actor_role in varchar2,
        p_source_version in number,
        p_comment in varchar2 default null
    ) is
        l_history json_array_t;
        l_entry json_object_t := json_object_t();
        l_id varchar2(36) := lower(rawtohex(sys_guid()));
    begin
        if p_request.has('approvalHistory') and not p_request.get('approvalHistory').is_null then
            l_history := p_request.get_array('approvalHistory');
        else
            l_history := json_array_t();
        end if;
        l_entry.put('id', l_id);
        l_entry.put('action', p_action);
        l_entry.put('actorId', p_actor_id);
        l_entry.put('actorName', p_actor_name);
        l_entry.put('at', iso_now);
        l_entry.put('sourceVersion', p_source_version);
        if p_comment is not null then l_entry.put('comment', p_comment); end if;
        l_history.append(l_entry);
        p_request.put('approvalHistory', l_history);

        insert into office_workflow_history(
            history_id, request_id, action_name, actor_id, actor_name, actor_role,
            source_version, action_comment
        ) values (
            office_workflow_history_seq.nextval, p_request_id, p_action, p_actor_id,
            p_actor_name, p_actor_role, p_source_version, p_comment
        );
    end;

    procedure persist_existing(
        p_request_id in varchar2,
        p_request in json_object_t,
        p_payload in clob default null,
        p_response in clob default null
    ) is
        l_json clob := p_request.to_clob;
        l_submitted_value varchar2(50);
        l_approved_value varchar2(50);
        l_submitted_at timestamp with time zone;
        l_approved_at timestamp with time zone;
    begin
        l_submitted_value := json_value(l_json, '$.submittedAt' returning varchar2(50) null on error);
        l_approved_value := json_value(l_json, '$.approvedAt' returning varchar2(50) null on error);
        if l_submitted_value is not null then l_submitted_at := parse_timestamp(l_submitted_value); end if;
        if l_approved_value is not null then l_approved_at := parse_timestamp(l_approved_value); end if;
        update office_workflow_request
           set workflow_status = json_value(l_json, '$.status' returning varchar2(30)),
               source_version = json_value(l_json, '$.sourceVersion' returning number),
               action_request_id = json_value(l_json, '$.actionRequestId' returning varchar2(80) null on error),
               style_description = json_value(l_json, '$.style.description' returning varchar2(250) null on error),
               submitted_by_id = json_value(l_json, '$.submittedBy.id' returning varchar2(200) null on error),
               approved_by_id = json_value(l_json, '$.approvedBy.id' returning varchar2(200) null on error),
               updated_at = systimestamp,
               submitted_at = l_submitted_at,
               approved_at = l_approved_at,
               request_json = l_json,
               integration_payload = coalesce(p_payload, integration_payload),
               integration_response = coalesce(p_response, integration_response)
         where request_id = p_request_id;
        if sql%rowcount = 0 then fail('NOT_FOUND', 'Workflow request was not found.'); end if;
    end;

    function request_object(p_request_id in varchar2) return json_object_t is
        l_json clob;
    begin
        select request_json into l_json from office_workflow_request where request_id = p_request_id for update;
        return json_object_t.parse(l_json);
    exception when no_data_found then
        fail('NOT_FOUND', 'Workflow request was not found.');
        return null;
    end;

    function actor_object(p_actor_json in clob) return json_object_t is
    begin
        return json_object_t.parse(p_actor_json);
    end;

    procedure apply_integration_response(
        p_request in out nocopy json_object_t,
        p_response in clob
    ) is
        l_status varchar2(30);
        l_workflow_status varchar2(30);
    begin
        select json_value(p_response, '$.STATUS' returning varchar2(30) null on error)
          into l_status from dual;
        l_workflow_status := case
            when l_status = 'COMPLETED' then 'POSTED'
            when l_status = 'PARTIALLY_COMPLETED' then 'PARTIALLY_COMPLETED'
            when l_status in ('OUTCOME_UNKNOWN', 'MANUAL_REVIEW') then 'MANUAL_REVIEW'
            else 'FAILED'
        end;
        p_request.put('status', l_workflow_status);
        p_request.put('updatedAt', iso_now);
        p_request.put('integrationResponse', json_object_t.parse(p_response));
    end;

    -- Public workflow commands. Each command commits one state transition and
    -- delegates MFCS integration to the controller package where required.
    procedure list_requests(p_status in varchar2 default null, p_http_status out number, p_response out clob) is
    begin
        select json_arrayagg(request_json format json order by updated_at desc returning clob)
          into p_response
          from office_workflow_request
         where p_status is null or workflow_status = upper(p_status);
        if p_response is null then p_response := '[]'; end if;
        p_http_status := 200;
    exception when others then response_error('LIST_REQUESTS', null, p_http_status, p_response);
    end;

    procedure get_request(p_request_id in varchar2, p_http_status out number, p_response out clob) is
    begin
        select request_json into p_response from office_workflow_request where request_id = p_request_id;
        p_http_status := 200;
    exception
        when no_data_found then
            p_http_status := 404;
            p_response := error_json('NOT_FOUND', 'Workflow request was not found.');
            office_workflow_log_pkg.info(c_package_name, 'GET_REQUEST', p_request_id, 'Request was not found');
        when others then response_error('GET_REQUEST', p_request_id, p_http_status, p_response);
    end;

    procedure save_draft(p_request_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_request_id varchar2(36);
        l_existing_status varchar2(30);
        l_count number;
        l_total_quantity number;
        l_cost number;
        l_created_at varchar2(50);
        l_created_timestamp timestamp with time zone;
    begin
        if p_request_json is null or not (p_request_json is json) then fail('INVALID_JSON', 'Request body must be valid JSON.'); end if;
        l_request := json_object_t.parse(p_request_json);
        l_request_id := json_value(p_request_json, '$.id' returning varchar2(36));
        if l_request_id is null then fail('REQUIRED', 'Request id is required.'); end if;
        select count(*), max(workflow_status) into l_count, l_existing_status from office_workflow_request where request_id = l_request_id;
        if l_count > 0 and l_existing_status <> 'DRAFT' then fail('CONFLICT', 'Only draft requests can be edited.'); end if;
        if json_value(p_request_json, '$.status' returning varchar2(30)) <> 'DRAFT' then fail('CONFLICT', 'Draft save requires DRAFT status.'); end if;
        select coalesce(sum(quantity), 0) into l_total_quantity
          from json_table(p_request_json, '$.variants[*]' columns quantity number path '$.quantity');
        l_cost := coalesce(json_value(p_request_json, '$.sourcing.costPrice' returning number null on error), 0);
        l_created_at := json_value(p_request_json, '$.createdAt' returning varchar2(50));
        l_created_timestamp := parse_timestamp(l_created_at);

        if l_count = 0 then
            insert into office_workflow_request(
                request_id, office_reference, operation_name, workflow_status,
                source_style_ref, source_order_ref, source_version, style_description,
                supplier, total_quantity, total_cost, created_by_id, created_by_name,
                created_at, updated_at, request_json
            ) values (
                l_request_id,
                json_value(p_request_json, '$.officeReference' returning varchar2(40)),
                json_value(p_request_json, '$.operationName' returning varchar2(30)),
                'DRAFT',
                json_value(p_request_json, '$.sourceStyleRef' returning varchar2(120)),
                json_value(p_request_json, '$.sourceOrderRef' returning varchar2(120)),
                json_value(p_request_json, '$.sourceVersion' returning number),
                json_value(p_request_json, '$.style.description' returning varchar2(250)),
                json_value(p_request_json, '$.sourcing.supplier' returning number),
                l_total_quantity, l_total_quantity * l_cost,
                json_value(p_request_json, '$.createdBy.id' returning varchar2(200)),
                json_value(p_request_json, '$.createdBy.name' returning varchar2(200)),
                l_created_timestamp, systimestamp, p_request_json
            );
        else
            update office_workflow_request
               set office_reference = json_value(p_request_json, '$.officeReference' returning varchar2(40)),
                   operation_name = json_value(p_request_json, '$.operationName' returning varchar2(30)),
                   source_version = json_value(p_request_json, '$.sourceVersion' returning number),
                   style_description = json_value(p_request_json, '$.style.description' returning varchar2(250)),
                   supplier = json_value(p_request_json, '$.sourcing.supplier' returning number),
                   total_quantity = l_total_quantity,
                   total_cost = l_total_quantity * l_cost,
                   updated_at = systimestamp,
                   request_json = p_request_json
             where request_id = l_request_id;
        end if;
        commit;
        select request_json into p_response from office_workflow_request where request_id = l_request_id;
        p_http_status := case when l_count = 0 then 201 else 200 end;
        office_workflow_log_pkg.info(c_package_name, 'SAVE_DRAFT', l_request_id, case when l_count = 0 then 'Draft created' else 'Draft updated' end);
    exception when others then response_error('SAVE_DRAFT', l_request_id, p_http_status, p_response);
    end;

    procedure delete_draft(p_request_id in varchar2, p_http_status out number, p_response out clob) is
    begin
        delete from office_workflow_request where request_id = p_request_id and workflow_status = 'DRAFT';
        if sql%rowcount = 0 then fail('CONFLICT', 'Only an existing draft can be deleted.'); end if;
        commit;
        p_http_status := 204;
        p_response := null;
        office_workflow_log_pkg.info(c_package_name, 'DELETE_DRAFT', p_request_id, 'Draft deleted');
    exception when others then response_error('DELETE_DRAFT', p_request_id, p_http_status, p_response);
    end;

    procedure submit_request(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
        l_version number;
    begin
        actor_values(p_actor_json, l_actor_id, l_actor_name, l_actor_role);
        l_request := request_object(p_request_id);
        if l_actor_role <> 'BUYER' or l_request.get_string('status') <> 'DRAFT' then fail('CONFLICT', 'Only a buyer can submit a draft.'); end if;
        if l_request.get_object('createdBy').get_string('id') <> l_actor_id then fail('FORBIDDEN', 'Only the creating buyer can submit this request.'); end if;
        l_version := l_request.get_number('sourceVersion');
        l_request.put('status', 'SUBMITTED');
        l_request.put('submittedBy', actor_object(p_actor_json));
        l_request.put('submittedAt', iso_now);
        l_request.put('updatedAt', iso_now);
        add_history(p_request_id, l_request, 'SUBMITTED', l_actor_id, l_actor_name, l_actor_role, l_version);
        persist_existing(p_request_id, l_request);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'SUBMIT_REQUEST', p_request_id, 'Request submitted');
    exception when others then response_error('SUBMIT_REQUEST', p_request_id, p_http_status, p_response);
    end;

    procedure begin_correction(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
    begin
        actor_values(p_actor_json, l_actor_id, l_actor_name, l_actor_role);
        l_request := request_object(p_request_id);
        if l_actor_role <> 'BUYER' or l_request.get_string('status') <> 'RETURNED' then fail('CONFLICT', 'Only a buyer can correct a returned request.'); end if;
        if l_request.get_object('createdBy').get_string('id') <> l_actor_id then fail('FORBIDDEN', 'Only the creating buyer can correct this request.'); end if;
        l_request.put('status', 'DRAFT');
        l_request.put('sourceVersion', l_request.get_number('sourceVersion') + 1);
        l_request.remove('submittedBy'); l_request.remove('submittedAt'); l_request.remove('approvedBy'); l_request.remove('approvedAt');
        l_request.put('updatedAt', iso_now);
        persist_existing(p_request_id, l_request);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'BEGIN_CORRECTION', p_request_id, 'Request returned to draft');
    exception when others then response_error('BEGIN_CORRECTION', p_request_id, p_http_status, p_response);
    end;

    procedure return_request(p_request_id in varchar2, p_command_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_actor_json clob; l_reason varchar2(2000);
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
        l_version number;
    begin
        select json_query(p_command_json, '$.actor' returning clob), json_value(p_command_json, '$.reason' returning varchar2(2000))
          into l_actor_json, l_reason from dual;
        actor_values(l_actor_json, l_actor_id, l_actor_name, l_actor_role);
        if l_actor_role <> 'MANAGER' or trim(l_reason) is null then fail('REQUIRED', 'A manager and return reason are required.'); end if;
        l_request := request_object(p_request_id);
        if l_request.get_string('status') <> 'SUBMITTED' then fail('CONFLICT', 'Only submitted requests can be returned.'); end if;
        l_version := l_request.get_number('sourceVersion');
        l_request.put('status', 'RETURNED'); l_request.put('updatedAt', iso_now);
        add_history(p_request_id, l_request, 'RETURNED', l_actor_id, l_actor_name, l_actor_role, l_version, trim(l_reason));
        persist_existing(p_request_id, l_request);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'RETURN_REQUEST', p_request_id, 'Request returned by manager');
    exception when others then response_error('RETURN_REQUEST', p_request_id, p_http_status, p_response);
    end;

    procedure approve_request(p_request_id in varchar2, p_command_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_actor_json clob; l_payload clob; l_integration_response clob;
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
        l_version number; l_api_status number; l_action_request_id varchar2(80);
    begin
        select json_query(p_command_json, '$.actor' returning clob),
               json_query(p_command_json, '$.payload' returning clob)
          into l_actor_json, l_payload from dual;
        actor_values(l_actor_json, l_actor_id, l_actor_name, l_actor_role);
        if l_actor_role <> 'MANAGER' or l_payload is null then fail('REQUIRED', 'A manager and integration payload are required.'); end if;
        l_request := request_object(p_request_id);
        if l_request.get_string('status') <> 'SUBMITTED' then fail('CONFLICT', 'Only submitted requests can be approved.'); end if;
        if l_request.get_object('createdBy').get_string('id') = l_actor_id or l_request.get_object('submittedBy').get_string('id') = l_actor_id then fail('FORBIDDEN', 'The submitter cannot approve their own request.'); end if;
        l_action_request_id := json_value(l_payload, '$.ACTION_REQUEST_ID' returning varchar2(80));
        if l_action_request_id is null then fail('REQUIRED', 'ACTION_REQUEST_ID is required.'); end if;
        l_version := l_request.get_number('sourceVersion');
        l_request.put('actionRequestId', l_action_request_id);
        l_request.put('status', 'POSTING');
        l_request.put('approvedBy', actor_object(l_actor_json));
        l_request.put('approvedAt', iso_now);
        l_request.put('updatedAt', iso_now);
        l_request.put('integrationPayload', json_object_t.parse(l_payload));
        add_history(p_request_id, l_request, 'APPROVED', l_actor_id, l_actor_name, l_actor_role, l_version);
        persist_existing(p_request_id, l_request, l_payload);
        commit;

        office_mfcs_app.office_mfcs_api_pkg.submit_transaction(l_payload, l_api_status, l_integration_response);
        apply_integration_response(l_request, l_integration_response);
        persist_existing(p_request_id, l_request, l_payload, l_integration_response);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'APPROVE_REQUEST', p_request_id, 'Approval and MFCS posting completed');
    exception when others then response_error('APPROVE_REQUEST', p_request_id, p_http_status, p_response);
    end;

    procedure retry_request(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_payload clob; l_integration_response clob;
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
        l_api_status number; l_retryable varchar2(10); l_version number;
    begin
        actor_values(p_actor_json, l_actor_id, l_actor_name, l_actor_role);
        if l_actor_role <> 'MANAGER' then fail('FORBIDDEN', 'Only a manager can retry integration.'); end if;
        select request_json, integration_payload,
               json_value(integration_response, '$.RETRYABLE' returning varchar2(10) null on error)
          into l_integration_response, l_payload, l_retryable
          from office_workflow_request where request_id = p_request_id for update;
        if l_payload is null or lower(l_retryable) <> 'true' then fail('CONFLICT', 'This request is not retryable.'); end if;
        l_request := json_object_t.parse(l_integration_response);
        l_version := l_request.get_number('sourceVersion');
        l_request.put('status', 'POSTING'); l_request.put('updatedAt', iso_now);
        add_history(p_request_id, l_request, 'RETRIED', l_actor_id, l_actor_name, l_actor_role, l_version);
        persist_existing(p_request_id, l_request);
        commit;
        office_mfcs_app.office_mfcs_api_pkg.submit_transaction(l_payload, l_api_status, l_integration_response);
        apply_integration_response(l_request, l_integration_response);
        persist_existing(p_request_id, l_request, l_payload, l_integration_response);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'RETRY_REQUEST', p_request_id, 'Integration retry completed');
    exception when no_data_found then
            p_http_status := 404;
            p_response := error_json('NOT_FOUND', 'Workflow request was not found.');
            office_workflow_log_pkg.info(c_package_name, 'RETRY_REQUEST', p_request_id, 'Request was not found');
        when others then response_error('RETRY_REQUEST', p_request_id, p_http_status, p_response);
    end;

    procedure resolve_status(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob) is
        l_request json_object_t;
        l_action_request_id varchar2(80); l_integration_response clob;
        l_actor_id varchar2(200); l_actor_name varchar2(200); l_actor_role varchar2(20);
        l_api_status number; l_version number;
    begin
        actor_values(p_actor_json, l_actor_id, l_actor_name, l_actor_role);
        if l_actor_role <> 'MANAGER' then fail('FORBIDDEN', 'Only a manager can resolve integration status.'); end if;
        select action_request_id, request_json into l_action_request_id, l_integration_response
          from office_workflow_request where request_id = p_request_id for update;
        if l_action_request_id is null then fail('CONFLICT', 'No action request ID is available.'); end if;
        l_request := json_object_t.parse(l_integration_response);
        office_mfcs_app.office_mfcs_api_pkg.get_transaction(l_action_request_id, l_api_status, l_integration_response);
        apply_integration_response(l_request, l_integration_response);
        l_version := l_request.get_number('sourceVersion');
        add_history(p_request_id, l_request, 'STATUS_RESOLVED', l_actor_id, l_actor_name, l_actor_role, l_version);
        persist_existing(p_request_id, l_request, null, l_integration_response);
        commit;
        p_response := l_request.to_clob; p_http_status := 200;
        office_workflow_log_pkg.info(c_package_name, 'RESOLVE_STATUS', p_request_id, 'Integration status resolved');
    exception when no_data_found then
            p_http_status := 404;
            p_response := error_json('NOT_FOUND', 'Workflow request was not found.');
            office_workflow_log_pkg.info(c_package_name, 'RESOLVE_STATUS', p_request_id, 'Request was not found');
        when others then response_error('RESOLVE_STATUS', p_request_id, p_http_status, p_response);
    end;
end office_workflow_pkg;
/

show errors

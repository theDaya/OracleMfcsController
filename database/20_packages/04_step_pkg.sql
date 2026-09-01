set define off

-- Step graph and attempt journalling for a registered request.
--
-- initialize_steps writes the full plan for an operation into STEP before
-- anything runs; the orchestrator then walks it by asking first_runnable_step.
-- Every outbound HTTP call is bracketed by begin_attempt / complete_attempt,
-- which is what makes a request resumable: the journal knows what was sent,
-- what came back, and which step to pick up from.

prompt Creating step_pkg

create or replace package step_pkg authid definer as
    -- Writes the operation's full step plan into STEP, all PENDING. See the
    -- body for why every operation gets its whole write set.
    procedure initialize_steps(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2
    );

    -- The lowest-sequence step still PENDING, FAILED or OUTCOME_UNKNOWN, or
    -- null when the request is complete. FAILED is runnable on purpose: that
    -- is what resume means.
    function first_runnable_step(
        p_action_request_id in varchar2
    ) return varchar2;

    -- Whether a step has already succeeded, used by resume to skip work that
    -- is done.
    function step_succeeded(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return boolean;

    -- Records a step's current status and, on failure, the error that stopped it.
    procedure set_step_status(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_status            in varchar2,
        p_entity_identifier in varchar2 default null,
        p_error_code        in varchar2 default null,
        p_error_message     in varchar2 default null
    );

    -- Journals an outbound call before it is sent, returning the attempt id and
    -- a fresh correlation id. Recording first is deliberate: if the process
    -- dies mid-call, the journal still shows a call may have gone out.
    procedure begin_attempt(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        o_attempt_id        out number,
        o_correlation_id    out varchar2
    );

    -- Closes an attempt with what came back - or with OUTCOME_UNKNOWN when the
    -- transport failed after the request may have been sent.
    procedure complete_attempt(
        p_attempt_id       in number,
        p_attempt_status   in varchar2,
        p_http_status      in number default null,
        p_response_payload in clob default null
    );
end step_pkg;
/

show errors

create or replace package body step_pkg as
    procedure add_step(
        p_action_request_id in varchar2,
        p_step_code in varchar2,
        p_step_sequence in number
    ) is
    begin
        merge into step s
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
            -- Barcodes are level-3 items under the SKUs, so they can only be
            -- created once the SKUs exist. No-op when the document carries no
            -- SKU_UPCS, which is how a style without barcodes stays legal.
            add_step(p_action_request_id, 'CREATE_REFERENCE_ITEMS', 45);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 50);
            add_step(p_action_request_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE', 55);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 60);
            if config_pkg.get_config('FEATURE_ITEM_LOCATIONS_YN', 'N') = 'Y' then
                add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 70);
            end if;
            add_step(p_action_request_id, 'APPROVE_ITEMS', 80);
        elsif p_operation_name in ('MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER') then
            -- The whole style write set, every time, for every operation that touches
            -- an existing style. Not a diff.
            --
            -- This layer does not know what changed. It receives a document describing
            -- what the style should now be, and the only safe reading of that is that
            -- all of it may have changed. Sending a subset because nothing here looks
            -- different would mean the one field that did change is the one left
            -- behind, and MFCS answers a write that changes nothing with SUCCESS, so
            -- nothing would ever reveal the omission.
            --
            -- An order carries the same set. A purchase order is placed against a
            -- style's SKUs at a cost, in a country, from a supplier - ordering is a
            -- statement about the style, not only about the order, so the style is
            -- brought up to date first and the order is placed against what results.
            --
            -- ENSURE_STYLE_SKUS runs first because everything after it addresses SKUs
            -- by number. It is the one genuinely conditional step, and it conditions
            -- on the tenant rather than on this database: MFCS will not repurpose an
            -- existing SKU, since a diff combination defines the item, so a colour or
            -- size the style lacks has to become a new child before anything can
            -- reference it.
            add_step(p_action_request_id, 'ENSURE_STYLE_SKUS', 25);
            add_step(p_action_request_id, 'CREATE_ITEM_HIERARCHY', 30);
            add_step(p_action_request_id, 'CREATE_REFERENCE_ITEMS', 35);
            add_step(p_action_request_id, 'CREATE_ITEM_SOURCING', 40);
            add_step(p_action_request_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE', 45);
            add_step(p_action_request_id, 'CREATE_ITEM_UDAS', 50);
            if config_pkg.get_config('FEATURE_ITEM_LOCATIONS_YN', 'N') = 'Y' then
                add_step(p_action_request_id, 'CREATE_ITEM_LOCATIONS', 60);
            end if;
            add_step(p_action_request_id, 'APPROVE_ITEMS', 70);
        end if;

        if p_operation_name = 'CREATE_ALL'
           and config_pkg.get_config('FEATURE_INITIAL_RETAIL_YN', 'N') = 'Y' then
            add_step(p_action_request_id, 'APPLY_INITIAL_RETAIL', 80);
        end if;

        if p_operation_name in ('CREATE_ORDER', 'CREATE_ALL') then
            add_step(p_action_request_id, 'RESERVE_ORDER_NUMBER', 90);
            add_step(p_action_request_id, 'CREATE_PURCHASE_ORDER', 100);
            add_step(p_action_request_id, 'VERIFY_PURCHASE_ORDER', 110);
        elsif p_operation_name = 'MODIFY_ORDER' then
            add_step(p_action_request_id, 'CREATE_PURCHASE_ORDER', 100);
            -- The header update above ignores its details array on this tenant
            -- (SUCCESS, nothing changes - proven live). The lines are synced
            -- through the purchaseOrder/details services in their own step,
            -- which reads the order first because what it sends depends on what
            -- the order currently holds.
            add_step(p_action_request_id, 'SYNC_ORDER_LINES', 105);
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
                from step
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
          from step
         where action_request_id = p_action_request_id
           and step_code = p_step_code
           and step_status = 'SUCCEEDED';

        return l_count > 0;
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
        update step
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
          from attempt
         where action_request_id = p_action_request_id
           and step_code = p_step_code;

        l_guid := lower(rawtohex(sys_guid()));
        o_correlation_id := substr(l_guid, 1, 8) || '-'
                         || substr(l_guid, 9, 4) || '-'
                         || substr(l_guid, 13, 4) || '-'
                         || substr(l_guid, 17, 4) || '-'
                         || substr(l_guid, 21);

        o_attempt_id := attempt_seq.nextval;

        insert into attempt (
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

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'ATTEMPT_BEGIN',
            p_step_code => p_step_code,
            p_attempt_id => o_attempt_id,
            p_message => 'MFCS attempt opened.',
            p_detail_payload => '{"attemptNumber":' || l_attempt_number
                || ',"correlationId":"' || event_pkg.escape_json(o_correlation_id)
                || '","httpMethod":"' || event_pkg.escape_json(p_http_method)
                || '","endpoint":"' || event_pkg.escape_json(p_endpoint) || '"}'
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
        update attempt
           set attempt_status = p_attempt_status,
               http_status = p_http_status,
               response_payload = p_response_payload,
               completed_at = systimestamp
         where attempt_id = p_attempt_id
         returning action_request_id, step_code
              into l_action_request_id, l_step_code;

        event_pkg.log_event(
            p_action_request_id => l_action_request_id,
            p_event_phase => 'ATTEMPT_COMPLETE',
            p_step_code => l_step_code,
            p_attempt_id => p_attempt_id,
            p_event_level => case when p_attempt_status = 'SUCCEEDED' then 'INFO' else 'ERROR' end,
            p_message => 'MFCS attempt completed.',
            p_detail_payload => '{"attemptStatus":"' || event_pkg.escape_json(p_attempt_status)
                || '","httpStatus":' || coalesce(to_char(p_http_status), 'null')
                || ',"responseBytes":' || coalesce(to_char(dbms_lob.getlength(p_response_payload)), '0') || '}'
        );

        commit;
    end;
end step_pkg;
/

show errors

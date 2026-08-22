set define off
set serveroutput on size unlimited
set lines 220

-- Fault-injection coverage for the failure and resume paths, against the REAL
-- MFCS tenant.
--
-- Rather than simulating failures, each scenario makes MFCS itself reject a call
-- by pointing one MAP.* entry at foundation data that does not exist. The tenant
-- returns a genuine 4xx, which is what the orchestrator would meet in production.
--
-- WHAT THIS CREATES: scenarios that fail mid-chain leave real items in the tenant
-- in Worksheet status, and the resume scenario approves them. That is deliberate -
-- a resume cannot be proven without something real to resume. Run against a dev
-- tenant only.
--
-- Every scenario restores the config it changed, including on failure.

declare
    g_pass number := 0;
    g_fail number := 0;
    g_prefix varchar2(40) := 'RCT-' || to_char(systimestamp, 'YYYYMMDDHH24MISS');

    procedure ok(p_what in varchar2, p_cond in boolean, p_detail in varchar2 default null) is
    begin
        if p_cond then
            g_pass := g_pass + 1;
            dbms_output.put_line('    PASS  ' || p_what);
        else
            g_fail := g_fail + 1;
            dbms_output.put_line('    FAIL  ' || p_what || case when p_detail is not null then '  [' || p_detail || ']' end);
        end if;
    end;

    procedure set_cfg(p_key in varchar2, p_value in varchar2) is
    begin
        merge into config c
        using (select p_key k from dual) s
        on (c.config_key = s.k and c.environment = 'DEFAULT')
        when matched then update set c.config_value = p_value, c.updated_at = systimestamp
        when not matched then insert (environment, config_key, config_value, enabled_ind)
        values ('DEFAULT', p_key, p_value, 'Y');
        commit;
    end;

    function cfg(p_key in varchar2) return varchar2 is
        l_v varchar2(4000);
    begin
        select dbms_lob.substr(config_value, 4000, 1) into l_v
          from config where config_key = p_key and environment = 'DEFAULT';
        return l_v;
    exception
        when no_data_found then return null;
    end;

    function payload(
        p_id in varchar2,
        p_op in varchar2 default 'CREATE_STYLE',
        p_ref in varchar2 default null
    ) return clob is
        l_ref varchar2(200) := nvl(p_ref, p_id);
    begin
        return '{'
            || '"ACTION_REQUEST_ID":"' || p_id || '",'
            || '"OPERATION_NAME":"' || p_op || '",'
            || '"SOURCE_SYSTEM":"OFFICE_DEV",'
            || '"SOURCE_STYLE_REF":"' || l_ref || '",'
            || '"SOURCE_ORDER_REF":"' || l_ref || '-PO",'
            || '"SOURCE_VERSION":"1",'
            || '"USER_ID":"resume.coverage@example.com",'
            || '"DESCRIPTION":"Resume coverage ' || p_id || '",'
            || '"DEPARTMENT":"1517","CLASS":"6892","SUBCLASS":"1128",'
            || '"SUPPLIER":"700087","ORIGIN_COUNTRY":"GB","IMPORT_COUNTRY":"GB",'
            || '"CURRENCY_CODE":"ZAR","COLOUR":"08610",'
            || '"UNIT_COST":48.49,"RETAIL_PRICE":100,'
            || '"PLMSizeCurveDtl":[{"SOURCE_VARIANT_REF":"' || l_ref || '-7","SKU_SIZE":"7","SKU_WIDTH":"ALL","SKU_QTY":1,"SKU_ID":null}],'
            || '"NOT_BEFORE_DATE":"' || to_char(sysdate, 'YYYY-MM-DD') || '",'
            || '"NOT_AFTER_DATE":"' || to_char(sysdate, 'YYYY-MM-DD') || '",'
            -- OTB end-of-week must land on the retail week-ending day (Sunday on this
            -- tenant), or validation rejects the request before any MFCS call.
            || '"OTB_EOW_DATE":"' || to_char(next_day(sysdate, 'SUNDAY'), 'YYYY-MM-DD') || '",'
            || '"EARLIEST_SHIP_DATE":"' || to_char(sysdate, 'YYYY-MM-DD') || '",'
            || '"LATEST_SHIP_DATE":"' || to_char(sysdate + 19, 'YYYY-MM-DD') || '",'
            || '"DELIVERY_LOC":1927,"ORDER_EXCHANGE_RATE":1}';
    end;

    function req_status(p_id in varchar2) return varchar2 is
        l_s varchar2(40);
    begin
        select request_status into l_s from request where action_request_id = p_id;
        return l_s;
    exception
        when no_data_found then return '(absent)';
    end;

    function step_status(p_id in varchar2, p_step in varchar2) return varchar2 is
        l_s varchar2(40);
    begin
        select step_status into l_s from step
         where action_request_id = p_id and step_code = p_step;
        return l_s;
    exception
        when no_data_found then return '(absent)';
    end;

    function count_steps(p_id in varchar2, p_status in varchar2) return number is
        l_n number;
    begin
        select count(*) into l_n from step
         where action_request_id = p_id and step_status = p_status;
        return l_n;
    end;

    function attempts(p_id in varchar2, p_step in varchar2) return number is
        l_n number;
    begin
        select count(*) into l_n from attempt
         where action_request_id = p_id and step_code = p_step;
        return l_n;
    end;

    procedure show_steps(p_id in varchar2) is
    begin
        for s in (select step_sequence, step_code, step_status, last_error_code
                    from step where action_request_id = p_id order by step_sequence) loop
            dbms_output.put_line('           ' || lpad(s.step_sequence, 4) || '  '
                || rpad(s.step_code, 38) || rpad(s.step_status, 18)
                || nvl(s.last_error_code, ''));
        end loop;
    end;

    -- ------------------------------------------------------------------
    -- 1. Validation failure: nothing may reach MFCS.
    -- ------------------------------------------------------------------
    procedure scenario_validation_failure is
        l_id varchar2(100) := g_prefix || '-VAL';
        l_status number;
        l_response clob;
        l_attempts number;
    begin
        dbms_output.put_line(chr(10) || '1. Validation failure before any side effect');
        api_pkg.submit_transaction(
            '{"ACTION_REQUEST_ID":"' || l_id || '","OPERATION_NAME":"CREATE_STYLE","SOURCE_SYSTEM":"OFFICE_DEV"}',
            l_status, l_response);

        ok('HTTP 422', l_status = 422, 'got ' || l_status);
        ok('request FAILED_NO_SIDE_EFFECT', req_status(l_id) = 'FAILED_NO_SIDE_EFFECT', req_status(l_id));

        select count(*) into l_attempts from attempt where action_request_id = l_id;
        ok('no MFCS call attempted', l_attempts = 0, 'attempts=' || l_attempts);
    end;

    -- ------------------------------------------------------------------
    -- 2. MFCS rejects mid-chain; 3. resume completes it.
    -- ------------------------------------------------------------------
    procedure scenario_fail_then_resume is
        l_id varchar2(100) := g_prefix || '-RESUME';
        l_status number;
        l_response clob;
        l_saved varchar2(4000);
        l_style varchar2(30);
        l_attempts_before number;
    begin
        dbms_output.put_line(chr(10) || '2. MFCS rejects a mid-chain step (bad country of manufacture)');

        -- Country of manufacture runs at step 55, after the items exist. Pointing it
        -- at a country code the tenant does not know makes MFCS reject that call
        -- while everything before it genuinely succeeded.
        l_saved := cfg('MFCS_MANUFACTURER_COUNTRY');
        set_cfg('MFCS_MANUFACTURER_COUNTRY', 'ZZ');

        begin
            api_pkg.submit_transaction(payload(l_id), l_status, l_response);
        exception
            when others then null;
        end;

        show_steps(l_id);
        ok('request not COMPLETED', req_status(l_id) <> 'COMPLETED', req_status(l_id));
        ok('earlier step RESERVE_ITEM_NUMBERS succeeded',
           step_status(l_id, 'RESERVE_ITEM_NUMBERS') = 'SUCCEEDED', step_status(l_id, 'RESERVE_ITEM_NUMBERS'));
        ok('earlier step CREATE_PARENT_ITEM_HIERARCHY succeeded',
           step_status(l_id, 'CREATE_PARENT_ITEM_HIERARCHY') = 'SUCCEEDED', step_status(l_id, 'CREATE_PARENT_ITEM_HIERARCHY'));
        ok('failing step CREATE_ITEM_COUNTRIES_OF_MANUFACTURE not succeeded',
           step_status(l_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE') <> 'SUCCEEDED',
           step_status(l_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE'));
        ok('later step APPROVE_ITEMS never ran',
           step_status(l_id, 'APPROVE_ITEMS') = 'PENDING', step_status(l_id, 'APPROVE_ITEMS'));

        -- entity_map is keyed by source reference, not by request id: identifiers
        -- outlive any single request so a later resume or replay can reuse them.
        begin
            select max(mfcs_style_no) into l_style
              from entity_map where source_style_ref = l_id;
        exception when no_data_found then l_style := null;
        end;
        ok('generated style identifier persisted', l_style is not null, 'style=' || nvl(l_style, 'null'));

        -- ------------------------------------------------------------------
        dbms_output.put_line(chr(10) || '3. Resume after correcting the configuration');
        set_cfg('MFCS_MANUFACTURER_COUNTRY', l_saved);

        l_attempts_before := attempts(l_id, 'CREATE_PARENT_ITEM_HIERARCHY');

        api_pkg.resume_transaction(l_id, l_status, l_response);
        show_steps(l_id);

        ok('resume returns 2xx', l_status between 200 and 299, 'got ' || l_status);
        ok('request now COMPLETED', req_status(l_id) = 'COMPLETED', req_status(l_id));
        ok('previously failing step now succeeded',
           step_status(l_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE') = 'SUCCEEDED',
           step_status(l_id, 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE'));
        ok('APPROVE_ITEMS ran on resume',
           step_status(l_id, 'APPROVE_ITEMS') = 'SUCCEEDED', step_status(l_id, 'APPROVE_ITEMS'));
        ok('succeeded step was NOT re-called',
           attempts(l_id, 'CREATE_PARENT_ITEM_HIERARCHY') = l_attempts_before,
           'attempts before=' || l_attempts_before || ' after=' || attempts(l_id, 'CREATE_PARENT_ITEM_HIERARCHY'));
        ok('no step left PENDING', count_steps(l_id, 'PENDING') = 0,
           'pending=' || count_steps(l_id, 'PENDING'));
    exception
        when others then
            set_cfg('MFCS_MANUFACTURER_COUNTRY', l_saved);
            dbms_output.put_line('    ERROR ' || sqlerrm);
            g_fail := g_fail + 1;
    end;

    -- ------------------------------------------------------------------
    -- 4. Idempotency: same id, same payload.
    -- ------------------------------------------------------------------
    procedure scenario_idempotent_replay is
        l_id varchar2(100) := g_prefix || '-RESUME';
        l_status number;
        l_response clob;
        l_before number;
        l_after number;
    begin
        dbms_output.put_line(chr(10) || '4. Idempotent replay of a completed request');
        select count(*) into l_before from attempt where action_request_id = l_id;
        api_pkg.submit_transaction(payload(l_id), l_status, l_response);
        select count(*) into l_after from attempt where action_request_id = l_id;

        ok('replay returns 2xx', l_status between 200 and 299, 'got ' || l_status);
        ok('no new MFCS calls made', l_after = l_before, 'before=' || l_before || ' after=' || l_after);
        ok('still COMPLETED', req_status(l_id) = 'COMPLETED', req_status(l_id));
    end;

    -- ------------------------------------------------------------------
    -- 5. Same id, different business payload.
    -- ------------------------------------------------------------------
    procedure scenario_payload_conflict is
        l_id varchar2(100) := g_prefix || '-RESUME';
        l_status number;
        l_response clob;
    begin
        dbms_output.put_line(chr(10) || '5. Changed payload under an existing ACTION_REQUEST_ID');
        api_pkg.submit_transaction(payload(l_id, 'CREATE_STYLE', l_id || '-DIFFERENT'), l_status, l_response);
        ok('HTTP 409 conflict', l_status = 409, 'got ' || l_status);
        ok('conflict reported', l_response like '%IDEMPOTENCY_CONFLICT%',
           substr(l_response, 1, 120));
    end;

begin
    dbms_output.put_line('===========================================================');
    dbms_output.put_line(' Resume and failure coverage against the live MFCS tenant');
    dbms_output.put_line(' Run prefix: ' || g_prefix);
    dbms_output.put_line('===========================================================');

    scenario_validation_failure;
    scenario_fail_then_resume;
    scenario_idempotent_replay;
    scenario_payload_conflict;

    dbms_output.put_line(chr(10) || '===========================================================');
    dbms_output.put_line(' passed: ' || g_pass || '   failed: ' || g_fail);
    dbms_output.put_line('===========================================================');
    if g_fail > 0 then
        raise_application_error(-20999, g_fail || ' assertion(s) failed.');
    end if;
end;
/

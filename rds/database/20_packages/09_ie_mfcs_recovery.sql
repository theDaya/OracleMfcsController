-- Resolves the outcome of ambiguous calls by correlation ID.
--
-- When a transport error leaves a step OUTCOME_UNKNOWN, the truth is in the
-- tenant, not in this database. This asks MFCS's operation-status service what
-- happened to the correlation id the attempt journalled: SUCCESS marks the
-- step done, FAILURE marks it failed, and no record at all means the call
-- never landed and the step can simply run again.

create or replace package ie_mfcs_recovery authid definer as
    -- Resolves the most recent OUTCOME_UNKNOWN attempt of one step. Returns
    -- SUCCEEDED, FAILED, NO_RECORD (safe to re-run), MANUAL_REVIEW (still
    -- ambiguous - the request is parked), or NO_UNKNOWN_ATTEMPT.
    function resolve_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return varchar2;
end ie_mfcs_recovery;
/

create or replace package body ie_mfcs_recovery as
    function resolve_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return varchar2 is
        l_correlation_id varchar2(80);
        l_status_response clob;
        l_status varchar2(30);
        l_response_code number;
        l_result_count number;
    begin
        select correlation_id
          into l_correlation_id
          from (
              select correlation_id
                from ie_mfcs_prd_step_attempt
               where action_request_id = p_action_request_id
                 and step_code = p_step_code
                 and attempt_status = 'OUTCOME_UNKNOWN'
               order by attempt_number desc
          )
         where rownum = 1;

        l_status_response := ie_mfcs_client.correlation_status(p_action_request_id, l_correlation_id);

        select json_value(l_status_response, '$.status' returning varchar2(30) null on error),
               json_value(l_status_response, '$.items[0].responseCode' returning number null on error),
               json_value(l_status_response, '$.count' returning number null on error)
          into l_status, l_response_code, l_result_count
          from dual;

        if l_status is null then
            if nvl(l_result_count, 0) = 0 then
                l_status := 'NO_RECORD';
            elsif l_response_code between 200 and 299 then
                l_status := 'SUCCESS';
            elsif l_response_code >= 400 then
                l_status := 'FAILURE';
            else
                l_status := 'UNKNOWN';
            end if;
        end if;

        if l_status = 'SUCCESS' then
            ie_mfcs_step.set_step_status(p_action_request_id, p_step_code, 'SUCCEEDED');
            return 'SUCCEEDED';
        elsif l_status = 'FAILURE' then
            ie_mfcs_step.set_step_status(p_action_request_id, p_step_code, 'FAILED', null, 'MFCS_REPORTED_FAILURE', 'MFCS operation-status service reported failure.');
            return 'FAILED';
        elsif l_status = 'NO_RECORD' then
            ie_mfcs_step.set_step_status(p_action_request_id, p_step_code, 'PENDING');
            return 'NO_RECORD';
        else
            ie_mfcs_step.set_step_status(p_action_request_id, p_step_code, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', 'MFCS operation outcome is still ambiguous.');
            ie_mfcs_request.set_request_status(p_action_request_id, 'MANUAL_REVIEW', ie_mfcs_request.build_status_response(p_action_request_id, 'MANUAL_REVIEW'));
            return 'MANUAL_REVIEW';
        end if;
    exception
        when no_data_found then
            return 'NO_UNKNOWN_ATTEMPT';
    end;
end ie_mfcs_recovery;
/

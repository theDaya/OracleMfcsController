-- Autonomous event log, and the one JSON string-escape helper.
--
-- Every package that talks to MFCS logs its progress here. The autonomous
-- transaction is the point: an event survives the rollback of the step that
-- logged it, so a failed request still tells its story. A logging failure is
-- swallowed - the log must never be the reason a request fails.

create or replace package ie_mfcs_event authid definer as
    -- Escapes a value for embedding inside a JSON string literal. Public because
    -- several packages hand-build small JSON documents (detail payloads, status
    -- responses); this is the single copy they all share. Returns null for null.
    function escape_json(p_value in varchar2) return varchar2;

    -- Appends one row to IE_MFCS_LOG_EVENT in an autonomous transaction and commits it.
    -- p_detail_payload is expected to be a JSON document; build its string
    -- values with escape_json.
    procedure log_event(
        p_action_request_id in varchar2,
        p_event_phase       in varchar2,
        p_step_code         in varchar2 default null,
        p_attempt_id        in number default null,
        p_message           in varchar2 default null,
        p_detail_payload    in clob default null,
        p_event_level       in varchar2 default 'INFO'
    );
end ie_mfcs_event;
/

create or replace package body ie_mfcs_event as
    function escape_json(p_value in varchar2) return varchar2 is
    begin
        if p_value is null then
            return null;
        end if;

        return replace(
                   replace(
                       replace(
                           replace(p_value, '\', '\\'),
                           '"', '\"'
                       ),
                       chr(10), '\n'
                   ),
                   chr(13), '\r'
               );
    end;

    procedure log_event(
        p_action_request_id in varchar2,
        p_event_phase       in varchar2,
        p_step_code         in varchar2 default null,
        p_attempt_id        in number default null,
        p_message           in varchar2 default null,
        p_detail_payload    in clob default null,
        p_event_level       in varchar2 default 'INFO'
    ) is
        pragma autonomous_transaction;
    begin
        insert into ie_mfcs_log_event (
            log_id,
            action_request_id,
            step_code,
            attempt_id,
            event_level,
            event_phase,
            message,
            detail_payload
        ) values (
            ie_mfcs_seq_event_log_id.nextval,
            p_action_request_id,
            p_step_code,
            p_attempt_id,
            coalesce(p_event_level, 'INFO'),
            p_event_phase,
            substr(p_message, 1, 1000),
            p_detail_payload
        );

        commit;
    exception
        when others then
            rollback;
    end;
end ie_mfcs_event;
/

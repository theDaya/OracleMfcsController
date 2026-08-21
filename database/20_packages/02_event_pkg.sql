set define off

-- Autonomous event log. Records progress even when a step later fails.

prompt Creating event_pkg

create or replace package event_pkg authid definer as
    procedure log_event(
        p_action_request_id in varchar2,
        p_event_phase       in varchar2,
        p_step_code         in varchar2 default null,
        p_attempt_id        in number default null,
        p_message           in varchar2 default null,
        p_detail_payload    in clob default null,
        p_event_level       in varchar2 default 'INFO'
    );
end event_pkg;
/

show errors

create or replace package body event_pkg as
    function json_escape(p_value in varchar2) return varchar2 is
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
        insert into event_log (
            log_id,
            action_request_id,
            step_code,
            attempt_id,
            event_level,
            event_phase,
            message,
            detail_payload
        ) values (
            event_log_seq.nextval,
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
end event_pkg;
/

show errors

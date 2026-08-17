set define off

prompt Creating Local MFCS event logging package

-- Persists the REST event journal independently from RMS business transactions.
create or replace package local_mfcs_log_pkg authid definer as
    procedure record_event(
        p_correlation_id   in varchar2,
        p_service_name     in varchar2,
        p_http_method      in varchar2,
        p_response_code    in number,
        p_request_payload  in clob,
        p_response_payload in clob,
        p_started_at       in timestamp with time zone
    );
end local_mfcs_log_pkg;
/

create or replace package body local_mfcs_log_pkg as
    procedure record_event(
        p_correlation_id   in varchar2,
        p_service_name     in varchar2,
        p_http_method      in varchar2,
        p_response_code    in number,
        p_request_payload  in clob,
        p_response_payload in clob,
        p_started_at       in timestamp with time zone
    ) is
        pragma autonomous_transaction;
    begin
        insert into local_mfcs_rest_event(
            event_id, correlation_id, service_name, http_method, response_code,
            request_payload, response_payload, started_at, completed_at
        ) values (
            local_mfcs_event_seq.nextval, substr(p_correlation_id, 1, 100),
            substr(upper(p_service_name), 1, 100), substr(upper(p_http_method), 1, 10),
            p_response_code, p_request_payload, p_response_payload,
            p_started_at, systimestamp
        );
        commit;
    exception
        when others then
            -- Event logging is diagnostic and must not alter simulator behavior.
            rollback;
    end record_event;
end local_mfcs_log_pkg;
/

show errors package local_mfcs_log_pkg
show errors package body local_mfcs_log_pkg

prompt Local MFCS event logging package created

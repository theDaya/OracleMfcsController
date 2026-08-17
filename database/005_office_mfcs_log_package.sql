set define off

prompt Creating OFFICE MFCS logging package

-- Central structured logging. Logging is best-effort and never changes the
-- outcome of the business operation that emitted the event.
create or replace package office_mfcs_log_pkg authid definer as
    procedure write_log(
        p_log_level         in varchar2,
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    );

    procedure info(
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    );

    procedure error(
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    );
end office_mfcs_log_pkg;
/

create or replace package body office_mfcs_log_pkg as
    procedure write_log(
        p_log_level         in varchar2,
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    ) is
        pragma autonomous_transaction;
        l_log_level varchar2(10) := upper(coalesce(trim(p_log_level), 'INFO'));
    begin
        if l_log_level not in ('DEBUG', 'INFO', 'WARN', 'ERROR') then
            l_log_level := 'INFO';
        end if;

        insert into office_mfcs_log(
            log_id, log_level, package_name, operation_name,
            action_request_id, message, details
        ) values (
            office_mfcs_log_seq.nextval, l_log_level,
            substr(p_package_name, 1, 128), substr(p_operation_name, 1, 128),
            substr(p_action_request_id, 1, 80), substr(p_message, 1, 4000), p_details
        );
        commit;
    exception
        when others then
            -- Diagnostics must never break the transaction being diagnosed.
            rollback;
    end write_log;

    procedure info(
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    ) is
    begin
        write_log('INFO', p_package_name, p_operation_name, p_action_request_id, p_message, p_details);
    end info;

    procedure error(
        p_package_name      in varchar2,
        p_operation_name    in varchar2,
        p_action_request_id in varchar2 default null,
        p_message           in varchar2 default null,
        p_details           in clob default null
    ) is
    begin
        write_log('ERROR', p_package_name, p_operation_name, p_action_request_id, p_message, p_details);
    end error;
end office_mfcs_log_pkg;
/

show errors package office_mfcs_log_pkg
show errors package body office_mfcs_log_pkg

prompt OFFICE MFCS logging package created

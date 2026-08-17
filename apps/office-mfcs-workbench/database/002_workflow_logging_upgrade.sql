set define off

prompt Ensuring Office workflow logging objects exist

declare
    l_count number;
begin
    select count(*) into l_count
      from user_tables
     where table_name = 'OFFICE_WORKFLOW_LOG';

    if l_count = 0 then
        execute immediate q'[
            create table office_workflow_log (
                log_id          number not null,
                log_level       varchar2(10) not null,
                package_name    varchar2(128) not null,
                operation_name  varchar2(128) not null,
                request_id      varchar2(36),
                message         varchar2(4000),
                details         clob,
                created_at      timestamp with time zone default systimestamp not null,
                constraint office_workflow_log_pk primary key (log_id),
                constraint office_workflow_log_level_ck check (log_level in ('DEBUG', 'INFO', 'WARN', 'ERROR'))
            )
        ]';
    end if;

    select count(*) into l_count
      from user_sequences
     where sequence_name = 'OFFICE_WORKFLOW_LOG_SEQ';

    if l_count = 0 then
        execute immediate 'create sequence office_workflow_log_seq start with 1 increment by 1 nocache';
    end if;

    select count(*) into l_count
      from user_indexes
     where index_name = 'OFFICE_WORKFLOW_LOG_REQUEST_IX';

    if l_count = 0 then
        execute immediate 'create index office_workflow_log_request_ix on office_workflow_log (request_id, created_at)';
    end if;
end;
/

comment on table office_workflow_log is 'Structured operational events emitted by the Office workflow packages.';
comment on column office_workflow_log.details is 'Optional diagnostic context. Sensitive payloads must not be stored here.';

prompt Office workflow logging objects ready

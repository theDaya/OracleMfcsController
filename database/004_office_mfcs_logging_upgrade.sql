set define off

prompt Ensuring OFFICE MFCS logging objects exist

declare
    l_count number;
begin
    select count(*) into l_count
      from user_tables
     where table_name = 'OFFICE_MFCS_LOG';

    if l_count = 0 then
        execute immediate q'[
            create table office_mfcs_log (
                log_id             number not null,
                log_level          varchar2(10) not null,
                package_name       varchar2(128) not null,
                operation_name     varchar2(128) not null,
                action_request_id  varchar2(80),
                message            varchar2(4000),
                details            clob,
                created_at         timestamp with time zone default systimestamp not null,
                constraint office_mfcs_log_pk primary key (log_id),
                constraint office_mfcs_log_level_ck check (log_level in ('DEBUG', 'INFO', 'WARN', 'ERROR'))
            )
        ]';
    end if;

    select count(*) into l_count
      from user_sequences
     where sequence_name = 'OFFICE_MFCS_LOG_SEQ';

    if l_count = 0 then
        execute immediate 'create sequence office_mfcs_log_seq start with 1 increment by 1 nocache';
    end if;

    select count(*) into l_count
      from user_indexes
     where index_name = 'OFFICE_MFCS_LOG_REQUEST_IX';

    if l_count = 0 then
        execute immediate 'create index office_mfcs_log_request_ix on office_mfcs_log (action_request_id, created_at)';
    end if;
end;
/

comment on table office_mfcs_log is 'Structured operational events emitted by the Office MFCS integration packages.';
comment on column office_mfcs_log.details is 'Optional diagnostic context. Secrets and access tokens must never be logged.';

prompt OFFICE MFCS logging objects ready

set define off

prompt Creating OFFICE MFCS integration tables

create table office_mfcs_request (
    action_request_id varchar2(80) not null,
    operation_name    varchar2(30) not null,
    source_system     varchar2(60),
    source_style_ref  varchar2(120),
    source_order_ref  varchar2(120),
    source_version    varchar2(60),
    payload_hash      varchar2(64) not null,
    request_status    varchar2(30) not null,
    style_no          varchar2(30),
    order_no          varchar2(30),
    request_payload   clob not null,
    response_payload  clob,
    created_at        timestamp with time zone default systimestamp not null,
    started_at        timestamp with time zone,
    completed_at      timestamp with time zone,
    last_updated_at   timestamp with time zone default systimestamp not null
);

create table office_mfcs_step (
    action_request_id   varchar2(80) not null,
    step_code           varchar2(60) not null,
    step_sequence       number(5) not null,
    step_status         varchar2(30) not null,
    entity_identifier   varchar2(120),
    started_at          timestamp with time zone,
    completed_at        timestamp with time zone,
    last_error_code     varchar2(80),
    last_error_message  varchar2(4000)
);

create table office_mfcs_attempt (
    attempt_id       number not null,
    action_request_id varchar2(80) not null,
    step_code        varchar2(60) not null,
    attempt_number   number(5) not null,
    correlation_id   varchar2(80) not null,
    http_method      varchar2(10) not null,
    endpoint         varchar2(1000) not null,
    http_status      number(5),
    request_payload  clob,
    response_payload clob,
    attempt_status   varchar2(30) not null,
    started_at       timestamp with time zone default systimestamp not null,
    completed_at     timestamp with time zone
);

create table office_mfcs_entity_map (
    source_system      varchar2(60) not null,
    source_style_ref   varchar2(120),
    mfcs_style_no      varchar2(30),
    source_variant_ref varchar2(120),
    mfcs_sku_no        varchar2(30),
    sku_size           varchar2(40),
    sku_width          varchar2(40),
    source_order_ref   varchar2(120),
    mfcs_order_no      varchar2(30),
    created_at         timestamp with time zone default systimestamp not null,
    last_updated_at    timestamp with time zone default systimestamp not null
);

create table office_mfcs_config (
    config_key    varchar2(200) not null,
    config_value  clob,
    environment   varchar2(40) default 'DEFAULT' not null,
    enabled_ind   char(1) default 'Y' not null,
    created_at    timestamp with time zone default systimestamp not null,
    updated_at    timestamp with time zone default systimestamp not null
);

-- Operational log entries are deliberately independent of request state so that
-- failures can be recorded even when the business transaction is rolled back.
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
);

create sequence office_mfcs_attempt_seq start with 1 increment by 1 nocache;
create sequence office_mfcs_log_seq start with 1 increment by 1 nocache;

create index office_mfcs_log_request_ix
    on office_mfcs_log (action_request_id, created_at);

comment on table office_mfcs_log is 'Structured operational events emitted by the Office MFCS integration packages.';
comment on column office_mfcs_log.details is 'Optional diagnostic context. Secrets and access tokens must never be logged.';

prompt OFFICE MFCS tables created

-- The controller's tables, named to the Oracle Database Naming Standard.
--
-- Same columns, same constraints, same meaning as the original layer - only the
-- names changed. The mapping is in docs/database-objects.md. Column names were
-- deliberately left alone: they leak into every JSON response and query, and
-- they already comply (ENABLED_IND is the only indicator).
--
-- Plain DDL, run once into an empty schema. The original created EVENT_LOG and
-- MASTER_DATA defensively because they were added to databases that already
-- existed, and a fresh install has no such history.
--
-- SECRET is not here. It held the STATIC_BEARER token, and that path was not
-- carried into RDS - see the header of ie_mfcs_client.

-- One inbound document and its outcome.
create table ie_mfcs_prd_request (
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

alter table ie_mfcs_prd_request add constraint ie_mfcs_prd_request_pk
    primary key (action_request_id);

alter table ie_mfcs_prd_request add constraint ie_mfcs_prd_request_ck
    check (request_status in (
        'RECEIVED',
        'VALIDATED',
        'IN_PROGRESS',
        'COMPLETED',
        'FAILED_NO_SIDE_EFFECT',
        'PARTIALLY_COMPLETED',
        'OUTCOME_UNKNOWN',
        'MANUAL_REVIEW'
    ));

alter table ie_mfcs_prd_request add constraint ie_mfcs_prd_request_ck1
    check (operation_name in (
        'CREATE_STYLE',
        'MODIFY_STYLE',
        'CREATE_ORDER',
        'MODIFY_ORDER',
        'CREATE_ALL'
    ));

alter table ie_mfcs_prd_request add constraint ie_mfcs_prd_request_ck2
    check (request_payload is json);

create index ie_mfcs_prd_request_ix
    on ie_mfcs_prd_request (request_status, last_updated_at);

-- The step graph for one request: one row per step, all written up front.
create table ie_mfcs_prd_request_step (
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

alter table ie_mfcs_prd_request_step add constraint ie_mfcs_prd_request_step_pk
    primary key (action_request_id, step_code);

alter table ie_mfcs_prd_request_step add constraint ie_mfcs_prd_request_step_fk
    foreign key (action_request_id)
    references ie_mfcs_prd_request (action_request_id);

alter table ie_mfcs_prd_request_step add constraint ie_mfcs_prd_request_step_ck
    check (step_status in (
        'PENDING',
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'SKIPPED'
    ));

create index ie_mfcs_prd_request_step_ix
    on ie_mfcs_prd_request_step (step_status, step_sequence);

-- Every outbound call, journalled before it is sent.
create table ie_mfcs_prd_step_attempt (
    attempt_id        number not null,
    action_request_id varchar2(80) not null,
    step_code         varchar2(60) not null,
    attempt_number    number(5) not null,
    correlation_id    varchar2(80) not null,
    http_method       varchar2(10) not null,
    endpoint          varchar2(1000) not null,
    http_status       number(5),
    request_payload   clob,
    response_payload  clob,
    attempt_status    varchar2(30) not null,
    started_at        timestamp with time zone default systimestamp not null,
    completed_at      timestamp with time zone
);

alter table ie_mfcs_prd_step_attempt add constraint ie_mfcs_prd_step_attempt_pk
    primary key (attempt_id);

alter table ie_mfcs_prd_step_attempt add constraint ie_mfcs_prd_step_attempt_fk
    foreign key (action_request_id, step_code)
    references ie_mfcs_prd_request_step (action_request_id, step_code);

alter table ie_mfcs_prd_step_attempt add constraint ie_mfcs_prd_step_attempt_ck
    check (attempt_status in (
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'NO_RECORD'
    ));

alter table ie_mfcs_prd_step_attempt add constraint ie_mfcs_prd_step_attempt_ck1
    check (request_payload is json);

alter table ie_mfcs_prd_step_attempt add constraint ie_mfcs_prd_step_attempt_uk
    unique (correlation_id);

create unique index ie_mfcs_prd_step_attempt_ux
    on ie_mfcs_prd_step_attempt (action_request_id, step_code, attempt_number);

create sequence ie_mfcs_seq_attempt_id start with 1 increment by 1 nocache;

-- What this layer created, keyed by the caller's references.
create table ie_mfcs_map_entity (
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

create unique index ie_mfcs_map_entity_ux
    on ie_mfcs_map_entity (
        source_system,
        source_style_ref,
        nvl(source_variant_ref, '-'),
        nvl(source_order_ref, '-')
    );

-- Endpoint paths, tenant constants and defaults. Never a credential.
create table ie_mfcs_cfg_setting (
    config_key    varchar2(200) not null,
    config_value  clob,
    environment   varchar2(40) default 'DEFAULT' not null,
    enabled_ind   char(1) default 'Y' not null,
    created_at    timestamp with time zone default systimestamp not null,
    updated_at    timestamp with time zone default systimestamp not null
);

alter table ie_mfcs_cfg_setting add constraint ie_mfcs_cfg_setting_pk
    primary key (environment, config_key);

alter table ie_mfcs_cfg_setting add constraint ie_mfcs_cfg_setting_ck
    check (enabled_ind in ('Y', 'N'));

alter table ie_mfcs_cfg_setting add constraint ie_mfcs_cfg_setting_ck1
    check (
        config_value is null
        or config_key not like 'JSON:%'
        or config_value is json
    );

-- Every phase of every request, written in autonomous transactions.
create table ie_mfcs_log_event (
    log_id            number not null,
    action_request_id varchar2(80),
    step_code         varchar2(60),
    attempt_id        number,
    event_level       varchar2(10) default 'INFO' not null,
    event_phase       varchar2(80) not null,
    message           varchar2(1000),
    detail_payload    clob,
    created_at        timestamp with time zone default systimestamp not null
);

alter table ie_mfcs_log_event add constraint ie_mfcs_log_event_pk
    primary key (log_id);

alter table ie_mfcs_log_event add constraint ie_mfcs_log_event_ck
    check (event_level in ('DEBUG', 'INFO', 'WARN', 'ERROR'));

alter table ie_mfcs_log_event add constraint ie_mfcs_log_event_ck1
    check (detail_payload is null or detail_payload is json);

create index ie_mfcs_log_event_ix
    on ie_mfcs_log_event (action_request_id, created_at);

create index ie_mfcs_log_event_ix1
    on ie_mfcs_log_event (event_phase, created_at);

create sequence ie_mfcs_seq_event_log_id start with 1 increment by 1 nocache;

-- The tenant's foundation data, as validation and the payload builders read it.
-- SOURCE says where each row came from: RDS, a foundation service, or derived
-- from the item and order feeds.
create table ie_mfcs_ref_master_data (
    data_type    varchar2(40)  not null,
    data_code    varchar2(120) not null,
    parent_code  varchar2(120) default '~' not null,
    description  varchar2(400),
    attributes   clob,
    source       varchar2(200),
    refreshed_at timestamp with time zone default systimestamp not null
);

alter table ie_mfcs_ref_master_data add constraint ie_mfcs_ref_master_data_pk
    primary key (data_type, data_code, parent_code);

create index ie_mfcs_ref_master_data_ix
    on ie_mfcs_ref_master_data (data_type, parent_code);

-- One row per master-data source: when it last refreshed, and how it went.
create table ie_mfcs_log_master_refresh (
    data_type    varchar2(40) not null,
    source       varchar2(200),
    http_status  number,
    row_count    number,
    message      varchar2(1000),
    started_at   timestamp with time zone,
    completed_at timestamp with time zone
);

alter table ie_mfcs_log_master_refresh add constraint ie_mfcs_log_master_refresh_pk
    primary key (data_type);

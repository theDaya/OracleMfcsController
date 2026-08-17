set define off
whenever sqlerror exit failure rollback

create table office_workflow_request (
    request_id            varchar2(36) not null,
    office_reference      varchar2(40) not null,
    operation_name        varchar2(30) not null,
    workflow_status       varchar2(30) not null,
    source_style_ref      varchar2(120) not null,
    source_order_ref      varchar2(120) not null,
    source_version        number(10) not null,
    action_request_id     varchar2(80),
    style_description     varchar2(250),
    supplier              number(10),
    total_quantity        number(20,4) default 0 not null,
    total_cost            number(20,4) default 0 not null,
    created_by_id         varchar2(200) not null,
    created_by_name       varchar2(200) not null,
    submitted_by_id       varchar2(200),
    approved_by_id        varchar2(200),
    created_at            timestamp with time zone not null,
    updated_at            timestamp with time zone not null,
    submitted_at          timestamp with time zone,
    approved_at           timestamp with time zone,
    request_json          clob not null,
    integration_payload   clob,
    integration_response  clob,
    constraint office_workflow_request_pk primary key (request_id),
    constraint office_workflow_request_ref_uq unique (office_reference),
    constraint office_workflow_request_action_uq unique (action_request_id),
    constraint office_workflow_request_operation_ck check (operation_name in ('CREATE_ALL', 'CREATE_STYLE', 'CREATE_ORDER', 'MODIFY_STYLE', 'MODIFY_ORDER')),
    constraint office_workflow_request_status_ck check (workflow_status in ('DRAFT', 'SUBMITTED', 'RETURNED', 'APPROVED', 'POSTING', 'POSTED', 'PARTIALLY_COMPLETED', 'FAILED', 'MANUAL_REVIEW')),
    constraint office_workflow_request_json_ck check (request_json is json),
    constraint office_workflow_payload_json_ck check (integration_payload is json),
    constraint office_workflow_response_json_ck check (integration_response is json)
);

create table office_workflow_history (
    history_id       number not null,
    request_id       varchar2(36) not null,
    action_name      varchar2(30) not null,
    actor_id         varchar2(200) not null,
    actor_name       varchar2(200) not null,
    actor_role       varchar2(20) not null,
    source_version   number(10) not null,
    action_comment   varchar2(2000),
    occurred_at      timestamp with time zone default systimestamp not null,
    constraint office_workflow_history_pk primary key (history_id),
    constraint office_workflow_history_request_fk foreign key (request_id) references office_workflow_request (request_id),
    constraint office_workflow_history_action_ck check (action_name in ('SUBMITTED', 'RETURNED', 'APPROVED', 'RETRIED', 'STATUS_RESOLVED')),
    constraint office_workflow_history_role_ck check (actor_role in ('BUYER', 'MANAGER'))
);

-- This table is an operational journal, not workflow state. The logging package
-- writes to it autonomously so a failed request still leaves useful diagnostics.
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
);

create sequence office_workflow_history_seq start with 1 increment by 1 nocache;
create sequence office_workflow_log_seq start with 1 increment by 1 nocache;

create index office_workflow_request_queue_ix on office_workflow_request (workflow_status, updated_at);
create index office_workflow_request_buyer_ix on office_workflow_request (created_by_id, updated_at);
create index office_workflow_history_request_ix on office_workflow_history (request_id, occurred_at);
create index office_workflow_log_request_ix on office_workflow_log (request_id, created_at);

comment on table office_workflow_log is 'Structured operational events emitted by the Office workflow packages.';
comment on column office_workflow_log.details is 'Optional diagnostic context. Sensitive payloads must not be stored here.';

prompt Office workflow tables created

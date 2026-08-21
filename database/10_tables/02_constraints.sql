set define off

prompt Creating OFFICE MFCS constraints and indexes

alter table request add constraint request_pk
    primary key (action_request_id);

alter table request add constraint request_status_ck
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

alter table request add constraint request_oper_ck
    check (operation_name in (
        'CREATE_STYLE',
        'MODIFY_STYLE',
        'CREATE_ORDER',
        'MODIFY_ORDER',
        'CREATE_ALL'
    ));

alter table request add constraint request_payload_json_ck
    check (request_payload is json);

alter table step add constraint step_pk
    primary key (action_request_id, step_code);

alter table step add constraint step_request_fk
    foreign key (action_request_id)
    references request (action_request_id);

alter table step add constraint step_status_ck
    check (step_status in (
        'PENDING',
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'SKIPPED'
    ));

alter table attempt add constraint attempt_pk
    primary key (attempt_id);

alter table attempt add constraint attempt_step_fk
    foreign key (action_request_id, step_code)
    references step (action_request_id, step_code);

alter table attempt add constraint attempt_status_ck
    check (attempt_status in (
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'NO_RECORD'
    ));

alter table attempt add constraint attempt_json_req_ck
    check (request_payload is json);

alter table attempt add constraint attempt_corr_uk
    unique (correlation_id);

create unique index attempt_uk1
    on attempt (action_request_id, step_code, attempt_number);

alter table event_log add constraint event_log_pk
    primary key (log_id);

alter table event_log add constraint event_level_ck
    check (event_level in ('DEBUG', 'INFO', 'WARN', 'ERROR'));

alter table event_log add constraint event_detail_json_ck
    check (detail_payload is null or detail_payload is json);

create index event_log_ix1
    on event_log (action_request_id, created_at);

create index event_log_ix2
    on event_log (event_phase, created_at);

create unique index entity_style_uk
    on entity_map (
        source_system,
        source_style_ref,
        nvl(source_variant_ref, '-'),
        nvl(source_order_ref, '-')
    );

alter table config add constraint config_pk
    primary key (environment, config_key);

alter table config add constraint config_enabled_ck
    check (enabled_ind in ('Y', 'N'));

alter table config add constraint config_json_ck
    check (
        config_value is null
        or config_key not like 'JSON:%'
        or config_value is json
    );

alter table secret add constraint secret_pk
    primary key (secret_ref);

create index request_status_ix
    on request (request_status, last_updated_at);

create index step_status_ix
    on step (step_status, step_sequence);

prompt OFFICE MFCS constraints and indexes created

set define off

prompt Creating OFFICE MFCS constraints and indexes

alter table office_mfcs_request add constraint office_mfcs_request_pk
    primary key (action_request_id);

alter table office_mfcs_request add constraint office_mfcs_request_status_ck
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

alter table office_mfcs_request add constraint office_mfcs_request_oper_ck
    check (operation_name in (
        'CREATE_STYLE',
        'MODIFY_STYLE',
        'CREATE_ORDER',
        'MODIFY_ORDER',
        'CREATE_ALL'
    ));

alter table office_mfcs_request add constraint office_mfcs_request_payload_json_ck
    check (request_payload is json);

alter table office_mfcs_request add constraint office_mfcs_response_payload_json_ck
    check (response_payload is json);

alter table office_mfcs_step add constraint office_mfcs_step_pk
    primary key (action_request_id, step_code);

alter table office_mfcs_step add constraint office_mfcs_step_request_fk
    foreign key (action_request_id)
    references office_mfcs_request (action_request_id);

alter table office_mfcs_step add constraint office_mfcs_step_status_ck
    check (step_status in (
        'PENDING',
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'SKIPPED'
    ));

alter table office_mfcs_attempt add constraint office_mfcs_attempt_pk
    primary key (attempt_id);

alter table office_mfcs_attempt add constraint office_mfcs_attempt_step_fk
    foreign key (action_request_id, step_code)
    references office_mfcs_step (action_request_id, step_code);

alter table office_mfcs_attempt add constraint office_mfcs_attempt_status_ck
    check (attempt_status in (
        'IN_PROGRESS',
        'SUCCEEDED',
        'FAILED',
        'OUTCOME_UNKNOWN',
        'NO_RECORD'
    ));

alter table office_mfcs_attempt add constraint office_mfcs_attempt_json_req_ck
    check (request_payload is json);

alter table office_mfcs_attempt add constraint office_mfcs_attempt_json_resp_ck
    check (response_payload is json);

alter table office_mfcs_attempt add constraint office_mfcs_attempt_corr_uk
    unique (correlation_id);

create unique index office_mfcs_attempt_uk1
    on office_mfcs_attempt (action_request_id, step_code, attempt_number);

create unique index office_mfcs_entity_style_uk
    on office_mfcs_entity_map (
        source_system,
        source_style_ref,
        nvl(source_variant_ref, '-'),
        nvl(source_order_ref, '-')
    );

alter table office_mfcs_config add constraint office_mfcs_config_pk
    primary key (environment, config_key);

alter table office_mfcs_config add constraint office_mfcs_config_enabled_ck
    check (enabled_ind in ('Y', 'N'));

alter table office_mfcs_config add constraint office_mfcs_config_json_ck
    check (
        config_value is null
        or config_key not like 'JSON:%'
        or config_value is json
    );

create index office_mfcs_request_status_ix
    on office_mfcs_request (request_status, last_updated_at);

create index office_mfcs_step_status_ix
    on office_mfcs_step (step_status, step_sequence);

prompt OFFICE MFCS constraints and indexes created

set define off

prompt Creating OFFICE MFCS package specifications

create or replace package office_mfcs_request_pkg authid definer as
    subtype t_status is varchar2(30);

    function get_config(
        p_key         in varchar2,
        p_default     in varchar2 default null,
        p_environment in varchar2 default 'DEFAULT'
    ) return varchar2;

    function payload_hash(p_payload in clob) return varchar2;

    procedure register_request(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2,
        p_payload_hash      in varchar2,
        p_payload           in clob,
        o_result            out varchar2,
        o_status            out varchar2,
        o_response_payload  out clob
    );

    procedure initialize_steps(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2
    );

    function first_runnable_step(
        p_action_request_id in varchar2
    ) return varchar2;

    function step_succeeded(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return boolean;

    procedure set_request_status(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_response_payload  in clob default null
    );

    procedure set_step_status(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_status            in varchar2,
        p_entity_identifier in varchar2 default null,
        p_error_code        in varchar2 default null,
        p_error_message     in varchar2 default null
    );

    procedure save_generated_identifier(
        p_action_request_id   in varchar2,
        p_source_system       in varchar2,
        p_source_style_ref    in varchar2,
        p_mfcs_style_no       in varchar2,
        p_source_variant_ref  in varchar2 default null,
        p_mfcs_sku_no         in varchar2 default null,
        p_sku_size            in varchar2 default null,
        p_sku_width           in varchar2 default null,
        p_source_order_ref    in varchar2 default null,
        p_mfcs_order_no       in varchar2 default null
    );

    procedure begin_attempt(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint          in varchar2,
        p_request_payload   in clob,
        o_attempt_id        out number,
        o_correlation_id    out varchar2
    );

    procedure complete_attempt(
        p_attempt_id       in number,
        p_attempt_status   in varchar2,
        p_http_status      in number default null,
        p_response_payload in clob default null
    );

    function build_status_response(
        p_action_request_id in varchar2,
        p_status_override   in varchar2 default null
    ) return clob;
end office_mfcs_request_pkg;
/

create or replace package office_mfcs_validation_pkg authid definer as
    function validate_request(
        p_payload in clob,
        o_errors  out clob
    ) return boolean;
end office_mfcs_validation_pkg;
/

create or replace package office_mfcs_mapping_pkg authid definer as
    function source_system(p_payload in clob) return varchar2;
    function source_style_ref(p_payload in clob) return varchar2;
    function source_order_ref(p_payload in clob) return varchar2;
    function user_id(p_payload in clob) return varchar2;

    function build_item_number_request(p_action_request_id in varchar2) return clob;
    function build_item_create_request(p_action_request_id in varchar2) return clob;
    function build_item_sourcing_request(p_action_request_id in varchar2) return clob;
    function build_item_uda_request(p_action_request_id in varchar2) return clob;
    function build_item_location_request(p_action_request_id in varchar2) return clob;
    function build_item_approval_request(p_action_request_id in varchar2) return clob;
    function build_initial_retail_request(p_action_request_id in varchar2) return clob;
    function build_po_number_request(p_action_request_id in varchar2) return clob;
    function build_purchase_order_request(p_action_request_id in varchar2) return clob;
    function build_purchase_order_verify_request(p_action_request_id in varchar2) return clob;
end office_mfcs_mapping_pkg;
/

create or replace package office_mfcs_client_pkg authid definer as
    e_downstream_failure exception;
    pragma exception_init(e_downstream_failure, -20950);

    e_downstream_unavailable exception;
    pragma exception_init(e_downstream_unavailable, -20951);

    e_outcome_unknown exception;
    pragma exception_init(e_outcome_unknown, -20952);

    function call_service(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_http_method       in varchar2,
        p_endpoint_key      in varchar2,
        p_request_payload   in clob,
        p_user_id           in varchar2
    ) return clob;

    function correlation_status(
        p_action_request_id in varchar2,
        p_correlation_id    in varchar2
    ) return clob;
end office_mfcs_client_pkg;
/

create or replace package office_mfcs_recovery_pkg authid definer as
    function resolve_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return varchar2;
end office_mfcs_recovery_pkg;
/

create or replace package office_mfcs_orchestrator_pkg authid definer as
    procedure execute_request(
        p_action_request_id in varchar2
    );

    procedure resume_request(
        p_action_request_id in varchar2
    );
end office_mfcs_orchestrator_pkg;
/

create or replace package office_mfcs_api_pkg authid definer as
    procedure submit_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    );

    procedure validate_transaction(
        p_payload      in clob,
        o_http_status  out number,
        o_response     out clob
    );

    procedure get_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
    );

    procedure resume_transaction(
        p_action_request_id in varchar2,
        o_http_status       out number,
        o_response          out clob
    );
end office_mfcs_api_pkg;
/

show errors

prompt OFFICE MFCS package specifications created

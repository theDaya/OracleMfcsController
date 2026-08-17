set define off

-- Public workflow facade used by ORDS. Persistence and integration details stay
-- private to the package body so callers see one small, stable API.
create or replace package office_workflow_pkg authid definer as
    procedure list_requests(p_status in varchar2 default null, p_http_status out number, p_response out clob);
    procedure get_request(p_request_id in varchar2, p_http_status out number, p_response out clob);
    procedure save_draft(p_request_json in clob, p_http_status out number, p_response out clob);
    procedure delete_draft(p_request_id in varchar2, p_http_status out number, p_response out clob);
    procedure submit_request(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob);
    procedure begin_correction(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob);
    procedure return_request(p_request_id in varchar2, p_command_json in clob, p_http_status out number, p_response out clob);
    procedure approve_request(p_request_id in varchar2, p_command_json in clob, p_http_status out number, p_response out clob);
    procedure retry_request(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob);
    procedure resolve_status(p_request_id in varchar2, p_actor_json in clob, p_http_status out number, p_response out clob);
end office_workflow_pkg;
/

show errors

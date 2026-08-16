set define off

prompt Creating Local MFCS service package specification

create or replace package local_mfcs_service_pkg authid definer as
    procedure handle(
        p_resource        in varchar2,
        p_http_method     in varchar2,
        p_request_payload in clob default null,
        p_correlation_id  in varchar2 default null,
        p_order_no        in varchar2 default null,
        p_status_corr_id  in varchar2 default null,
        o_http_status     out number,
        o_response        out clob
    );

    procedure reset_transactional_data;
end local_mfcs_service_pkg;
/

show errors package local_mfcs_service_pkg

prompt Local MFCS service package specification created

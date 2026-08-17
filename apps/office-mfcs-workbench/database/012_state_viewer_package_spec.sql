set define off

-- Read-only projection over the Local MFCS RMS tables.
create or replace package office_mfcs_state_pkg authid definer as
    procedure lookup_state(
        p_identifier  in varchar2,
        p_http_status out number,
        p_response    out clob
    );
end office_mfcs_state_pkg;
/

show errors

set define off

create or replace package office_workflow_http_pkg as
    procedure begin_json;
    function end_json return clob;
    procedure abandon_json;

    function error_json(
        p_code    in varchar2,
        p_message in varchar2
    ) return clob;

    procedure send_json(
        p_http_status in number,
        p_response    in clob
    );
end office_workflow_http_pkg;
/

create or replace package body office_workflow_http_pkg as
    c_http_chunk_size constant pls_integer := 8000;

    procedure begin_json is
    begin
        apex_json.initialize_clob_output(p_preserve => true);
    end begin_json;

    procedure abandon_json is
    begin
        apex_json.free_output;
    exception
        when others then
            null;
    end abandon_json;

    function end_json return clob is
        l_apex_output clob := apex_json.get_clob_output;
        l_result clob;
    begin
        dbms_lob.createtemporary(l_result, true, dbms_lob.call);
        if l_apex_output is not null then
            dbms_lob.copy(l_result, l_apex_output, dbms_lob.getlength(l_apex_output));
        end if;
        apex_json.free_output;
        return l_result;
    exception
        when others then
            abandon_json;
            if dbms_lob.istemporary(l_result) = 1 then
                dbms_lob.freetemporary(l_result);
            end if;
            raise;
    end end_json;

    function error_json(
        p_code    in varchar2,
        p_message in varchar2
    ) return clob is
    begin
        begin_json;
        apex_json.open_object;
        apex_json.write('code', p_code);
        apex_json.write('message', p_message);
        apex_json.close_object;
        return end_json;
    exception
        when others then
            abandon_json;
            raise;
    end error_json;

    -- APEX_JSON writes through HTP safely, including responses over 32 KB.
    procedure send_json(
        p_http_status in number,
        p_response    in clob
    ) is
        l_offset pls_integer := 1;
        l_length pls_integer := coalesce(dbms_lob.getlength(p_response), 0);
    begin
        apex_json.initialize_output(p_http_header => false);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(p_http_status, null, false);
        owa_util.http_header_close;

        -- Preserve explicit JSON nulls while safely streaming large CLOBs.
        while l_offset <= l_length loop
            htp.prn(dbms_lob.substr(p_response, c_http_chunk_size, l_offset));
            l_offset := l_offset + c_http_chunk_size;
        end loop;
    end send_json;
end office_workflow_http_pkg;
/

prompt Office workflow HTTP response package created

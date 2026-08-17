set define off

create or replace package office_workflow_http_pkg as
    procedure send_json(
        p_http_status in number,
        p_response    in clob
    );
end office_workflow_http_pkg;
/

create or replace package body office_workflow_http_pkg as
    c_chunk_size constant pls_integer := 8000;

    -- ORDS/HTP accepts VARCHAR2 output chunks. Streaming the CLOB prevents
    -- ORA-06502 when list or detail responses grow beyond one HTP buffer.
    procedure send_json(
        p_http_status in number,
        p_response    in clob
    ) is
        l_offset pls_integer := 1;
        l_length pls_integer := coalesce(dbms_lob.getlength(p_response), 0);
    begin
        owa_util.mime_header('application/json', false);
        owa_util.status_line(p_http_status, null, false);
        owa_util.http_header_close;

        while l_offset <= l_length loop
            htp.prn(dbms_lob.substr(p_response, c_chunk_size, l_offset));
            l_offset := l_offset + c_chunk_size;
        end loop;
    end send_json;
end office_workflow_http_pkg;
/

prompt Office workflow HTTP response package created

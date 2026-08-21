set define off

-- Chunked ORDS response output.

prompt Creating ords_util_pkg

create or replace package ords_util_pkg authid definer as
    -- Writes a CLOB to the ORDS response in chunks.
    --
    -- htp.prn takes a VARCHAR2, so passing a CLOB larger than 32767 bytes raises
    -- ORA-06502 and ORDS turns that into an opaque HTTP 555. The MFCS item feed
    -- returns roughly 4.6KB per item, so a listing of more than about seven items
    -- crosses that line. Every handler that emits a service response must stream
    -- rather than pass the whole value in one call.
    procedure emit_json(p_body in clob);

    -- Same, for handlers that set an explicit HTTP status.
    procedure emit_json(p_body in clob, p_status in number);
end ords_util_pkg;
/

show errors

create or replace package body ords_util_pkg as
    c_chunk constant pls_integer := 8000;

    procedure write_body(p_body in clob) is
        l_len number;
        l_off number := 1;
    begin
        if p_body is null then
            htp.prn('{}');
            return;
        end if;
        l_len := dbms_lob.getlength(p_body);
        while l_off <= l_len loop
            htp.prn(dbms_lob.substr(p_body, c_chunk, l_off));
            l_off := l_off + c_chunk;
        end loop;
    end;

    procedure emit_json(p_body in clob) is
    begin
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        write_body(p_body);
    end;

    procedure emit_json(p_body in clob, p_status in number) is
    begin
        owa_util.mime_header('application/json', false);
        owa_util.status_line(p_status, null, false);
        owa_util.http_header_close;
        write_body(p_body);
    end;
end ords_util_pkg;
/

show errors

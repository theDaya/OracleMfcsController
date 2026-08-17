set define off

prompt Creating OFFICE MFCS APEX integration helpers

create or replace package office_mfcs_apex_pkg authid definer as
    procedure begin_json;
    function end_json return clob;
    procedure abandon_json;

    procedure write_json_member(
        p_name       in varchar2,
        p_json       in clob,
        p_write_null in boolean default false
    );

    function transaction_error(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_retryable         in boolean,
        p_failed_step       in varchar2,
        p_field             in varchar2,
        p_code              in varchar2,
        p_message           in varchar2
    ) return clob;

    function transaction_validation_error(
        p_action_request_id in varchar2,
        p_errors            in clob
    ) return clob;

    procedure send_json(
        p_http_status in number,
        p_response    in clob
    );
end office_mfcs_apex_pkg;
/

create or replace package body office_mfcs_apex_pkg as
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

    procedure write_json_member(
        p_name       in varchar2,
        p_json       in clob,
        p_write_null in boolean default false
    ) is
        l_values apex_json.t_values;
        l_null varchar2(1);
    begin
        if p_json is null then
            apex_json.write(p_name, l_null, p_write_null);
            return;
        end if;

        apex_json.parse(l_values, p_json);
        apex_json.write(
            p_name       => p_name,
            p_values     => l_values,
            p_path       => '.',
            p_write_null => p_write_null
        );
    end write_json_member;

    function transaction_error(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_retryable         in boolean,
        p_failed_step       in varchar2,
        p_field             in varchar2,
        p_code              in varchar2,
        p_message           in varchar2
    ) return clob is
    begin
        begin_json;
        apex_json.open_object;
        apex_json.write('ACTION_REQUEST_ID', p_action_request_id, true);
        apex_json.write('STATUS', p_status);
        apex_json.write('RETRYABLE', p_retryable);
        apex_json.open_array('COMPLETED_STEPS');
        apex_json.close_array;
        apex_json.write('FAILED_STEP', p_failed_step, true);
        apex_json.open_object('GENERATED_IDENTIFIERS');
        apex_json.close_object;
        apex_json.open_array('ERRORS');
        apex_json.open_object;
        apex_json.write('FIELD', p_field);
        apex_json.write('CODE', p_code);
        apex_json.write('MESSAGE', p_message);
        apex_json.close_object;
        apex_json.close_array;
        apex_json.close_object;
        return end_json;
    exception
        when others then
            abandon_json;
            raise;
    end transaction_error;

    function transaction_validation_error(
        p_action_request_id in varchar2,
        p_errors            in clob
    ) return clob is
        l_null varchar2(1);
    begin
        begin_json;
        apex_json.open_object;
        apex_json.write('ACTION_REQUEST_ID', p_action_request_id);
        apex_json.write('STATUS', 'FAILED_NO_SIDE_EFFECT');
        apex_json.write('RETRYABLE', false);
        apex_json.open_array('COMPLETED_STEPS');
        apex_json.close_array;
        apex_json.write('FAILED_STEP', l_null, true);
        apex_json.open_object('GENERATED_IDENTIFIERS');
        apex_json.close_object;
        write_json_member('ERRORS', p_errors, true);
        apex_json.close_object;
        return end_json;
    exception
        when others then
            abandon_json;
            raise;
    end transaction_validation_error;

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

        -- APEX_JSON has no raw-document writer; emitting the generated CLOB
        -- directly preserves explicit null members and large response bodies.
        while l_offset <= l_length loop
            htp.prn(dbms_lob.substr(p_response, c_http_chunk_size, l_offset));
            l_offset := l_offset + c_http_chunk_size;
        end loop;
    end send_json;
end office_mfcs_apex_pkg;
/

show errors package office_mfcs_apex_pkg
show errors package body office_mfcs_apex_pkg

prompt OFFICE MFCS APEX integration helpers created

set define off

declare
    c_module constant varchar2(100) := 'office-mfcs-workflow';

    procedure define_id_command(p_suffix in varchar2, p_method in varchar2, p_procedure in varchar2, p_body_parameter in varchar2) is
        l_pattern varchar2(200) := 'requests/:id/' || p_suffix;
        l_source clob;
    begin
        ords.define_template(p_module_name => c_module, p_pattern => l_pattern);
        l_source :=
            'declare l_status number; l_response clob; l_body clob := :body_text; begin ' ||
            'office_workflow_pkg.' || p_procedure || '(p_request_id => :id, ' || p_body_parameter || ' => l_body, p_http_status => l_status, p_response => l_response); ' ||
            'office_workflow_http_pkg.send_json(l_status, l_response); end;';
        ords.define_handler(
            p_module_name => c_module,
            p_pattern => l_pattern,
            p_method => p_method,
            p_source_type => ords.source_type_plsql,
            p_source => l_source,
            p_mimes_allowed => 'application/json'
        );
    end;
begin
    ords.enable_schema(
        p_enabled => true,
        p_schema => user,
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => lower(user),
        p_auto_rest_auth => false
    );

    ords.define_module(
        p_module_name => c_module,
        p_base_path => '/office-workflow/v1/',
        p_items_per_page => 100,
        p_status => 'PUBLISHED',
        p_comments => 'Oracle-backed Office MFCS POC workflow API.'
    );

    ords.define_template(p_module_name => c_module, p_pattern => 'requests');
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'requests',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[declare l_status number; l_response clob; begin office_workflow_pkg.list_requests(:status, l_status, l_response); office_workflow_http_pkg.send_json(l_status, l_response); end;]'
    );
    ords.define_parameter(c_module, 'requests', 'GET', 'status', 'status', 'URI', 'STRING', 'IN');

    ords.define_template(p_module_name => c_module, p_pattern => 'requests/:id');
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'requests/:id',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[declare l_status number; l_response clob; begin office_workflow_pkg.get_request(:id, l_status, l_response); office_workflow_http_pkg.send_json(l_status, l_response); end;]'
    );
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'requests/:id',
        p_method => 'PUT',
        p_source_type => ords.source_type_plsql,
        p_source => q'[declare l_status number; l_response clob; l_body clob := :body_text; begin office_workflow_pkg.save_draft(l_body, l_status, l_response); office_workflow_http_pkg.send_json(l_status, l_response); end;]',
        p_mimes_allowed => 'application/json'
    );
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'requests/:id',
        p_method => 'DELETE',
        p_source_type => ords.source_type_plsql,
        p_source => q'[declare l_status number; l_response clob; begin office_workflow_pkg.delete_draft(:id, l_status, l_response); office_workflow_http_pkg.send_json(l_status, l_response); end;]'
    );

    define_id_command('submit', 'POST', 'submit_request', 'p_actor_json');
    define_id_command('correct', 'POST', 'begin_correction', 'p_actor_json');
    define_id_command('return', 'POST', 'return_request', 'p_command_json');
    define_id_command('approve', 'POST', 'approve_request', 'p_command_json');
    define_id_command('retry', 'POST', 'retry_request', 'p_actor_json');
    define_id_command('status', 'POST', 'resolve_status', 'p_actor_json');

    ords.define_template(p_module_name => c_module, p_pattern => 'state/:identifier');
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'state/:identifier',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[declare l_status number; l_response clob; begin office_mfcs_state_pkg.lookup_state(:identifier, l_status, l_response); office_workflow_http_pkg.send_json(l_status, l_response); end;]'
    );

    ords.define_template(p_module_name => c_module, p_pattern => 'health');
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'health',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[begin owa_util.mime_header('application/json', false); owa_util.status_line(200, null, false); owa_util.http_header_close; htp.prn('{"status":"UP","service":"office-mfcs-workflow"}'); end;]'
    );

    commit;
end;
/

prompt Office workflow ORDS module created

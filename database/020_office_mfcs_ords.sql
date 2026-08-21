set define off

prompt Creating OFFICE MFCS ORDS module

declare
    l_roles owa.vc_arr;
    l_patterns owa.vc_arr;
begin
    ords.enable_schema(
        p_enabled => true,
        p_schema => user,
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => lower(user),
        p_auto_rest_auth => false
    );

    ords.define_module(
        p_module_name => 'office-mfcs-v1',
        p_base_path => '/office-mfcs/v1/',
        p_items_per_page => 25,
        p_status => 'PUBLISHED',
        p_comments => 'Office-approved transaction integration layer for Oracle MFCS.'
    );

    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    office_mfcs_api_pkg.submit_transaction(:body_text, l_http_status, l_response);
    office_mfcs_ords_util_pkg.emit_json(l_response, l_http_status);
end;
]'
    );

    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/validate'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/validate',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    office_mfcs_api_pkg.validate_transaction(:body_text, l_http_status, l_response);
    office_mfcs_ords_util_pkg.emit_json(l_response, l_http_status);
end;
]'
    );

    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/:actionRequestId'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/:actionRequestId',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    office_mfcs_api_pkg.get_transaction(:actionRequestId, l_http_status, l_response);
    office_mfcs_ords_util_pkg.emit_json(l_response, l_http_status);
end;
]'
    );

    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/:actionRequestId/resume'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/:actionRequestId/resume',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    office_mfcs_api_pkg.resume_transaction(:actionRequestId, l_http_status, l_response);
    office_mfcs_ords_util_pkg.emit_json(l_response, l_http_status);
end;
]'
    );

    begin
        ords.create_role('office-mfcs-integration-support');
    exception
        when others then
            if sqlcode <> -1 then
                null;
            end if;
    end;

    l_roles(1) := 'office-mfcs-integration-support';
    l_patterns(1) := '/office-mfcs/v1/transactions/*/resume';

    ords.define_privilege(
        p_privilege_name => 'office-mfcs-resume-support',
        p_roles => l_roles,
        p_patterns => l_patterns,
        p_label => 'Office MFCS resume support',
        p_description => 'Allows integration-support users to resume partial or ambiguous Office MFCS transactions.'
    );

    commit;
end;
/

prompt OFFICE MFCS ORDS module created

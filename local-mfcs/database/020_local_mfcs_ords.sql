set define off

prompt Creating Local MFCS public-contract ORDS module

declare
    c_module constant varchar2(100) := 'local-mfcs-public-contract';

    procedure define_body_handler(
        p_pattern  in varchar2,
        p_method   in varchar2,
        p_resource in varchar2
    ) is
        l_source clob;
    begin
        ords.define_template(
            p_module_name => c_module,
            p_pattern => p_pattern
        );
        l_source :=
            'declare' || chr(10) ||
            '  l_body clob := :body_text;' || chr(10) ||
            '  l_status number;' || chr(10) ||
            '  l_response clob;' || chr(10) ||
            'begin' || chr(10) ||
            '  local_mfcs_service_pkg.handle(' || chr(10) ||
            '    p_resource => ''' || p_resource || ''',' || chr(10) ||
            '    p_http_method => ''' || p_method || ''',' || chr(10) ||
            '    p_request_payload => l_body,' || chr(10) ||
            '    p_correlation_id => :x_correlation_id,' || chr(10) ||
            '    p_http_status => l_status,' || chr(10) ||
            '    p_response => l_response);' || chr(10) ||
            '  office_mfcs_apex_pkg.send_json(l_status, l_response);' || chr(10) ||
            'end;';
        ords.define_handler(
            p_module_name => c_module,
            p_pattern => p_pattern,
            p_method => p_method,
            p_source_type => ords.source_type_plsql,
            p_source => l_source,
            p_mimes_allowed => case when p_resource = 'TOKEN' then 'application/x-www-form-urlencoded' else 'application/json' end
        );
        ords.define_parameter(
            p_module_name => c_module,
            p_pattern => p_pattern,
            p_method => p_method,
            p_name => 'X-Correlation-ID',
            p_bind_variable_name => 'x_correlation_id',
            p_source_type => 'HEADER',
            p_param_type => 'STRING',
            p_access_method => 'IN'
        );
    end;

    procedure define_simple_handler(
        p_pattern  in varchar2,
        p_method   in varchar2,
        p_resource in varchar2
    ) is
        l_source clob;
    begin
        ords.define_template(
            p_module_name => c_module,
            p_pattern => p_pattern
        );
        l_source :=
            'declare' || chr(10) ||
            '  l_status number;' || chr(10) ||
            '  l_response clob;' || chr(10) ||
            'begin' || chr(10) ||
            '  local_mfcs_service_pkg.handle(' || chr(10) ||
            '    p_resource => ''' || p_resource || ''',' || chr(10) ||
            '    p_http_method => ''' || p_method || ''',' || chr(10) ||
            '    p_correlation_id => :x_correlation_id,' || chr(10) ||
            '    p_http_status => l_status,' || chr(10) ||
            '    p_response => l_response);' || chr(10) ||
            '  office_mfcs_apex_pkg.send_json(l_status, l_response);' || chr(10) ||
            'end;';
        ords.define_handler(
            p_module_name => c_module,
            p_pattern => p_pattern,
            p_method => p_method,
            p_source_type => ords.source_type_plsql,
            p_source => l_source
        );
        ords.define_parameter(
            p_module_name => c_module,
            p_pattern => p_pattern,
            p_method => p_method,
            p_name => 'X-Correlation-ID',
            p_bind_variable_name => 'x_correlation_id',
            p_source_type => 'HEADER',
            p_param_type => 'STRING',
            p_access_method => 'IN'
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
        p_base_path => '/local-mfcs/',
        p_items_per_page => 100,
        p_status => 'PUBLISHED',
        p_comments => 'Stateful RMS-shaped Local MFCS simulator for integration testing.'
    );

    define_body_handler('oauth2/v1/token', 'POST', 'TOKEN');
    define_body_handler('MerchIntegrations/services/item/itemNumbers/reserve', 'POST', 'RESERVE_ITEM_NUMBERS');
    define_body_handler('MerchIntegrations/services/items/create', 'POST', 'ITEMS');
    define_body_handler('MerchIntegrations/services/items/update', 'PUT', 'ITEMS');
    define_body_handler('MerchIntegrations/services/item/suppliers/create', 'POST', 'ITEM_SUPPLIERS');
    define_body_handler('MerchIntegrations/services/item/suppliers/update', 'PUT', 'ITEM_SUPPLIERS');
    define_body_handler('MerchIntegrations/services/item/uda/create', 'POST', 'ITEM_UDAS');
    define_body_handler('MerchIntegrations/services/item/uda/update', 'PUT', 'ITEM_UDAS');
    define_body_handler('MerchIntegrations/services/item/locations/create', 'POST', 'ITEM_LOCATIONS');
    define_body_handler('MerchIntegrations/services/item/locations/update', 'PUT', 'ITEM_LOCATIONS');
    define_body_handler('MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create', 'POST', 'RESERVE_ORDER_NUMBERS');
    define_body_handler('MerchIntegrations/services/purchaseOrders/create', 'POST', 'PURCHASE_ORDERS');
    define_body_handler('MerchIntegrations/services/purchaseOrders/update', 'PUT', 'PURCHASE_ORDERS');
    define_simple_handler('__admin/state', 'GET', 'STATE');
    define_simple_handler('__admin/reset', 'POST', 'RESET');

    ords.define_template(
        p_module_name => c_module,
        p_pattern => 'MerchIntegrations/services/procurement/order/:orderNo'
    );
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'MerchIntegrations/services/procurement/order/:orderNo',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_status number;
    l_response clob;
begin
    local_mfcs_service_pkg.handle(
        p_resource => 'GET_ORDER',
        p_http_method => 'GET',
        p_correlation_id => :x_correlation_id,
        p_order_no => :orderNo,
        p_http_status => l_status,
        p_response => l_response);
    office_mfcs_apex_pkg.send_json(l_status, l_response);
end;
]'
    );
    ords.define_parameter(c_module, 'MerchIntegrations/services/procurement/order/:orderNo', 'GET', 'X-Correlation-ID', 'x_correlation_id', 'HEADER', 'STRING', 'IN');

    ords.define_template(
        p_module_name => c_module,
        p_pattern => 'MerchIntegrations/services/administration/operations/restService/status'
    );
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'MerchIntegrations/services/administration/operations/restService/status',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_status number;
    l_response clob;
begin
    local_mfcs_service_pkg.handle(
        p_resource => 'GET_STATUS',
        p_http_method => 'GET',
        p_correlation_id => :x_correlation_id,
        p_status_corr_id => :xCorrelationId,
        p_http_status => l_status,
        p_response => l_response);
    office_mfcs_apex_pkg.send_json(l_status, l_response);
end;
]'
    );
    ords.define_parameter(c_module, 'MerchIntegrations/services/administration/operations/restService/status', 'GET', 'X-Correlation-ID', 'x_correlation_id', 'HEADER', 'STRING', 'IN');
    ords.define_parameter(c_module, 'MerchIntegrations/services/administration/operations/restService/status', 'GET', 'xCorrelationId', 'xCorrelationId', 'URI', 'STRING', 'IN');

    ords.define_template(
        p_module_name => c_module,
        p_pattern => 'health'
    );
    ords.define_handler(
        p_module_name => c_module,
        p_pattern => 'health',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_response clob;
begin
    office_mfcs_apex_pkg.begin_json;
    apex_json.open_object;
    apex_json.write('status', 'UP');
    apex_json.write('service', 'local-mfcs-rms-simulator');
    apex_json.close_object;
    l_response := office_mfcs_apex_pkg.end_json;
    office_mfcs_apex_pkg.send_json(200, l_response);
end;
]'
    );

    commit;
end;
/

prompt Local MFCS public-contract ORDS module created

set define off

prompt Creating OFFICE MFCS preview and UI-support ORDS handlers

declare
    l_origins owa.vc_arr;
begin
    -- Adds to the existing office-mfcs-v1 module rather than defining a new one.
    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/preview'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'transactions/preview',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_http_status number;
    l_response clob;
begin
    office_mfcs_preview_pkg.preview_transaction(:body_text, l_http_status, l_response);
    :status_code := l_http_status;
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.prn(l_response);
end;
]'
    );

    -- Reference data for the entry form, read straight from OFFICE_MFCS_CONFIG so
    -- the UI offers exactly the values this environment can actually map.
    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'reference-data'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'reference-data',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_arr json_array_t;
    l_item json_object_t;

    procedure collect(p_prefix in varchar2, p_name in varchar2) is
        l_local json_array_t := json_array_t();
        l_entry json_object_t;
    begin
        for c in (
            select substr(config_key, length(p_prefix) + 1) code,
                   dbms_lob.substr(config_value, 400, 1) mapped
              from office_mfcs_config
             where config_key like p_prefix || '%'
               and environment = 'DEFAULT'
               and enabled_ind = 'Y'
             order by 1
        ) loop
            l_entry := json_object_t();
            l_entry.put('code', c.code);
            l_entry.put('mapped', c.mapped);
            l_local.append(l_entry);
        end loop;
        l_root.put(p_name, l_local);
    end;
begin
    collect('MAP.DEPARTMENT.', 'departments');
    collect('MAP.CLASS.', 'classes');
    collect('MAP.SUBCLASS.', 'subclasses');
    collect('MAP.SUPPLIER.', 'suppliers');
    collect('MAP.COUNTRY.', 'countries');
    collect('MAP.CURRENCY.', 'currencies');
    collect('MAP.COLOUR.', 'colours');
    collect('MAP.SIZE.', 'sizes');
    collect('MAP.WIDTH.', 'widths');
    collect('MAP.ORDER_LOCATION.', 'orderLocations');
    collect('ENDPOINT.', 'endpoints');

    l_arr := json_array_t();
    for o in (
        select column_value op from table(sys.odcivarchar2list(
            'CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL', 'MODIFY_STYLE', 'MODIFY_ORDER'))
    ) loop
        l_arr.append(o.op);
    end loop;
    l_root.put('operations', l_arr);

    l_item := json_object_t();
    for c in (
        select config_key, dbms_lob.substr(config_value, 400, 1) v
          from office_mfcs_config
         where environment = 'DEFAULT'
           and enabled_ind = 'Y'
           and config_key in ('MFCS_AUTH_MODE', 'MFCS_BASE_URL',
                              'FEATURE_ITEM_LOCATIONS_YN', 'FEATURE_INITIAL_RETAIL_YN',
                              'BATCH_WINDOW_ACTIVE_YN')
    ) loop
        l_item.put(c.config_key, c.v);
    end loop;
    l_root.put('runtime', l_item);

    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.prn(l_root.to_clob);
end;
]'
    );

    -- Recent requests, so the UI can show what has been submitted and its outcome.
    ords.define_template(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'requests'
    );

    ords.define_handler(
        p_module_name => 'office-mfcs-v1',
        p_pattern => 'requests',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_arr json_array_t := json_array_t();
    l_row json_object_t;
begin
    for r in (
        select action_request_id, operation_name, request_status, style_no, order_no,
               to_char(last_updated_at, 'YYYY-MM-DD"T"HH24:MI:SS') updated
          from office_mfcs_request
         where action_request_id not like 'PREVIEW-%'
         order by last_updated_at desc
         fetch first 50 rows only
    ) loop
        l_row := json_object_t();
        l_row.put('actionRequestId', r.action_request_id);
        l_row.put('operationName', r.operation_name);
        l_row.put('requestStatus', r.request_status);
        l_row.put('styleNo', r.style_no);
        l_row.put('orderNo', r.order_no);
        l_row.put('lastUpdatedAt', r.updated);
        l_arr.append(l_row);
    end loop;
    l_root.put('items', l_arr);
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.prn(l_root.to_clob);
end;
]'
    );

    commit;
end;
/

-- Allow the React dev server to call these handlers.
begin
    ords.delete_privilege_mapping(
        p_privilege_name => 'office-mfcs-resume-support',
        p_pattern => '/office-mfcs/v1/transactions/preview'
    );
exception
    when others then null;
end;
/

prompt OFFICE MFCS preview and UI-support ORDS handlers created

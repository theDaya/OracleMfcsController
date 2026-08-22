set define off

prompt Creating OFFICE MFCS browse and master-data ORDS handlers

begin
    -- Live style listing for the browse screen.
    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'styles');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'styles',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
begin
    ords_util_pkg.emit_json(browse_pkg.list_styles(
        p_limit => to_number(nvl(:limit, '50')),
        p_dept => :dept,
        p_item_level => nvl(:itemLevel, '1')
    ));
end;
]'
    );

    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'styles/:item');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'styles/:item',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
begin
    ords_util_pkg.emit_json(browse_pkg.get_style(:item, nvl(:withSkus, 'N')));
end;
]'
    );

    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'orders');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'orders',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
begin
    ords_util_pkg.emit_json(browse_pkg.list_orders(
        p_limit => to_number(nvl(:limit, '50')),
        p_supplier => :supplier
    ));
end;
]'
    );

    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'orders/:orderNo');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'orders/:orderNo',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
begin
    ords_util_pkg.emit_json(browse_pkg.get_order(:orderNo, nvl(:enrich, 'Y')));
end;
]'
    );

    -- Bearer token health, so an expired credential is visible in the console
    -- instead of showing up as unexplained blank listings.
    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'token-status');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'token-status',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
begin
    ords_util_pkg.emit_json(client_pkg.token_status);
end;
]'
    );

    -- Cached master data, grouped by type, for dropdowns and the browse screen.
    ords.define_template(p_module_name => 'mfcs-v1', p_pattern => 'master-data');
    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'master-data',
        p_method => 'GET',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_root json_object_t := json_object_t();
    l_types json_object_t := json_object_t();
    l_arr json_array_t;
    l_row json_object_t;
    l_log json_array_t := json_array_t();
    l_current varchar2(40);
begin
    l_arr := json_array_t();
    for r in (
        select data_type, data_code, parent_code, description
          from master_data
         order by data_type,
                  case when regexp_like(data_code, '^\d+$') then lpad(data_code, 20, '0') else data_code end
    ) loop
        if l_current is null then
            l_current := r.data_type;
        elsif l_current <> r.data_type then
            l_types.put(l_current, l_arr);
            l_arr := json_array_t();
            l_current := r.data_type;
        end if;
        l_row := json_object_t();
        l_row.put('code', r.data_code);
        l_row.put('parent', case when r.parent_code = '~' then null else r.parent_code end);
        l_row.put('description', r.description);
        l_arr.append(l_row);
    end loop;
    if l_current is not null then
        l_types.put(l_current, l_arr);
    end if;
    l_root.put('types', l_types);

    for r in (
        select data_type, source, http_status, row_count, message,
               to_char(completed_at, 'YYYY-MM-DD"T"HH24:MI:SS') completed
          from master_refresh order by data_type
    ) loop
        l_row := json_object_t();
        l_row.put('dataType', r.data_type);
        l_row.put('source', r.source);
        l_row.put('httpStatus', r.http_status);
        l_row.put('rowCount', r.row_count);
        l_row.put('message', r.message);
        l_row.put('completedAt', r.completed);
        l_log.append(l_row);
    end loop;
    l_root.put('log', l_log);

    ords_util_pkg.emit_json(l_root.to_clob);
end;
]'
    );

    ords.define_handler(
        p_module_name => 'mfcs-v1',
        p_pattern => 'master-data',
        p_method => 'POST',
        p_source_type => ords.source_type_plsql,
        p_source => q'[
declare
    l_summary clob;
begin
    master_pkg.refresh_all(l_summary);
    ords_util_pkg.emit_json(l_summary);
end;
]'
    );

    commit;
end;
/

prompt OFFICE MFCS browse and master-data ORDS handlers created

set define off

create or replace package body office_mfcs_state_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_MFCS_STATE_PKG';

    -- Keep transport errors small and consistent with the workflow API.
    function error_response(p_message in varchar2) return clob is
    begin
        return office_workflow_http_pkg.error_json('STATE_LOOKUP', p_message);
    end error_response;

    procedure lookup_state(
        p_identifier  in varchar2,
        p_http_status out number,
        p_response    out clob
    ) is
        l_identifier varchar2(100) := trim(p_identifier);
        l_found_by varchar2(10);
        l_style_id varchar2(25);
        l_order_no number(12);
        l_count number;
        l_error_message varchar2(4000);
        l_output_active boolean := false;
    begin
        if l_identifier is null then
            p_http_status := 400;
            p_response := error_response('An order or style number is required.');
            office_workflow_log_pkg.info(c_package_name, 'LOOKUP_STATE', null, 'Empty state lookup rejected');
            return;
        end if;

        select count(*), max(order_no)
          into l_count, l_order_no
          from office_mfcs_app.ordhead
         where to_char(order_no) = l_identifier;

        if l_count = 1 then
            l_found_by := 'ORDER';
        else
            begin
                select coalesce(item_grandparent, item_parent, item)
                  into l_style_id
                  from office_mfcs_app.item_master
                 where item = l_identifier;
                l_found_by := case when l_style_id = l_identifier then 'STYLE' else 'SKU' end;
            exception
                when no_data_found then
                    p_http_status := 404;
                    p_response := error_response('No MFCS order, style, or SKU was found for ' || l_identifier);
                    office_workflow_log_pkg.info(c_package_name, 'LOOKUP_STATE', null, 'Identifier ' || l_identifier || ' was not found');
                    return;
            end;
        end if;

        office_workflow_http_pkg.begin_json;
        l_output_active := true;
        apex_json.open_object;
        apex_json.write('query', l_identifier);
        apex_json.write('foundBy', l_found_by);
        apex_json.open_array('styles');

        for l_row in (
            select im.*
              from office_mfcs_app.item_master im
             where im.item_level = 1
               and (
                    (l_found_by = 'ORDER' and exists (
                        select 1
                          from office_mfcs_app.ordsku os
                          join office_mfcs_app.item_master oi on oi.item = os.item
                         where os.order_no = l_order_no
                           and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = im.item
                    ))
                    or (l_found_by <> 'ORDER' and im.item = l_style_id)
               )
             order by im.item
        ) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('description', l_row.item_desc);
            apex_json.write('shortDescription', l_row.short_desc, true);
            apex_json.write('department', l_row.dept);
            apex_json.write('classNumber', l_row.class);
            apex_json.write('subclass', l_row.subclass);
            apex_json.write('status', l_row.status);
            apex_json.write('approved', l_row.approve_ind);
            apex_json.write('originalRetail', l_row.original_retail, true);
            apex_json.write('approvedBy', l_row.approved_by, true);
            apex_json.write('approvedAt', to_char(l_row.approved_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'), true);
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('items');

        for l_row in (
            select im.*
              from office_mfcs_app.item_master im
             where (
                    (l_found_by = 'ORDER' and exists (
                        select 1
                          from office_mfcs_app.ordsku os
                          join office_mfcs_app.item_master oi on oi.item = os.item
                         where os.order_no = l_order_no
                           and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = coalesce(im.item_grandparent, im.item_parent, im.item)
                    ))
                    or (l_found_by <> 'ORDER' and coalesce(im.item_grandparent, im.item_parent, im.item) = l_style_id)
               )
             order by im.item_level, im.item
        ) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('itemParent', l_row.item_parent, true);
            apex_json.write('itemGrandparent', l_row.item_grandparent, true);
            apex_json.write('itemLevel', l_row.item_level);
            apex_json.write('transactionLevel', l_row.tran_level);
            apex_json.write('description', l_row.item_desc);
            apex_json.write('status', l_row.status);
            apex_json.write('approved', l_row.approve_ind);
            apex_json.write('standardUom', l_row.standard_uom);
            apex_json.write('diff1', l_row.diff_1, true);
            apex_json.write('diff2', l_row.diff_2, true);
            apex_json.write('diff3', l_row.diff_3, true);
            apex_json.write('diff4', l_row.diff_4, true);
            apex_json.write('originalRetail', l_row.original_retail, true);
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('sourcing');

        for l_row in (
            select ims.item, ims.supplier, s.sup_name, ims.primary_supp_ind, ims.vpn,
                   isc.origin_country_id, isc.primary_country_ind, isc.unit_cost,
                   isc.currency_code, isc.lead_time, isc.pickup_lead_time,
                   isc.default_uop, isc.supp_pack_size
              from office_mfcs_app.item_supplier ims
              join office_mfcs_app.sups s on s.supplier = ims.supplier
              left join office_mfcs_app.item_supp_country isc
                on isc.item = ims.item and isc.supplier = ims.supplier
              join office_mfcs_app.item_master im on im.item = ims.item
             where (
                    (l_found_by = 'ORDER' and exists (
                        select 1 from office_mfcs_app.ordsku os
                        join office_mfcs_app.item_master oi on oi.item = os.item
                        where os.order_no = l_order_no
                          and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = coalesce(im.item_grandparent, im.item_parent, im.item)
                    ))
                    or (l_found_by <> 'ORDER' and coalesce(im.item_grandparent, im.item_parent, im.item) = l_style_id)
               )
             order by ims.item, ims.primary_supp_ind desc, isc.primary_country_ind desc, isc.origin_country_id
        ) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('supplier', l_row.supplier);
            apex_json.write('supplierName', l_row.sup_name);
            apex_json.write('primarySupplier', l_row.primary_supp_ind);
            apex_json.write('vpn', l_row.vpn, true);
            apex_json.write('originCountry', l_row.origin_country_id, true);
            apex_json.write('primaryCountry', l_row.primary_country_ind, true);
            apex_json.write('unitCost', l_row.unit_cost, true);
            apex_json.write('currencyCode', l_row.currency_code, true);
            apex_json.write('leadTime', l_row.lead_time, true);
            apex_json.write('pickupLeadTime', l_row.pickup_lead_time, true);
            apex_json.write('defaultUop', l_row.default_uop, true);
            apex_json.write('supplierPackSize', l_row.supp_pack_size, true);
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('locations');

        for l_row in (
            select il.item, il.location, il.loc_type, il.status, il.primary_supp,
                   il.source_method, il.unit_retail,
                   case il.loc_type when 'S' then st.store_name else w.wh_name end location_name
              from office_mfcs_app.item_loc il
              join office_mfcs_app.item_master im on im.item = il.item
              left join office_mfcs_app.store st on il.loc_type = 'S' and st.store = il.location
              left join office_mfcs_app.wh w on il.loc_type = 'W' and w.wh = il.location
             where (
                    (l_found_by = 'ORDER' and exists (
                        select 1 from office_mfcs_app.ordsku os
                        join office_mfcs_app.item_master oi on oi.item = os.item
                        where os.order_no = l_order_no
                          and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = coalesce(im.item_grandparent, im.item_parent, im.item)
                    ))
                    or (l_found_by <> 'ORDER' and coalesce(im.item_grandparent, im.item_parent, im.item) = l_style_id)
               )
             order by il.item, il.loc_type, il.location
        ) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('location', l_row.location);
            apex_json.write('locationType', l_row.loc_type);
            apex_json.write('locationName', l_row.location_name, true);
            apex_json.write('status', l_row.status);
            apex_json.write('primarySupplier', l_row.primary_supp, true);
            apex_json.write('sourceMethod', l_row.source_method);
            apex_json.write('unitRetail', l_row.unit_retail, true);
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('udas');

        for l_row in (
            select iu.item, iu.uda_id, iu.uda_value
              from office_mfcs_app.item_uda iu
              join office_mfcs_app.item_master im on im.item = iu.item
             where (
                    (l_found_by = 'ORDER' and exists (
                        select 1 from office_mfcs_app.ordsku os
                        join office_mfcs_app.item_master oi on oi.item = os.item
                        where os.order_no = l_order_no
                          and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = coalesce(im.item_grandparent, im.item_parent, im.item)
                    ))
                    or (l_found_by <> 'ORDER' and coalesce(im.item_grandparent, im.item_parent, im.item) = l_style_id)
               )
             order by iu.item, iu.uda_id
        ) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('udaId', l_row.uda_id);
            apex_json.write('value', l_row.uda_value);
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('orders');

        for l_order_row in (
            select oh.*
              from office_mfcs_app.ordhead oh
             where (l_found_by = 'ORDER' and oh.order_no = l_order_no)
                or (l_found_by <> 'ORDER' and exists (
                    select 1
                      from office_mfcs_app.ordsku os
                      join office_mfcs_app.item_master oi on oi.item = os.item
                     where os.order_no = oh.order_no
                       and coalesce(oi.item_grandparent, oi.item_parent, oi.item) = l_style_id
                ))
             order by oh.order_no desc
        ) loop
            apex_json.open_object;
            apex_json.write('orderNo', l_order_row.order_no);
            apex_json.write('orderType', l_order_row.order_type);
            apex_json.write('supplier', l_order_row.supplier);
            apex_json.write('department', l_order_row.dept);
            apex_json.write('status', l_order_row.status);
            apex_json.write('currencyCode', l_order_row.currency_code);
            apex_json.write('exchangeRate', l_order_row.exchange_rate);
            apex_json.write('notBeforeDate', to_char(l_order_row.not_before_date, 'YYYY-MM-DD'), true);
            apex_json.write('notAfterDate', to_char(l_order_row.not_after_date, 'YYYY-MM-DD'), true);
            apex_json.write('earliestShipDate', to_char(l_order_row.earliest_ship_date, 'YYYY-MM-DD'), true);
            apex_json.write('latestShipDate', to_char(l_order_row.latest_ship_date, 'YYYY-MM-DD'), true);
            apex_json.write('totalQuantity', l_order_row.total_qty_ordered);
            apex_json.write('totalCost', l_order_row.total_cost);
            apex_json.write('sourceSystem', l_order_row.source_system);
            apex_json.write('approvedBy', l_order_row.approved_by, true);
            apex_json.write('approvedAt', to_char(l_order_row.approved_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'), true);
            apex_json.open_array('lines');

            for l_line_row in (
                select ol.item, im.item_desc, im.diff_1, im.diff_2, im.diff_3,
                       ol.location, ol.loc_type, ol.origin_country_id,
                       ol.qty_ordered, ol.qty_received, ol.qty_cancelled,
                       ol.unit_cost, ol.unit_retail, ol.earliest_ship_date, ol.latest_ship_date
                  from office_mfcs_app.ordloc ol
                  join office_mfcs_app.item_master im on im.item = ol.item
                 where ol.order_no = l_order_row.order_no
                 order by ol.item, ol.location
            ) loop
                apex_json.open_object;
                apex_json.write('item', l_line_row.item);
                apex_json.write('description', l_line_row.item_desc);
                apex_json.write('diff1', l_line_row.diff_1, true);
                apex_json.write('diff2', l_line_row.diff_2, true);
                apex_json.write('diff3', l_line_row.diff_3, true);
                apex_json.write('location', l_line_row.location);
                apex_json.write('locationType', l_line_row.loc_type);
                apex_json.write('originCountry', l_line_row.origin_country_id);
                apex_json.write('quantityOrdered', l_line_row.qty_ordered);
                apex_json.write('quantityReceived', l_line_row.qty_received);
                apex_json.write('quantityCancelled', l_line_row.qty_cancelled);
                apex_json.write('unitCost', l_line_row.unit_cost);
                apex_json.write('unitRetail', l_line_row.unit_retail, true);
                apex_json.write('earliestShipDate', to_char(l_line_row.earliest_ship_date, 'YYYY-MM-DD'), true);
                apex_json.write('latestShipDate', to_char(l_line_row.latest_ship_date, 'YYYY-MM-DD'), true);
                apex_json.close_object;
            end loop;
            apex_json.close_array;
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.open_array('events');

        for l_row in (
            select * from (
                select event_id, correlation_id, service_name, http_method, response_code, started_at, completed_at
                  from office_mfcs_app.local_mfcs_rest_event e
                 where dbms_lob.instr(e.request_payload, l_identifier) > 0
                    or dbms_lob.instr(e.response_payload, l_identifier) > 0
                 order by event_id desc
            ) where rownum <= 20
        ) loop
            apex_json.open_object;
            apex_json.write('eventId', l_row.event_id);
            apex_json.write('correlationId', l_row.correlation_id);
            apex_json.write('serviceName', l_row.service_name);
            apex_json.write('httpMethod', l_row.http_method);
            apex_json.write('responseCode', l_row.response_code);
            apex_json.write('startedAt', to_char(l_row.started_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.write('completedAt', to_char(l_row.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.close_object;
        end loop;

        apex_json.close_array;
        apex_json.close_object;
        p_http_status := 200;
        p_response := office_workflow_http_pkg.end_json;
        l_output_active := false;
        office_workflow_log_pkg.info(c_package_name, 'LOOKUP_STATE', null, l_found_by || ' ' || l_identifier || ' returned');
    exception
        when others then
            if l_output_active then
                office_workflow_http_pkg.abandon_json;
            end if;
            l_error_message := sqlerrm;
            p_http_status := 500;
            p_response := error_response('MFCS state lookup failed: ' || l_error_message);
            office_workflow_log_pkg.error(c_package_name, 'LOOKUP_STATE', null, 'Lookup failed for ' || l_identifier, l_error_message);
    end lookup_state;
end office_mfcs_state_pkg;
/

show errors

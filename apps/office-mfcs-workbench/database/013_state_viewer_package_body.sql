set define off

create or replace package body office_mfcs_state_pkg as
    c_package_name constant varchar2(128) := 'OFFICE_MFCS_STATE_PKG';

    -- Keep transport errors small and consistent with the workflow API.
    function error_response(p_message in varchar2) return clob is
        l_error json_object_t := json_object_t();
    begin
        l_error.put('message', p_message);
        return l_error.to_clob;
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
        l_root json_object_t := json_object_t();
        l_styles json_array_t := json_array_t();
        l_items json_array_t := json_array_t();
        l_sourcing json_array_t := json_array_t();
        l_locations json_array_t := json_array_t();
        l_udas json_array_t := json_array_t();
        l_orders json_array_t := json_array_t();
        l_events json_array_t := json_array_t();
        l_node json_object_t;
        l_order json_object_t;
        l_lines json_array_t;
        l_error_message varchar2(4000);
    begin
        if l_identifier is null then
            p_http_status := 400;
            p_response := '{"message":"An order or style number is required."}';
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
            l_node := json_object_t();
            l_node.put('item', l_row.item);
            l_node.put('description', l_row.item_desc);
            if l_row.short_desc is null then l_node.put_null('shortDescription'); else l_node.put('shortDescription', l_row.short_desc); end if;
            l_node.put('department', l_row.dept);
            l_node.put('classNumber', l_row.class);
            l_node.put('subclass', l_row.subclass);
            l_node.put('status', l_row.status);
            l_node.put('approved', l_row.approve_ind);
            if l_row.original_retail is null then l_node.put_null('originalRetail'); else l_node.put('originalRetail', l_row.original_retail); end if;
            if l_row.approved_by is null then l_node.put_null('approvedBy'); else l_node.put('approvedBy', l_row.approved_by); end if;
            if l_row.approved_at is null then l_node.put_null('approvedAt'); else l_node.put('approvedAt', to_char(l_row.approved_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM')); end if;
            l_styles.append(l_node);
        end loop;

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
            l_node := json_object_t();
            l_node.put('item', l_row.item);
            if l_row.item_parent is null then l_node.put_null('itemParent'); else l_node.put('itemParent', l_row.item_parent); end if;
            if l_row.item_grandparent is null then l_node.put_null('itemGrandparent'); else l_node.put('itemGrandparent', l_row.item_grandparent); end if;
            l_node.put('itemLevel', l_row.item_level);
            l_node.put('transactionLevel', l_row.tran_level);
            l_node.put('description', l_row.item_desc);
            l_node.put('status', l_row.status);
            l_node.put('approved', l_row.approve_ind);
            l_node.put('standardUom', l_row.standard_uom);
            if l_row.diff_1 is null then l_node.put_null('diff1'); else l_node.put('diff1', l_row.diff_1); end if;
            if l_row.diff_2 is null then l_node.put_null('diff2'); else l_node.put('diff2', l_row.diff_2); end if;
            if l_row.diff_3 is null then l_node.put_null('diff3'); else l_node.put('diff3', l_row.diff_3); end if;
            if l_row.diff_4 is null then l_node.put_null('diff4'); else l_node.put('diff4', l_row.diff_4); end if;
            if l_row.original_retail is null then l_node.put_null('originalRetail'); else l_node.put('originalRetail', l_row.original_retail); end if;
            l_items.append(l_node);
        end loop;

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
            l_node := json_object_t();
            l_node.put('item', l_row.item);
            l_node.put('supplier', l_row.supplier);
            l_node.put('supplierName', l_row.sup_name);
            l_node.put('primarySupplier', l_row.primary_supp_ind);
            if l_row.vpn is null then l_node.put_null('vpn'); else l_node.put('vpn', l_row.vpn); end if;
            if l_row.origin_country_id is null then l_node.put_null('originCountry'); else l_node.put('originCountry', l_row.origin_country_id); end if;
            if l_row.primary_country_ind is null then l_node.put_null('primaryCountry'); else l_node.put('primaryCountry', l_row.primary_country_ind); end if;
            if l_row.unit_cost is null then l_node.put_null('unitCost'); else l_node.put('unitCost', l_row.unit_cost); end if;
            if l_row.currency_code is null then l_node.put_null('currencyCode'); else l_node.put('currencyCode', l_row.currency_code); end if;
            if l_row.lead_time is null then l_node.put_null('leadTime'); else l_node.put('leadTime', l_row.lead_time); end if;
            if l_row.pickup_lead_time is null then l_node.put_null('pickupLeadTime'); else l_node.put('pickupLeadTime', l_row.pickup_lead_time); end if;
            if l_row.default_uop is null then l_node.put_null('defaultUop'); else l_node.put('defaultUop', l_row.default_uop); end if;
            if l_row.supp_pack_size is null then l_node.put_null('supplierPackSize'); else l_node.put('supplierPackSize', l_row.supp_pack_size); end if;
            l_sourcing.append(l_node);
        end loop;

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
            l_node := json_object_t();
            l_node.put('item', l_row.item);
            l_node.put('location', l_row.location);
            l_node.put('locationType', l_row.loc_type);
            if l_row.location_name is null then l_node.put_null('locationName'); else l_node.put('locationName', l_row.location_name); end if;
            l_node.put('status', l_row.status);
            if l_row.primary_supp is null then l_node.put_null('primarySupplier'); else l_node.put('primarySupplier', l_row.primary_supp); end if;
            l_node.put('sourceMethod', l_row.source_method);
            if l_row.unit_retail is null then l_node.put_null('unitRetail'); else l_node.put('unitRetail', l_row.unit_retail); end if;
            l_locations.append(l_node);
        end loop;

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
            l_node := json_object_t();
            l_node.put('item', l_row.item);
            l_node.put('udaId', l_row.uda_id);
            l_node.put('value', l_row.uda_value);
            l_udas.append(l_node);
        end loop;

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
            l_order := json_object_t();
            l_lines := json_array_t();
            l_order.put('orderNo', l_order_row.order_no);
            l_order.put('orderType', l_order_row.order_type);
            l_order.put('supplier', l_order_row.supplier);
            l_order.put('department', l_order_row.dept);
            l_order.put('status', l_order_row.status);
            l_order.put('currencyCode', l_order_row.currency_code);
            l_order.put('exchangeRate', l_order_row.exchange_rate);
            if l_order_row.not_before_date is null then l_order.put_null('notBeforeDate'); else l_order.put('notBeforeDate', to_char(l_order_row.not_before_date, 'YYYY-MM-DD')); end if;
            if l_order_row.not_after_date is null then l_order.put_null('notAfterDate'); else l_order.put('notAfterDate', to_char(l_order_row.not_after_date, 'YYYY-MM-DD')); end if;
            if l_order_row.earliest_ship_date is null then l_order.put_null('earliestShipDate'); else l_order.put('earliestShipDate', to_char(l_order_row.earliest_ship_date, 'YYYY-MM-DD')); end if;
            if l_order_row.latest_ship_date is null then l_order.put_null('latestShipDate'); else l_order.put('latestShipDate', to_char(l_order_row.latest_ship_date, 'YYYY-MM-DD')); end if;
            l_order.put('totalQuantity', l_order_row.total_qty_ordered);
            l_order.put('totalCost', l_order_row.total_cost);
            l_order.put('sourceSystem', l_order_row.source_system);
            if l_order_row.approved_by is null then l_order.put_null('approvedBy'); else l_order.put('approvedBy', l_order_row.approved_by); end if;
            if l_order_row.approved_at is null then l_order.put_null('approvedAt'); else l_order.put('approvedAt', to_char(l_order_row.approved_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM')); end if;

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
                l_node := json_object_t();
                l_node.put('item', l_line_row.item);
                l_node.put('description', l_line_row.item_desc);
                if l_line_row.diff_1 is null then l_node.put_null('diff1'); else l_node.put('diff1', l_line_row.diff_1); end if;
                if l_line_row.diff_2 is null then l_node.put_null('diff2'); else l_node.put('diff2', l_line_row.diff_2); end if;
                if l_line_row.diff_3 is null then l_node.put_null('diff3'); else l_node.put('diff3', l_line_row.diff_3); end if;
                l_node.put('location', l_line_row.location);
                l_node.put('locationType', l_line_row.loc_type);
                l_node.put('originCountry', l_line_row.origin_country_id);
                l_node.put('quantityOrdered', l_line_row.qty_ordered);
                l_node.put('quantityReceived', l_line_row.qty_received);
                l_node.put('quantityCancelled', l_line_row.qty_cancelled);
                l_node.put('unitCost', l_line_row.unit_cost);
                if l_line_row.unit_retail is null then l_node.put_null('unitRetail'); else l_node.put('unitRetail', l_line_row.unit_retail); end if;
                if l_line_row.earliest_ship_date is null then l_node.put_null('earliestShipDate'); else l_node.put('earliestShipDate', to_char(l_line_row.earliest_ship_date, 'YYYY-MM-DD')); end if;
                if l_line_row.latest_ship_date is null then l_node.put_null('latestShipDate'); else l_node.put('latestShipDate', to_char(l_line_row.latest_ship_date, 'YYYY-MM-DD')); end if;
                l_lines.append(l_node);
            end loop;
            l_order.put('lines', l_lines);
            l_orders.append(l_order);
        end loop;

        for l_row in (
            select * from (
                select event_id, correlation_id, service_name, http_method, response_code, started_at, completed_at
                  from office_mfcs_app.local_mfcs_rest_event e
                 where dbms_lob.instr(e.request_payload, l_identifier) > 0
                    or dbms_lob.instr(e.response_payload, l_identifier) > 0
                 order by event_id desc
            ) where rownum <= 20
        ) loop
            l_node := json_object_t();
            l_node.put('eventId', l_row.event_id);
            l_node.put('correlationId', l_row.correlation_id);
            l_node.put('serviceName', l_row.service_name);
            l_node.put('httpMethod', l_row.http_method);
            l_node.put('responseCode', l_row.response_code);
            l_node.put('startedAt', to_char(l_row.started_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            l_node.put('completedAt', to_char(l_row.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            l_events.append(l_node);
        end loop;

        l_root.put('query', l_identifier);
        l_root.put('foundBy', l_found_by);
        l_root.put('styles', l_styles);
        l_root.put('items', l_items);
        l_root.put('sourcing', l_sourcing);
        l_root.put('locations', l_locations);
        l_root.put('udas', l_udas);
        l_root.put('orders', l_orders);
        l_root.put('events', l_events);
        p_http_status := 200;
        p_response := l_root.to_clob;
        office_workflow_log_pkg.info(c_package_name, 'LOOKUP_STATE', null, l_found_by || ' ' || l_identifier || ' returned');
    exception
        when others then
            l_error_message := sqlerrm;
            p_http_status := 500;
            p_response := error_response('MFCS state lookup failed: ' || l_error_message);
            office_workflow_log_pkg.error(c_package_name, 'LOOKUP_STATE', null, 'Lookup failed for ' || l_identifier, l_error_message);
    end lookup_state;
end office_mfcs_state_pkg;
/

show errors

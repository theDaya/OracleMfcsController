set define off

prompt Creating OFFICE MFCS public-contract mapper package

create or replace package office_mfcs_public_contract_pkg authid definer as
    function build_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob;
end office_mfcs_public_contract_pkg;
/

create or replace package body office_mfcs_public_contract_pkg as
    function payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_payload;
    end;

    function string_value(p_payload in clob, p_name in varchar2) return varchar2 is
    begin
        return json_object_t.parse(p_payload).get_string(p_name);
    end;

    function number_value(p_payload in clob, p_name in varchar2) return number is
    begin
        return json_object_t.parse(p_payload).get_number(p_name);
    end;

    function request_style(p_action_request_id in varchar2) return varchar2 is
        l_style varchar2(30);
    begin
        select style_no into l_style
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_style;
    end;

    function request_order(p_action_request_id in varchar2) return varchar2 is
        l_order varchar2(30);
    begin
        select order_no into l_order
          from office_mfcs_request
         where action_request_id = p_action_request_id;
        return l_order;
    end;

    function resolved_sku(
        p_payload            in clob,
        p_source_variant_ref in varchar2,
        p_payload_sku        in varchar2
    ) return varchar2 is
        l_sku varchar2(30) := p_payload_sku;
        l_source_system varchar2(60);
        l_source_style_ref varchar2(120);
    begin
        if l_sku is not null then
            return l_sku;
        end if;

        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60)),
               json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120))
          into l_source_system, l_source_style_ref
          from dual;

        select max(mfcs_sku_no)
          into l_sku
          from office_mfcs_entity_map
         where source_system = l_source_system
           and source_style_ref = l_source_style_ref
           and source_variant_ref = p_source_variant_ref;
        return l_sku;
    end;

    function item_number_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_count number;
    begin
        select count(*) + 1
          into l_count
          from json_table(l_payload, '$.PLMSizeCurveDtl[*]' columns x path '$');
        l_root.put('itemNumberType', 'ITEM');
        l_root.put('quantity', l_count);
        l_root.put('daysUntilExpiry', 14);
        return l_root.to_clob;
    end;

    function item_create_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_operation varchar2(30);
        l_style varchar2(30) := request_style(p_action_request_id);
        l_department number;
        l_class number;
        l_subclass number;
        l_retail number;
        l_source_ref varchar2(120);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.OPERATION_NAME' returning varchar2(30)),
               json_value(l_payload, '$.DEPARTMENT' returning number),
               json_value(l_payload, '$.CLASS' returning number),
               json_value(l_payload, '$.SUBCLASS' returning number),
               json_value(l_payload, '$.RETAIL_PRICE' returning number),
               json_value(l_payload, '$.SOURCE_STYLE_REF' returning varchar2(120))
          into l_operation, l_department, l_class, l_subclass, l_retail, l_source_ref
          from dual;

        l_item := json_object_t();
        l_item.put('item', l_style);
        l_item.put('itemDescription', substr(l_source_ref, 1, 250));
        l_item.put('dataLoadingDestination', 'RMS');
        if l_operation <> 'MODIFY_STYLE' then
            l_item.put('itemNumberType', 'ITEM');
            l_item.put('itemLevel', 1);
            l_item.put('tranLevel', 2);
            l_item.put('dept', l_department);
            l_item.put('class', l_class);
            l_item.put('subclass', l_subclass);
            l_item.put('status', 'W');
            l_item.put('approveInd', 'N');
            l_item.put('standardUom', 'EA');
            l_item.put('merchandiseInd', 'Y');
            l_item.put('inventoryInd', 'Y');
            l_item.put('sellableInd', 'Y');
            l_item.put('orderableInd', 'Y');
            l_item.put('originalRetail', l_retail);
        end if;
        l_items.append(l_item);

        for v in (
            select source_variant_ref, sku_size, sku_width, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_size varchar2(60) path '$.SKU_SIZE',
                      sku_width varchar2(60) path '$.SKU_WIDTH',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('itemDescription', substr(l_source_ref || ' ' || v.sku_size || ' ' || v.sku_width, 1, 250));
            l_item.put('dataLoadingDestination', 'RMS');
            if l_operation <> 'MODIFY_STYLE' then
                l_item.put('itemParent', l_style);
                l_item.put('itemNumberType', 'ITEM');
                l_item.put('itemLevel', 2);
                l_item.put('tranLevel', 2);
                l_item.put('dept', l_department);
                l_item.put('class', l_class);
                l_item.put('subclass', l_subclass);
                l_item.put('status', 'W');
                l_item.put('approveInd', 'N');
                l_item.put('standardUom', 'EA');
                l_item.put('merchandiseInd', 'Y');
                l_item.put('inventoryInd', 'Y');
                l_item.put('sellableInd', 'Y');
                l_item.put('orderableInd', 'Y');
                l_item.put('originalRetail', l_retail);
            end if;
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_sourcing_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_supplier_node json_object_t;
        l_country_node json_object_t;
        l_suppliers json_array_t;
        l_countries json_array_t;
        l_supplier number;
        l_cost number;
        l_country varchar2(3);
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.SUPPLIER' returning number),
               json_value(l_payload, '$.UNIT_COST' returning number),
               json_value(l_payload, '$.ORIGIN_COUNTRY' returning varchar2(3))
          into l_supplier, l_cost, l_country
          from dual;

        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_country_node := json_object_t();
            l_country_node.put('originCountry', l_country);
            l_country_node.put('primaryCountryInd', 'Y');
            l_country_node.put('unitCost', l_cost);
            l_countries := json_array_t();
            l_countries.append(l_country_node);

            l_supplier_node := json_object_t();
            l_supplier_node.put('supplier', l_supplier);
            l_supplier_node.put('primarySupplierInd', 'Y');
            l_supplier_node.put('countryOfSourcing', l_countries);
            l_suppliers := json_array_t();
            l_suppliers.append(l_supplier_node);

            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('supplier', l_suppliers);
            l_items.append(l_item);
        end loop;

        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_uda_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('uda', json_array_t());
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_location_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_location json_object_t;
        l_locations json_array_t;
        l_delivery number;
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.DELIVERY_LOC' returning number)
          into l_delivery from dual;
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_location := json_object_t();
            l_location.put('location', l_delivery);
            l_location.put('locationType', 'S');
            l_location.put('status', 'A');
            l_locations := json_array_t();
            l_locations.append(l_location);

            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('dataLoadingDestination', 'RMS');
            l_item.put('locations', l_locations);
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function item_approval_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_sku varchar2(30);
    begin
        l_item := json_object_t();
        l_item.put('item', request_style(p_action_request_id));
        l_item.put('status', 'A');
        l_item.put('approveInd', 'Y');
        l_item.put('dataLoadingDestination', 'RMS');
        l_items.append(l_item);
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID'
              )
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('status', 'A');
            l_item.put('approveInd', 'Y');
            l_item.put('dataLoadingDestination', 'RMS');
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function initial_retail_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_item json_object_t;
        l_retail number;
        l_sku varchar2(30);
    begin
        select json_value(l_payload, '$.RETAIL_PRICE' returning number) into l_retail from dual;
        for v in (
            select source_variant_ref, sku_id
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF', sku_id varchar2(30) path '$.SKU_ID')
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_item := json_object_t();
            l_item.put('item', l_sku);
            l_item.put('originalRetail', l_retail);
            l_item.put('dataLoadingDestination', 'RMS');
            l_items.append(l_item);
        end loop;
        l_root.put('collectionSize', l_items.get_size);
        l_root.put('items', l_items);
        return l_root.to_clob;
    end;

    function po_number_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
    begin
        l_root.put('supplier', number_value(l_payload, 'SUPPLIER'));
        l_root.put('quantity', 1);
        l_root.put('expiryDays', 14);
        return l_root.to_clob;
    end;

    function purchase_order_request(p_action_request_id in varchar2) return clob is
        l_payload clob := payload(p_action_request_id);
        l_root json_object_t := json_object_t();
        l_orders json_array_t := json_array_t();
        l_order json_object_t := json_object_t();
        l_details json_array_t := json_array_t();
        l_detail json_object_t;
        l_sku varchar2(30);
        l_operation varchar2(30);
    begin
        select json_value(l_payload, '$.OPERATION_NAME' returning varchar2(30)) into l_operation from dual;
        l_order.put('orderNo', to_number(request_order(p_action_request_id)));
        l_order.put('supplier', number_value(l_payload, 'SUPPLIER'));
        l_order.put('currencyCode', string_value(l_payload, 'CURRENCY_CODE'));
        l_order.put('notBeforeDate', string_value(l_payload, 'NOT_BEFORE_DATE'));
        l_order.put('notAfterDate', string_value(l_payload, 'NOT_AFTER_DATE'));
        l_order.put('earliestShipDate', string_value(l_payload, 'EARLIEST_SHIP_DATE'));
        l_order.put('latestShipDate', string_value(l_payload, 'LATEST_SHIP_DATE'));
        l_order.put('dept', number_value(l_payload, 'DEPARTMENT'));
        l_order.put('status', 'A');
        l_order.put('exchangeRate', number_value(l_payload, 'ORDER_EXCHANGE_RATE'));
        l_order.put('approvedBy', office_mfcs_mapping_pkg.user_id(l_payload));
        l_order.put('dataLoadingDestination', 'RMS');

        for v in (
            select source_variant_ref, sku_id, sku_qty
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_id varchar2(30) path '$.SKU_ID',
                      sku_qty number path '$.SKU_QTY')
        ) loop
            l_sku := resolved_sku(l_payload, v.source_variant_ref, v.sku_id);
            l_detail := json_object_t();
            l_detail.put('item', l_sku);
            l_detail.put('location', number_value(l_payload, 'DELIVERY_LOC'));
            l_detail.put('locationType', 'S');
            l_detail.put('qtyOrdered', v.sku_qty);
            l_detail.put('unitCost', number_value(l_payload, 'UNIT_COST'));
            l_detail.put('originCountryId', string_value(l_payload, 'ORIGIN_COUNTRY'));
            l_details.append(l_detail);
        end loop;
        l_order.put('details', l_details);
        l_orders.append(l_order);
        l_root.put('items', l_orders);
        return l_root.to_clob;
    end;

    function build_request(
        p_action_request_id in varchar2,
        p_mapper_name       in varchar2
    ) return clob is
    begin
        case p_mapper_name
            when 'build_item_number_request' then return item_number_request(p_action_request_id);
            when 'build_item_create_request' then return item_create_request(p_action_request_id);
            when 'build_item_sourcing_request' then return item_sourcing_request(p_action_request_id);
            when 'build_item_uda_request' then return item_uda_request(p_action_request_id);
            when 'build_item_location_request' then return item_location_request(p_action_request_id);
            when 'build_item_approval_request' then return item_approval_request(p_action_request_id);
            when 'build_initial_retail_request' then return initial_retail_request(p_action_request_id);
            when 'build_po_number_request' then return po_number_request(p_action_request_id);
            when 'build_purchase_order_request' then return purchase_order_request(p_action_request_id);
            when 'build_purchase_order_verify_request' then return '{}';
            else raise_application_error(-20820, 'Unsupported public mapper: ' || p_mapper_name);
        end case;
    end;
end office_mfcs_public_contract_pkg;
/

show errors

prompt OFFICE MFCS public-contract mapper package created

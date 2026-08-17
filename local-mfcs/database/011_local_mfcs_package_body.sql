set define off

prompt Creating Local MFCS service package body

create or replace package body local_mfcs_service_pkg as
    -- Shared validation and response helpers.
    e_validation exception;
    pragma exception_init(e_validation, -20001);

    procedure fail(p_field in varchar2, p_message in varchar2) is
    begin
        raise_application_error(-20001, p_field || '|' || p_message);
    end;

    procedure assert_true(p_condition in boolean, p_field in varchar2, p_message in varchar2) is
    begin
        if not p_condition then
            fail(p_field, p_message);
        end if;
    end;

    function correlation_id(p_value in varchar2) return varchar2 is
    begin
        return coalesce(p_value, lower(rawtohex(sys_guid())));
    end;

    function iso_date(p_value in varchar2) return date is
    begin
        if p_value is null then
            return null;
        end if;
        return to_date(substr(p_value, 1, 10), 'YYYY-MM-DD');
    exception
        when others then
            fail('date', 'must use YYYY-MM-DD format');
            return null;
    end;

    function success_response return clob is
    begin
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.write('status', 'SUCCESS');
        apex_json.close_object;
        return office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    function error_response(p_field in varchar2, p_message in varchar2) return clob is
        l_null varchar2(1);
    begin
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.write('status', 'ERROR');
        apex_json.write('message', 'Error found in validation of input payload');
        apex_json.open_array('validationErrors');
        apex_json.open_object;
        apex_json.write('error', p_message);
        apex_json.write('field', p_field);
        apex_json.write('inputValue', l_null, true);
        apex_json.close_object;
        apex_json.close_array;
        apex_json.close_object;
        return office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    procedure validate_collection(p_payload in clob) is
        l_declared number;
        l_actual number;
    begin
        assert_true(p_payload is not null and p_payload is json, 'body', 'must be valid JSON');
        select json_value(p_payload, '$.collectionSize' returning number null on error),
               (select count(*) from json_table(p_payload, '$.items[*]' columns x path '$'))
          into l_declared, l_actual
          from dual;
        assert_true(l_actual > 0, 'items', 'must contain at least one item');
        if l_declared is not null then
            assert_true(l_declared = l_actual, 'collectionSize', 'must match items length');
        end if;
    end;

    procedure validate_diff(p_diff in varchar2, p_type in varchar2, p_field in varchar2) is
        l_count number;
    begin
        if p_diff is null then
            return;
        end if;
        select count(*)
          into l_count
          from (
              select diff_id value_id, diff_type from diff_ids
              union all
              select diff_group_id, diff_type from diff_group_head
          )
         where value_id = p_diff
           and (p_type is null or diff_type = p_type);
        assert_true(l_count > 0, p_field, 'must reference DIFF_IDS or DIFF_GROUP_HEAD for the supplied type');
    end;

    -- Item domain: number reservation, hierarchy, sourcing, locations, and UDAs.
    procedure reserve_item_numbers(
        p_payload in clob,
        p_corr in varchar2,
        p_response out clob
    ) is
        l_quantity number;
        l_days number;
        l_type varchar2(10);
        l_item varchar2(25);
        l_expiry timestamp with time zone;
    begin
        assert_true(p_payload is json, 'body', 'must be valid JSON');
        select json_value(p_payload, '$.quantity' returning number),
               coalesce(json_value(p_payload, '$.daysUntilExpiry' returning number null on error), 14),
               coalesce(json_value(p_payload, '$.itemNumberType' returning varchar2(10) null on error), 'ITEM')
          into l_quantity, l_days, l_type
          from dual;
        assert_true(l_quantity between 1 and 1000 and l_quantity = trunc(l_quantity), 'quantity', 'must be a whole number from 1 to 1000');
        assert_true(l_days between 1 and 90, 'daysUntilExpiry', 'must be from 1 to 90');

        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.open_array('items');
        for i in 1 .. l_quantity loop
            l_item := to_char(local_mfcs_item_seq.nextval);
            l_expiry := systimestamp + numtodsinterval(l_days, 'DAY');
            insert into item_number_reservation(
                item, item_number_type, expiry_date, correlation_id
            ) values (
                l_item, l_type, l_expiry, p_corr
            );
            apex_json.open_object;
            apex_json.write('item', l_item);
            apex_json.write('itemNumberType', l_type);
            apex_json.write('expiryDate', to_char(l_expiry, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.close_object;
        end loop;
        apex_json.close_array;
        apex_json.close_object;
        p_response := office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    procedure upsert_items(p_payload in clob, p_update in boolean, p_response out clob) is
        l_count number;
        l_parent_diff_1 item_master.diff_1%type;
        l_parent_diff_2 item_master.diff_2%type;
        l_parent_diff_3 item_master.diff_3%type;
        l_parent_diff_4 item_master.diff_4%type;

        procedure validate_group_member(
            p_group in varchar2,
            p_diff  in varchar2,
            p_field in varchar2
        ) is
            l_group_count number;
            l_member_count number;
        begin
            if p_group is null or p_diff is null then
                return;
            end if;
            select count(*) into l_group_count
              from diff_group_head
             where diff_group_id = p_group;
            if l_group_count = 0 then
                return;
            end if;
            select count(*) into l_member_count
              from diff_group_detail
             where diff_group_id = p_group
               and diff_id = p_diff;
            assert_true(l_member_count = 1, p_field, 'must belong to parent diff group ' || p_group);
        end;
    begin
        validate_collection(p_payload);
        for l_row in (
            select item,
                   item_number_type,
                   item_parent,
                   item_grandparent,
                   item_level,
                   tran_level,
                   item_desc,
                   dept,
                   class_no,
                   subclass_no,
                   status,
                   approve_ind,
                   standard_uom,
                   merchandise_ind,
                   inventory_ind,
                   sellable_ind,
                   orderable_ind,
                   diff_1,
                   diff_1_type,
                   diff_2,
                   diff_2_type,
                   diff_3,
                   diff_3_type,
                   diff_4,
                   diff_4_type,
                   original_retail,
                   data_destination
              from json_table(p_payload, '$.items[*]'
                  columns
                      item varchar2(25) path '$.item',
                      item_number_type varchar2(10) path '$.itemNumberType',
                      item_parent varchar2(25) path '$.itemParent',
                      item_grandparent varchar2(25) path '$.itemGrandparent',
                      item_level number path '$.itemLevel',
                      tran_level number path '$.tranLevel',
                      item_desc varchar2(250) path '$.itemDescription',
                      dept number path '$.dept',
                      class_no number path '$.class',
                      subclass_no number path '$.subclass',
                      status varchar2(1) path '$.status',
                      approve_ind varchar2(1) path '$.approveInd',
                      standard_uom varchar2(4) path '$.standardUom',
                      merchandise_ind varchar2(1) path '$.merchandiseInd',
                      inventory_ind varchar2(1) path '$.inventoryInd',
                      sellable_ind varchar2(1) path '$.sellableInd',
                      orderable_ind varchar2(1) path '$.orderableInd',
                      diff_1 varchar2(100) path '$.diff1',
                      diff_1_type varchar2(30) path '$.diff1Type',
                      diff_2 varchar2(100) path '$.diff2',
                      diff_2_type varchar2(30) path '$.diff2Type',
                      diff_3 varchar2(100) path '$.diff3',
                      diff_3_type varchar2(30) path '$.diff3Type',
                      diff_4 varchar2(100) path '$.diff4',
                      diff_4_type varchar2(30) path '$.diff4Type',
                      original_retail number path '$.originalRetail',
                      data_destination varchar2(6) path '$.dataLoadingDestination'
              )
        ) loop
            assert_true(l_row.item is not null, 'items.item', 'is required');
            assert_true(l_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS for direct Local MFCS creation');
            validate_diff(l_row.diff_1, l_row.diff_1_type, 'items.diff1');
            validate_diff(l_row.diff_2, l_row.diff_2_type, 'items.diff2');
            validate_diff(l_row.diff_3, l_row.diff_3_type, 'items.diff3');
            validate_diff(l_row.diff_4, l_row.diff_4_type, 'items.diff4');

            if p_update then
                update item_master
                   set item_desc = coalesce(l_row.item_desc, item_desc),
                       short_desc = coalesce(substr(l_row.item_desc, 1, 120), short_desc),
                       status = coalesce(l_row.status, status),
                       approve_ind = coalesce(l_row.approve_ind, approve_ind),
                       original_retail = coalesce(l_row.original_retail, original_retail),
                       diff_1 = coalesce(l_row.diff_1, diff_1),
                       diff_1_type = coalesce(l_row.diff_1_type, diff_1_type),
                       diff_2 = coalesce(l_row.diff_2, diff_2),
                       diff_2_type = coalesce(l_row.diff_2_type, diff_2_type),
                       diff_3 = coalesce(l_row.diff_3, diff_3),
                       diff_3_type = coalesce(l_row.diff_3_type, diff_3_type),
                       diff_4 = coalesce(l_row.diff_4, diff_4),
                       diff_4_type = coalesce(l_row.diff_4_type, diff_4_type),
                       approved_by = case when coalesce(l_row.status, status) = 'A' then coalesce(approved_by, 'LOCAL_MFCS_REST') else approved_by end,
                       approved_at = case when coalesce(l_row.status, status) = 'A' then coalesce(approved_at, systimestamp) else approved_at end,
                       updated_at = systimestamp
                 where item = l_row.item;
                assert_true(sql%rowcount = 1, 'items.item', 'does not exist for update: ' || l_row.item);
            else
                assert_true(l_row.item_level is not null and l_row.tran_level is not null, 'items.itemLevel', 'itemLevel and tranLevel are required for create');
                assert_true(l_row.dept is not null and l_row.class_no is not null and l_row.subclass_no is not null, 'items.dept', 'dept, class and subclass are required for create');
                if l_row.item_parent is not null then
                    begin
                        select diff_1, diff_2, diff_3, diff_4
                          into l_parent_diff_1, l_parent_diff_2, l_parent_diff_3, l_parent_diff_4
                          from item_master
                         where item = l_row.item_parent;
                    exception when no_data_found then
                        fail('items.itemParent', 'must already exist: ' || l_row.item_parent);
                    end;
                    validate_group_member(l_parent_diff_1, l_row.diff_1, 'items.diff1');
                    validate_group_member(l_parent_diff_2, l_row.diff_2, 'items.diff2');
                    validate_group_member(l_parent_diff_3, l_row.diff_3, 'items.diff3');
                    validate_group_member(l_parent_diff_4, l_row.diff_4, 'items.diff4');
                end if;
                insert into item_master(
                    item, item_number_type, item_parent, item_grandparent, item_level, tran_level,
                    item_desc, short_desc, dept, class, subclass, status, approve_ind, standard_uom,
                    merchandise_ind, inventory_ind, sellable_ind, orderable_ind,
                    diff_1, diff_1_type, diff_2, diff_2_type, diff_3, diff_3_type, diff_4, diff_4_type,
                    original_retail, approved_by, approved_at
                ) values (
                    l_row.item, coalesce(l_row.item_number_type, 'ITEM'), l_row.item_parent, l_row.item_grandparent,
                    l_row.item_level, l_row.tran_level, coalesce(l_row.item_desc, l_row.item), substr(coalesce(l_row.item_desc, l_row.item), 1, 120),
                    l_row.dept, l_row.class_no, l_row.subclass_no, coalesce(l_row.status, 'W'), coalesce(l_row.approve_ind, 'N'),
                    coalesce(l_row.standard_uom, 'EA'), coalesce(l_row.merchandise_ind, 'Y'), coalesce(l_row.inventory_ind, 'Y'),
                    coalesce(l_row.sellable_ind, 'Y'), coalesce(l_row.orderable_ind, 'Y'),
                    l_row.diff_1, l_row.diff_1_type, l_row.diff_2, l_row.diff_2_type, l_row.diff_3, l_row.diff_3_type, l_row.diff_4, l_row.diff_4_type,
                    l_row.original_retail,
                    case when l_row.status = 'A' then 'LOCAL_MFCS_REST' end,
                    case when l_row.status = 'A' then systimestamp end
                );
                update item_number_reservation set consumed_ind = 'Y' where item = l_row.item;
            end if;
        end loop;
        p_response := success_response;
    exception
        when dup_val_on_index then
            fail('items.item', 'already exists or violates a unique item rule');
    end;

    procedure upsert_item_suppliers(p_payload in clob, p_response out clob) is
        l_currency varchar2(3);
        l_count number;
    begin
        validate_collection(p_payload);
        for l_row in (
            select item, supplier_no, primary_supp_ind, origin_country, primary_country_ind, unit_cost, data_destination
              from json_table(p_payload, '$.items[*]'
                  columns
                      item varchar2(25) path '$.item',
                      data_destination varchar2(6) path '$.dataLoadingDestination',
                      nested path '$.supplier[*]' columns (
                          supplier_no number path '$.supplier',
                          primary_supp_ind varchar2(1) path '$.primarySupplierInd',
                          nested path '$.countryOfSourcing[*]' columns (
                              origin_country varchar2(3) path '$.originCountry',
                              primary_country_ind varchar2(1) path '$.primaryCountryInd',
                              unit_cost number path '$.unitCost'
                          )
                      )
              )
        ) loop
            assert_true(l_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = l_row.item;
            assert_true(l_count = 1, 'items.item', 'must exist before sourcing: ' || l_row.item);
            begin
                select currency_code into l_currency from sups where supplier = l_row.supplier_no and status = 'A';
            exception when no_data_found then
                fail('items.supplier', 'supplier is not active: ' || l_row.supplier_no);
            end;
            select count(*) into l_count from country where country_id = l_row.origin_country;
            assert_true(l_count = 1, 'items.originCountry', 'country is not defined: ' || l_row.origin_country);
            assert_true(l_row.unit_cost is not null and l_row.unit_cost >= 0, 'items.unitCost', 'must be zero or greater');

            if coalesce(l_row.primary_supp_ind, 'N') = 'Y' then
                update item_supplier set primary_supp_ind = 'N', updated_at = systimestamp where item = l_row.item;
            end if;
            merge into item_supplier d
            using (select l_row.item item, l_row.supplier_no supplier from dual) s
               on (d.item = s.item and d.supplier = s.supplier)
            when matched then update set d.primary_supp_ind = coalesce(l_row.primary_supp_ind, d.primary_supp_ind), d.updated_at = systimestamp
            when not matched then insert (item, supplier, primary_supp_ind) values (l_row.item, l_row.supplier_no, coalesce(l_row.primary_supp_ind, 'N'));

            if coalesce(l_row.primary_country_ind, 'N') = 'Y' then
                update item_supp_country
                   set primary_country_ind = 'N', updated_at = systimestamp
                 where item = l_row.item and supplier = l_row.supplier_no;
            end if;
            merge into item_supp_country d
            using (select l_row.item item, l_row.supplier_no supplier, l_row.origin_country origin_country_id from dual) s
               on (d.item = s.item and d.supplier = s.supplier and d.origin_country_id = s.origin_country_id)
            when matched then update set
                d.primary_country_ind = coalesce(l_row.primary_country_ind, d.primary_country_ind),
                d.unit_cost = l_row.unit_cost,
                d.currency_code = l_currency,
                d.updated_at = systimestamp
            when not matched then insert (
                item, supplier, origin_country_id, primary_country_ind, unit_cost, currency_code
            ) values (
                l_row.item, l_row.supplier_no, l_row.origin_country, coalesce(l_row.primary_country_ind, 'N'), l_row.unit_cost, l_currency
            );
        end loop;
        p_response := success_response;
    end;

    procedure upsert_item_locations(p_payload in clob, p_response out clob) is
        l_count number;
        l_primary_supplier number;
        l_retail number;
    begin
        validate_collection(p_payload);
        for l_row in (
            select item, location, loc_type, location_status, data_destination
              from json_table(p_payload, '$.items[*]'
                  columns
                      item varchar2(25) path '$.item',
                      data_destination varchar2(6) path '$.dataLoadingDestination',
                      nested path '$.locations[*]' columns (
                          location number path '$.location',
                          loc_type varchar2(1) path '$.locationType',
                          location_status varchar2(1) path '$.status'
                      )
              )
        ) loop
            assert_true(l_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = l_row.item;
            assert_true(l_count = 1, 'items.item', 'must exist before location ranging: ' || l_row.item);
            if l_row.loc_type = 'S' then
                select count(*) into l_count from store where store = l_row.location and status = 'A' and stockholding_ind = 'Y';
            elsif l_row.loc_type = 'W' then
                select count(*) into l_count from wh where wh = l_row.location and status = 'A' and stockholding_ind = 'Y';
            else
                l_count := 0;
            end if;
            assert_true(l_count = 1, 'items.locations.location', 'must be an active stockholding location');
            begin
                select supplier into l_primary_supplier
                  from item_supplier
                 where item = l_row.item and primary_supp_ind = 'Y';
            exception when no_data_found then
                l_primary_supplier := null;
            end;
            select original_retail into l_retail from item_master where item = l_row.item;
            merge into item_loc d
            using (select l_row.item item, l_row.location location, l_row.loc_type loc_type from dual) s
               on (d.item = s.item and d.location = s.location and d.loc_type = s.loc_type)
            when matched then update set d.status = coalesce(l_row.location_status, d.status), d.primary_supp = coalesce(l_primary_supplier, d.primary_supp), d.unit_retail = coalesce(l_retail, d.unit_retail), d.updated_at = systimestamp
            when not matched then insert (item, location, loc_type, status, primary_supp, unit_retail)
                values (l_row.item, l_row.location, l_row.loc_type, coalesce(l_row.location_status, 'A'), l_primary_supplier, l_retail);
        end loop;
        p_response := success_response;
    end;

    procedure upsert_item_udas(p_payload in clob, p_response out clob) is
        l_count number;
    begin
        validate_collection(p_payload);
        for l_item_row in (
            select item, uda_json, data_destination
              from json_table(p_payload, '$.items[*]'
                  columns
                      item varchar2(25) path '$.item',
                      data_destination varchar2(6) path '$.dataLoadingDestination',
                      uda_json clob format json path '$.uda'
              )
        ) loop
            assert_true(l_item_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = l_item_row.item;
            assert_true(l_count = 1, 'items.item', 'must exist before UDA assignment: ' || l_item_row.item);
            for l_uda_row in (
                select uda_id, uda_value
                  from json_table(l_item_row.uda_json, '$[*]'
                      columns uda_id number path '$.udaId', uda_value varchar2(250) path '$.udaValue')
            ) loop
                assert_true(l_uda_row.uda_id is not null and l_uda_row.uda_value is not null, 'items.uda', 'udaId and udaValue are required');
                merge into item_uda d
                using (select l_item_row.item item, l_uda_row.uda_id uda_id from dual) s
                   on (d.item = s.item and d.uda_id = s.uda_id)
                when matched then update set d.uda_value = l_uda_row.uda_value, d.updated_at = systimestamp
                when not matched then insert (item, uda_id, uda_value) values (l_item_row.item, l_uda_row.uda_id, l_uda_row.uda_value);
            end loop;
        end loop;
        p_response := success_response;
    end;

    -- Order domain: number reservation, purchase-order persistence, and lookup.
    procedure reserve_order_numbers(p_payload in clob, p_corr in varchar2, p_response out clob) is
        l_supplier number;
        l_quantity number;
        l_days number;
        l_order_no number;
        l_expiry timestamp with time zone;
        l_count number;
        l_null_supplier number;
    begin
        assert_true(p_payload is json, 'body', 'must be valid JSON');
        select json_value(p_payload, '$.supplier' returning number null on error),
               coalesce(json_value(p_payload, '$.quantity' returning number null on error), 1),
               coalesce(json_value(p_payload, '$.expiryDays' returning number null on error), 14)
          into l_supplier, l_quantity, l_days from dual;
        if l_supplier is not null then
            select count(*) into l_count from sups where supplier = l_supplier and status = 'A';
            assert_true(l_count = 1, 'supplier', 'must identify an active supplier');
        end if;
        assert_true(l_quantity between 1 and 100 and l_quantity = trunc(l_quantity), 'quantity', 'must be a whole number from 1 to 100');
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.open_array('orderNumbers');
        for i in 1 .. l_quantity loop
            l_order_no := local_mfcs_order_seq.nextval;
            l_expiry := systimestamp + numtodsinterval(l_days, 'DAY');
            insert into order_number_reservation(order_no, supplier, expiry_date, correlation_id)
            values (l_order_no, l_supplier, l_expiry, p_corr);
            l_null_supplier := l_supplier;
            apex_json.open_object;
            apex_json.write('supplier', l_null_supplier, true);
            apex_json.write('orderNo', l_order_no);
            apex_json.write('expiryDate', to_char(l_expiry, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.close_object;
        end loop;
        apex_json.close_array;
        apex_json.close_object;
        p_response := office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    procedure upsert_purchase_orders(p_payload in clob, p_update in boolean, p_response out clob) is
        l_count number;
        l_detail_count number;
        l_header_exists number;
        l_item_status char(1);
        l_item_retail number;
        l_details clob;
        l_not_before_date date;
        l_not_after_date date;
        l_earliest_ship_date date;
        l_latest_ship_date date;
    begin
        assert_true(p_payload is not null and p_payload is json, 'body', 'must be valid JSON');
        select count(*) into l_count from json_table(p_payload, '$.items[*]' columns x path '$');
        assert_true(l_count > 0, 'items', 'must contain at least one purchase order');

        for l_order_row in (
            select order_no, supplier_no, currency_code, not_before_date, not_after_date,
                   earliest_ship_date, latest_ship_date, dept, order_status, exchange_rate,
                   approved_by, data_destination, details
              from json_table(p_payload, '$.items[*]'
                  columns
                      order_no number path '$.orderNo',
                      supplier_no number path '$.supplier',
                      currency_code varchar2(3) path '$.currencyCode',
                      not_before_date varchar2(30) path '$.notBeforeDate',
                      not_after_date varchar2(30) path '$.notAfterDate',
                      earliest_ship_date varchar2(30) path '$.earliestShipDate',
                      latest_ship_date varchar2(30) path '$.latestShipDate',
                      dept number path '$.dept',
                      order_status varchar2(1) path '$.status',
                      exchange_rate number path '$.exchangeRate',
                      approved_by varchar2(120) path '$.approvedBy',
                      data_destination varchar2(6) path '$.dataLoadingDestination',
                      details clob format json path '$.details'
              )
        ) loop
            assert_true(l_order_row.order_no is not null, 'items.orderNo', 'is required');
            assert_true(l_order_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from sups where supplier = l_order_row.supplier_no and status = 'A';
            assert_true(l_count = 1, 'items.supplier', 'must identify an active supplier');
            select count(*) into l_count from deps where dept = l_order_row.dept;
            assert_true(l_count = 1, 'items.dept', 'must identify an existing department');
            select count(*) into l_header_exists from ordhead where order_no = l_order_row.order_no;
            l_not_before_date := iso_date(l_order_row.not_before_date);
            l_not_after_date := iso_date(l_order_row.not_after_date);
            l_earliest_ship_date := iso_date(l_order_row.earliest_ship_date);
            l_latest_ship_date := iso_date(l_order_row.latest_ship_date);

            if p_update then
                assert_true(l_header_exists = 1, 'items.orderNo', 'does not exist for update');
                update ordhead
                   set supplier = coalesce(l_order_row.supplier_no, supplier),
                       dept = coalesce(l_order_row.dept, dept),
                       status = coalesce(l_order_row.order_status, status),
                       currency_code = coalesce(l_order_row.currency_code, currency_code),
                       exchange_rate = coalesce(l_order_row.exchange_rate, exchange_rate),
                       not_before_date = coalesce(l_not_before_date, not_before_date),
                       not_after_date = coalesce(l_not_after_date, not_after_date),
                       earliest_ship_date = coalesce(l_earliest_ship_date, earliest_ship_date),
                       latest_ship_date = coalesce(l_latest_ship_date, latest_ship_date),
                       approved_by = coalesce(l_order_row.approved_by, approved_by),
                       approved_at = case when coalesce(l_order_row.order_status, status) = 'A' then coalesce(approved_at, systimestamp) else approved_at end,
                       updated_at = systimestamp
                 where order_no = l_order_row.order_no;
                delete from ordloc where order_no = l_order_row.order_no;
                delete from ordsku where order_no = l_order_row.order_no;
            else
                assert_true(l_header_exists = 0, 'items.orderNo', 'already exists');
                insert into ordhead(
                    order_no, supplier, dept, status, currency_code, exchange_rate,
                    not_before_date, not_after_date, earliest_ship_date, latest_ship_date,
                    approved_by, approved_at
                ) values (
                    l_order_row.order_no, l_order_row.supplier_no, l_order_row.dept, coalesce(l_order_row.order_status, 'W'), l_order_row.currency_code,
                    coalesce(l_order_row.exchange_rate, 1), l_not_before_date, l_not_after_date,
                    l_earliest_ship_date, l_latest_ship_date, l_order_row.approved_by,
                    case when l_order_row.order_status = 'A' then systimestamp end
                );
                update order_number_reservation set consumed_ind = 'Y' where order_no = l_order_row.order_no;
            end if;

            l_details := l_order_row.details;
            select count(*) into l_detail_count from json_table(l_details, '$[*]' columns x path '$');
            assert_true(l_detail_count > 0, 'items.details', 'must contain at least one item/location detail');
            for l_line_row in (
                select item, location, loc_type, qty_ordered, unit_cost, origin_country_id
                  from json_table(l_details, '$[*]'
                      columns
                          item varchar2(25) path '$.item',
                          location number path '$.location',
                          loc_type varchar2(1) path '$.locationType',
                          qty_ordered number path '$.qtyOrdered',
                          unit_cost number path '$.unitCost',
                          origin_country_id varchar2(3) path '$.originCountryId'
                  )
            ) loop
                begin
                    select status, original_retail into l_item_status, l_item_retail from item_master where item = l_line_row.item;
                exception when no_data_found then
                    fail('items.details.item', 'does not exist: ' || l_line_row.item);
                end;
                assert_true(l_item_status = 'A', 'items.details.item', 'must be approved before ordering: ' || l_line_row.item);
                select count(*) into l_count
                  from item_supp_country
                 where item = l_line_row.item
                   and supplier = l_order_row.supplier_no
                   and origin_country_id = l_line_row.origin_country_id;
                assert_true(l_count = 1, 'items.details.originCountryId', 'item must be sourced from the order supplier and country');
                select count(*) into l_count
                  from item_loc
                 where item = l_line_row.item
                   and location = l_line_row.location
                   and loc_type = l_line_row.loc_type
                   and status = 'A';
                assert_true(l_count = 1, 'items.details.location', 'item must be active at the order location');
                assert_true(l_line_row.qty_ordered > 0 and l_line_row.qty_ordered = trunc(l_line_row.qty_ordered), 'items.details.qtyOrdered', 'must be a positive whole number');
                assert_true(l_line_row.unit_cost >= 0, 'items.details.unitCost', 'must be zero or greater');

                merge into ordsku target
                using (select l_order_row.order_no order_no, l_line_row.item item from dual) source
                   on (target.order_no = source.order_no and target.item = source.item)
                when matched then update set
                    target.qty_ordered = target.qty_ordered + l_line_row.qty_ordered,
                    target.unit_cost = l_line_row.unit_cost,
                    target.origin_country_id = l_line_row.origin_country_id
                when not matched then insert (
                    order_no, item, origin_country_id, unit_cost, qty_ordered
                ) values (
                    l_order_row.order_no, l_line_row.item, l_line_row.origin_country_id, l_line_row.unit_cost, l_line_row.qty_ordered
                );

                insert into ordloc(
                    order_no, item, location, loc_type, origin_country_id,
                    qty_ordered, unit_cost, unit_retail, earliest_ship_date, latest_ship_date
                ) values (
                    l_order_row.order_no, l_line_row.item, l_line_row.location, l_line_row.loc_type, l_line_row.origin_country_id,
                    l_line_row.qty_ordered, l_line_row.unit_cost, l_item_retail, l_earliest_ship_date, l_latest_ship_date
                );
            end loop;

            update ordhead oh
               set (total_qty_ordered, total_cost, updated_at) = (
                   select sum(qty_ordered), sum(qty_ordered * unit_cost), systimestamp
                     from ordloc ol
                    where ol.order_no = oh.order_no
               )
             where order_no = l_order_row.order_no;
        end loop;
        p_response := success_response;
    end;

    procedure get_purchase_order(p_order_no in varchar2, p_response out clob) is
        l_found_count number := 0;
    begin
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.open_array('items');
        for l_order_row in (select * from ordhead where order_no = to_number(p_order_no)) loop
            l_found_count := l_found_count + 1;
            apex_json.open_object;
            apex_json.write('orderNo', l_order_row.order_no);
            apex_json.write('supplier', l_order_row.supplier);
            apex_json.write('dept', l_order_row.dept);
            apex_json.write('status', l_order_row.status);
            apex_json.write('currencyCode', l_order_row.currency_code);
            apex_json.write('exchangeRate', l_order_row.exchange_rate);
            apex_json.write('notBeforeDate', to_char(l_order_row.not_before_date, 'YYYY-MM-DD'), true);
            apex_json.write('notAfterDate', to_char(l_order_row.not_after_date, 'YYYY-MM-DD'), true);
            apex_json.write('earliestShipDate', to_char(l_order_row.earliest_ship_date, 'YYYY-MM-DD'), true);
            apex_json.write('latestShipDate', to_char(l_order_row.latest_ship_date, 'YYYY-MM-DD'), true);
            apex_json.write('totalQtyOrdered', l_order_row.total_qty_ordered);
            apex_json.write('totalCost', l_order_row.total_cost);
            apex_json.open_array('details');
            for l_line_row in (select * from ordloc where order_no = l_order_row.order_no order by item, location) loop
                apex_json.open_object;
                apex_json.write('item', l_line_row.item);
                apex_json.write('location', l_line_row.location);
                apex_json.write('locationType', l_line_row.loc_type);
                apex_json.write('originCountryId', l_line_row.origin_country_id);
                apex_json.write('qtyOrdered', l_line_row.qty_ordered);
                apex_json.write('unitCost', l_line_row.unit_cost);
                apex_json.close_object;
            end loop;
            apex_json.close_array;
            apex_json.close_object;
        end loop;
        apex_json.close_array;
        assert_true(l_found_count = 1, 'orderNo', 'order was not found: ' || p_order_no);
        apex_json.write('hasMore', false);
        apex_json.write('limit', 1000);
        apex_json.write('count', 1);
        apex_json.open_array('links');
        apex_json.close_array;
        apex_json.close_object;
        p_response := office_mfcs_apex_pkg.end_json;
    exception
        when value_error then
            office_mfcs_apex_pkg.abandon_json;
            fail('orderNo', 'must be numeric');
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    -- Read models used by correlation recovery and the local state viewer.
    procedure get_operation_status(p_target_corr in varchar2, p_response out clob) is
        l_found boolean := false;
        l_request_payload varchar2(32000);
        l_response_payload varchar2(32000);
    begin
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.open_array('items');
        for l_row in (
            select *
              from (
                  select e.* from local_mfcs_rest_event e
                   where e.correlation_id = p_target_corr
                   order by event_id desc
              )
             where rownum = 1
        ) loop
            l_request_payload := case when l_row.request_payload is not null then dbms_lob.substr(l_row.request_payload, 32000, 1) end;
            l_response_payload := case when l_row.response_payload is not null then dbms_lob.substr(l_row.response_payload, 32000, 1) end;
            apex_json.open_object;
            apex_json.write('requestId', to_char(l_row.event_id));
            apex_json.write('xCorrelationId', l_row.correlation_id);
            apex_json.write('method', l_row.http_method);
            apex_json.write('serviceUrl', l_row.service_name);
            apex_json.write('responseCode', l_row.response_code);
            apex_json.write('requestTimestamp', to_char(l_row.started_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.write('responseTimestamp', to_char(l_row.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            apex_json.write('requestPayload', l_request_payload, true);
            apex_json.write('responsePayload', l_response_payload, true);
            apex_json.close_object;
            l_found := true;
        end loop;
        apex_json.close_array;
        apex_json.write('hasMore', false);
        apex_json.write('limit', 1000);
        apex_json.write('count', case when l_found then 1 else 0 end);
        apex_json.open_array('links');
        apex_json.close_array;
        apex_json.close_object;
        p_response := office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    procedure state_snapshot(p_response out clob) is
        l_count number;
    begin
        office_mfcs_apex_pkg.begin_json;
        apex_json.open_object;
        apex_json.open_object('tableCounts');
        select count(*) into l_count from item_master; apex_json.write('ITEM_MASTER', l_count);
        select count(*) into l_count from item_supplier; apex_json.write('ITEM_SUPPLIER', l_count);
        select count(*) into l_count from item_supp_country; apex_json.write('ITEM_SUPP_COUNTRY', l_count);
        select count(*) into l_count from item_loc; apex_json.write('ITEM_LOC', l_count);
        select count(*) into l_count from ordhead; apex_json.write('ORDHEAD', l_count);
        select count(*) into l_count from ordsku; apex_json.write('ORDSKU', l_count);
        select count(*) into l_count from ordloc; apex_json.write('ORDLOC', l_count);
        apex_json.close_object;
        apex_json.open_array('items');
        for l_row in (select item, item_parent, item_level, tran_level, item_desc, status, diff_1, diff_2, diff_3 from item_master order by created_at, item) loop
            apex_json.open_object;
            apex_json.write('item', l_row.item);
            apex_json.write('itemParent', l_row.item_parent, true);
            apex_json.write('itemLevel', l_row.item_level);
            apex_json.write('tranLevel', l_row.tran_level);
            apex_json.write('itemDescription', l_row.item_desc);
            apex_json.write('status', l_row.status);
            apex_json.write('diff1', l_row.diff_1);
            apex_json.write('diff2', l_row.diff_2);
            apex_json.write('diff3', l_row.diff_3);
            apex_json.close_object;
        end loop;
        apex_json.close_array;
        apex_json.open_array('orders');
        for l_row in (select order_no, supplier, status, total_qty_ordered, total_cost from ordhead order by order_no) loop
            apex_json.open_object;
            apex_json.write('orderNo', l_row.order_no);
            apex_json.write('supplier', l_row.supplier);
            apex_json.write('status', l_row.status);
            apex_json.write('totalQtyOrdered', l_row.total_qty_ordered);
            apex_json.write('totalCost', l_row.total_cost);
            apex_json.close_object;
        end loop;
        apex_json.close_array;
        apex_json.close_object;
        p_response := office_mfcs_apex_pkg.end_json;
    exception
        when others then
            office_mfcs_apex_pkg.abandon_json;
            raise;
    end;

    -- Administration operations only affect transactional simulator data.
    procedure reset_transactional_data is
    begin
        delete from local_mfcs_rest_event;
        delete from ordloc;
        delete from ordsku;
        delete from ordhead;
        delete from order_number_reservation;
        delete from item_uda;
        delete from item_loc;
        delete from item_supp_country;
        delete from item_supplier;
        delete from item_master;
        delete from item_number_reservation;
        commit;
    end;

    -- Thin REST dispatcher: route, commit/rollback once, then journal the result.
    procedure handle(
        p_resource        in varchar2,
        p_http_method     in varchar2,
        p_request_payload in clob default null,
        p_correlation_id  in varchar2 default null,
        p_order_no        in varchar2 default null,
        p_status_corr_id  in varchar2 default null,
        p_http_status     out number,
        p_response        out clob
    ) is
        l_corr varchar2(100) := correlation_id(p_correlation_id);
        l_started timestamp with time zone := systimestamp;
        l_error varchar2(4000);
        l_field varchar2(4000);
        l_message varchar2(4000);
        l_separator number;
    begin
        case upper(p_resource)
            when 'TOKEN' then
                office_mfcs_apex_pkg.begin_json;
                apex_json.open_object;
                apex_json.write('access_token', 'public-contract-token');
                apex_json.write('token_type', 'Bearer');
                apex_json.write('expires_in', 3600);
                apex_json.close_object;
                p_response := office_mfcs_apex_pkg.end_json;
            when 'RESERVE_ITEM_NUMBERS' then
                reserve_item_numbers(p_request_payload, l_corr, p_response);
            when 'ITEMS' then
                upsert_items(p_request_payload, upper(p_http_method) = 'PUT', p_response);
            when 'ITEMS_UPDATE' then
                upsert_items(p_request_payload, true, p_response);
            when 'ITEM_SUPPLIERS' then
                upsert_item_suppliers(p_request_payload, p_response);
            when 'ITEM_UDAS' then
                upsert_item_udas(p_request_payload, p_response);
            when 'ITEM_LOCATIONS' then
                upsert_item_locations(p_request_payload, p_response);
            when 'RESERVE_ORDER_NUMBERS' then
                reserve_order_numbers(p_request_payload, l_corr, p_response);
            when 'PURCHASE_ORDERS' then
                upsert_purchase_orders(p_request_payload, upper(p_http_method) = 'PUT', p_response);
            when 'GET_ORDER' then
                get_purchase_order(p_order_no, p_response);
            when 'GET_STATUS' then
                get_operation_status(p_status_corr_id, p_response);
            when 'STATE' then
                state_snapshot(p_response);
            when 'RESET' then
                reset_transactional_data;
                p_response := success_response;
            else
                fail('resource', 'is not implemented: ' || p_resource);
        end case;
        commit;
        p_http_status := 200;
        local_mfcs_log_pkg.record_event(
            l_corr, p_resource, p_http_method, p_http_status,
            p_request_payload, p_response, l_started
        );
    exception
        when others then
            rollback;
            l_error := case when sqlcode = -20001 then substr(sqlerrm, instr(sqlerrm, ': ') + 2) else sqlerrm end;
            l_separator := instr(l_error, '|');
            if l_separator > 0 then
                l_field := substr(l_error, 1, l_separator - 1);
                l_message := substr(l_error, l_separator + 1);
            else
                l_field := 'service';
                l_message := l_error;
            end if;
            p_http_status := 400;
            p_response := error_response(l_field, l_message);
            local_mfcs_log_pkg.record_event(
                l_corr, p_resource, p_http_method, p_http_status,
                p_request_payload, p_response, l_started
            );
    end;
end local_mfcs_service_pkg;
/

show errors package body local_mfcs_service_pkg

prompt Local MFCS service package body created

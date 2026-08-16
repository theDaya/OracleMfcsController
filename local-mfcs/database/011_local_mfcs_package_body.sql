set define off

prompt Creating Local MFCS service package body

create or replace package body local_mfcs_service_pkg as
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
        l_object json_object_t := json_object_t();
    begin
        l_object.put('status', 'SUCCESS');
        return l_object.to_clob;
    end;

    function error_response(p_field in varchar2, p_message in varchar2) return clob is
        l_root json_object_t := json_object_t();
        l_error json_object_t := json_object_t();
        l_errors json_array_t := json_array_t();
    begin
        l_root.put('status', 'ERROR');
        l_root.put('message', 'Error found in validation of input payload');
        l_error.put('error', p_message);
        l_error.put('field', p_field);
        l_error.put_null('inputValue');
        l_errors.append(l_error);
        l_root.put('validationErrors', l_errors);
        return l_root.to_clob;
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

    procedure reserve_item_numbers(
        p_payload in clob,
        p_corr in varchar2,
        o_response out clob
    ) is
        l_quantity number;
        l_days number;
        l_type varchar2(10);
        l_item varchar2(25);
        l_expiry timestamp with time zone;
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_node json_object_t;
    begin
        assert_true(p_payload is json, 'body', 'must be valid JSON');
        select json_value(p_payload, '$.quantity' returning number),
               coalesce(json_value(p_payload, '$.daysUntilExpiry' returning number null on error), 14),
               coalesce(json_value(p_payload, '$.itemNumberType' returning varchar2(10) null on error), 'ITEM')
          into l_quantity, l_days, l_type
          from dual;
        assert_true(l_quantity between 1 and 1000 and l_quantity = trunc(l_quantity), 'quantity', 'must be a whole number from 1 to 1000');
        assert_true(l_days between 1 and 90, 'daysUntilExpiry', 'must be from 1 to 90');

        for i in 1 .. l_quantity loop
            l_item := to_char(local_mfcs_item_seq.nextval);
            l_expiry := systimestamp + numtodsinterval(l_days, 'DAY');
            insert into item_number_reservation(
                item, item_number_type, expiry_date, correlation_id
            ) values (
                l_item, l_type, l_expiry, p_corr
            );
            l_node := json_object_t();
            l_node.put('item', l_item);
            l_node.put('itemNumberType', l_type);
            l_node.put('expiryDate', to_char(l_expiry, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            l_items.append(l_node);
        end loop;
        l_root.put('items', l_items);
        o_response := l_root.to_clob;
    end;

    procedure upsert_items(p_payload in clob, p_update in boolean, o_response out clob) is
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
        for r in (
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
            assert_true(r.item is not null, 'items.item', 'is required');
            assert_true(r.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS for direct Local MFCS creation');
            validate_diff(r.diff_1, r.diff_1_type, 'items.diff1');
            validate_diff(r.diff_2, r.diff_2_type, 'items.diff2');
            validate_diff(r.diff_3, r.diff_3_type, 'items.diff3');
            validate_diff(r.diff_4, r.diff_4_type, 'items.diff4');

            if p_update then
                update item_master
                   set item_desc = coalesce(r.item_desc, item_desc),
                       short_desc = coalesce(substr(r.item_desc, 1, 120), short_desc),
                       status = coalesce(r.status, status),
                       approve_ind = coalesce(r.approve_ind, approve_ind),
                       original_retail = coalesce(r.original_retail, original_retail),
                       diff_1 = coalesce(r.diff_1, diff_1),
                       diff_1_type = coalesce(r.diff_1_type, diff_1_type),
                       diff_2 = coalesce(r.diff_2, diff_2),
                       diff_2_type = coalesce(r.diff_2_type, diff_2_type),
                       diff_3 = coalesce(r.diff_3, diff_3),
                       diff_3_type = coalesce(r.diff_3_type, diff_3_type),
                       diff_4 = coalesce(r.diff_4, diff_4),
                       diff_4_type = coalesce(r.diff_4_type, diff_4_type),
                       approved_by = case when coalesce(r.status, status) = 'A' then coalesce(approved_by, 'LOCAL_MFCS_REST') else approved_by end,
                       approved_at = case when coalesce(r.status, status) = 'A' then coalesce(approved_at, systimestamp) else approved_at end,
                       updated_at = systimestamp
                 where item = r.item;
                assert_true(sql%rowcount = 1, 'items.item', 'does not exist for update: ' || r.item);
            else
                assert_true(r.item_level is not null and r.tran_level is not null, 'items.itemLevel', 'itemLevel and tranLevel are required for create');
                assert_true(r.dept is not null and r.class_no is not null and r.subclass_no is not null, 'items.dept', 'dept, class and subclass are required for create');
                if r.item_parent is not null then
                    begin
                        select diff_1, diff_2, diff_3, diff_4
                          into l_parent_diff_1, l_parent_diff_2, l_parent_diff_3, l_parent_diff_4
                          from item_master
                         where item = r.item_parent;
                    exception when no_data_found then
                        fail('items.itemParent', 'must already exist: ' || r.item_parent);
                    end;
                    validate_group_member(l_parent_diff_1, r.diff_1, 'items.diff1');
                    validate_group_member(l_parent_diff_2, r.diff_2, 'items.diff2');
                    validate_group_member(l_parent_diff_3, r.diff_3, 'items.diff3');
                    validate_group_member(l_parent_diff_4, r.diff_4, 'items.diff4');
                end if;
                insert into item_master(
                    item, item_number_type, item_parent, item_grandparent, item_level, tran_level,
                    item_desc, short_desc, dept, class, subclass, status, approve_ind, standard_uom,
                    merchandise_ind, inventory_ind, sellable_ind, orderable_ind,
                    diff_1, diff_1_type, diff_2, diff_2_type, diff_3, diff_3_type, diff_4, diff_4_type,
                    original_retail, approved_by, approved_at
                ) values (
                    r.item, coalesce(r.item_number_type, 'ITEM'), r.item_parent, r.item_grandparent,
                    r.item_level, r.tran_level, coalesce(r.item_desc, r.item), substr(coalesce(r.item_desc, r.item), 1, 120),
                    r.dept, r.class_no, r.subclass_no, coalesce(r.status, 'W'), coalesce(r.approve_ind, 'N'),
                    coalesce(r.standard_uom, 'EA'), coalesce(r.merchandise_ind, 'Y'), coalesce(r.inventory_ind, 'Y'),
                    coalesce(r.sellable_ind, 'Y'), coalesce(r.orderable_ind, 'Y'),
                    r.diff_1, r.diff_1_type, r.diff_2, r.diff_2_type, r.diff_3, r.diff_3_type, r.diff_4, r.diff_4_type,
                    r.original_retail,
                    case when r.status = 'A' then 'LOCAL_MFCS_REST' end,
                    case when r.status = 'A' then systimestamp end
                );
                update item_number_reservation set consumed_ind = 'Y' where item = r.item;
            end if;
        end loop;
        o_response := success_response;
    exception
        when dup_val_on_index then
            fail('items.item', 'already exists or violates a unique item rule');
    end;

    procedure upsert_item_suppliers(p_payload in clob, o_response out clob) is
        l_currency varchar2(3);
        l_count number;
    begin
        validate_collection(p_payload);
        for r in (
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
            assert_true(r.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = r.item;
            assert_true(l_count = 1, 'items.item', 'must exist before sourcing: ' || r.item);
            begin
                select currency_code into l_currency from sups where supplier = r.supplier_no and status = 'A';
            exception when no_data_found then
                fail('items.supplier', 'supplier is not active: ' || r.supplier_no);
            end;
            select count(*) into l_count from country where country_id = r.origin_country;
            assert_true(l_count = 1, 'items.originCountry', 'country is not defined: ' || r.origin_country);
            assert_true(r.unit_cost is not null and r.unit_cost >= 0, 'items.unitCost', 'must be zero or greater');

            if coalesce(r.primary_supp_ind, 'N') = 'Y' then
                update item_supplier set primary_supp_ind = 'N', updated_at = systimestamp where item = r.item;
            end if;
            merge into item_supplier d
            using (select r.item item, r.supplier_no supplier from dual) s
               on (d.item = s.item and d.supplier = s.supplier)
            when matched then update set d.primary_supp_ind = coalesce(r.primary_supp_ind, d.primary_supp_ind), d.updated_at = systimestamp
            when not matched then insert (item, supplier, primary_supp_ind) values (r.item, r.supplier_no, coalesce(r.primary_supp_ind, 'N'));

            if coalesce(r.primary_country_ind, 'N') = 'Y' then
                update item_supp_country
                   set primary_country_ind = 'N', updated_at = systimestamp
                 where item = r.item and supplier = r.supplier_no;
            end if;
            merge into item_supp_country d
            using (select r.item item, r.supplier_no supplier, r.origin_country origin_country_id from dual) s
               on (d.item = s.item and d.supplier = s.supplier and d.origin_country_id = s.origin_country_id)
            when matched then update set
                d.primary_country_ind = coalesce(r.primary_country_ind, d.primary_country_ind),
                d.unit_cost = r.unit_cost,
                d.currency_code = l_currency,
                d.updated_at = systimestamp
            when not matched then insert (
                item, supplier, origin_country_id, primary_country_ind, unit_cost, currency_code
            ) values (
                r.item, r.supplier_no, r.origin_country, coalesce(r.primary_country_ind, 'N'), r.unit_cost, l_currency
            );
        end loop;
        o_response := success_response;
    end;

    procedure upsert_item_locations(p_payload in clob, o_response out clob) is
        l_count number;
        l_primary_supplier number;
        l_retail number;
    begin
        validate_collection(p_payload);
        for r in (
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
            assert_true(r.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = r.item;
            assert_true(l_count = 1, 'items.item', 'must exist before location ranging: ' || r.item);
            if r.loc_type = 'S' then
                select count(*) into l_count from store where store = r.location and status = 'A' and stockholding_ind = 'Y';
            elsif r.loc_type = 'W' then
                select count(*) into l_count from wh where wh = r.location and status = 'A' and stockholding_ind = 'Y';
            else
                l_count := 0;
            end if;
            assert_true(l_count = 1, 'items.locations.location', 'must be an active stockholding location');
            begin
                select supplier into l_primary_supplier
                  from item_supplier
                 where item = r.item and primary_supp_ind = 'Y';
            exception when no_data_found then
                l_primary_supplier := null;
            end;
            select original_retail into l_retail from item_master where item = r.item;
            merge into item_loc d
            using (select r.item item, r.location location, r.loc_type loc_type from dual) s
               on (d.item = s.item and d.location = s.location and d.loc_type = s.loc_type)
            when matched then update set d.status = coalesce(r.location_status, d.status), d.primary_supp = coalesce(l_primary_supplier, d.primary_supp), d.unit_retail = coalesce(l_retail, d.unit_retail), d.updated_at = systimestamp
            when not matched then insert (item, location, loc_type, status, primary_supp, unit_retail)
                values (r.item, r.location, r.loc_type, coalesce(r.location_status, 'A'), l_primary_supplier, l_retail);
        end loop;
        o_response := success_response;
    end;

    procedure upsert_item_udas(p_payload in clob, o_response out clob) is
        l_count number;
    begin
        validate_collection(p_payload);
        for item_row in (
            select item, uda_json, data_destination
              from json_table(p_payload, '$.items[*]'
                  columns
                      item varchar2(25) path '$.item',
                      data_destination varchar2(6) path '$.dataLoadingDestination',
                      uda_json clob format json path '$.uda'
              )
        ) loop
            assert_true(item_row.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from item_master where item = item_row.item;
            assert_true(l_count = 1, 'items.item', 'must exist before UDA assignment: ' || item_row.item);
            for u in (
                select uda_id, uda_value
                  from json_table(item_row.uda_json, '$[*]'
                      columns uda_id number path '$.udaId', uda_value varchar2(250) path '$.udaValue')
            ) loop
                assert_true(u.uda_id is not null and u.uda_value is not null, 'items.uda', 'udaId and udaValue are required');
                merge into item_uda d
                using (select item_row.item item, u.uda_id uda_id from dual) s
                   on (d.item = s.item and d.uda_id = s.uda_id)
                when matched then update set d.uda_value = u.uda_value, d.updated_at = systimestamp
                when not matched then insert (item, uda_id, uda_value) values (item_row.item, u.uda_id, u.uda_value);
            end loop;
        end loop;
        o_response := success_response;
    end;

    procedure reserve_order_numbers(p_payload in clob, p_corr in varchar2, o_response out clob) is
        l_supplier number;
        l_quantity number;
        l_days number;
        l_order_no number;
        l_expiry timestamp with time zone;
        l_count number;
        l_root json_object_t := json_object_t();
        l_orders json_array_t := json_array_t();
        l_node json_object_t;
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
        for i in 1 .. l_quantity loop
            l_order_no := local_mfcs_order_seq.nextval;
            l_expiry := systimestamp + numtodsinterval(l_days, 'DAY');
            insert into order_number_reservation(order_no, supplier, expiry_date, correlation_id)
            values (l_order_no, l_supplier, l_expiry, p_corr);
            l_node := json_object_t();
            if l_supplier is null then l_node.put_null('supplier'); else l_node.put('supplier', l_supplier); end if;
            l_node.put('orderNo', l_order_no);
            l_node.put('expiryDate', to_char(l_expiry, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            l_orders.append(l_node);
        end loop;
        l_root.put('orderNumbers', l_orders);
        o_response := l_root.to_clob;
    end;

    procedure upsert_purchase_orders(p_payload in clob, p_update in boolean, o_response out clob) is
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

        for h in (
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
            assert_true(h.order_no is not null, 'items.orderNo', 'is required');
            assert_true(h.data_destination = 'RMS', 'items.dataLoadingDestination', 'must be RMS');
            select count(*) into l_count from sups where supplier = h.supplier_no and status = 'A';
            assert_true(l_count = 1, 'items.supplier', 'must identify an active supplier');
            select count(*) into l_count from deps where dept = h.dept;
            assert_true(l_count = 1, 'items.dept', 'must identify an existing department');
            select count(*) into l_header_exists from ordhead where order_no = h.order_no;
            l_not_before_date := iso_date(h.not_before_date);
            l_not_after_date := iso_date(h.not_after_date);
            l_earliest_ship_date := iso_date(h.earliest_ship_date);
            l_latest_ship_date := iso_date(h.latest_ship_date);

            if p_update then
                assert_true(l_header_exists = 1, 'items.orderNo', 'does not exist for update');
                update ordhead
                   set supplier = coalesce(h.supplier_no, supplier),
                       dept = coalesce(h.dept, dept),
                       status = coalesce(h.order_status, status),
                       currency_code = coalesce(h.currency_code, currency_code),
                       exchange_rate = coalesce(h.exchange_rate, exchange_rate),
                       not_before_date = coalesce(l_not_before_date, not_before_date),
                       not_after_date = coalesce(l_not_after_date, not_after_date),
                       earliest_ship_date = coalesce(l_earliest_ship_date, earliest_ship_date),
                       latest_ship_date = coalesce(l_latest_ship_date, latest_ship_date),
                       approved_by = coalesce(h.approved_by, approved_by),
                       approved_at = case when coalesce(h.order_status, status) = 'A' then coalesce(approved_at, systimestamp) else approved_at end,
                       updated_at = systimestamp
                 where order_no = h.order_no;
                delete from ordloc where order_no = h.order_no;
                delete from ordsku where order_no = h.order_no;
            else
                assert_true(l_header_exists = 0, 'items.orderNo', 'already exists');
                insert into ordhead(
                    order_no, supplier, dept, status, currency_code, exchange_rate,
                    not_before_date, not_after_date, earliest_ship_date, latest_ship_date,
                    approved_by, approved_at
                ) values (
                    h.order_no, h.supplier_no, h.dept, coalesce(h.order_status, 'W'), h.currency_code,
                    coalesce(h.exchange_rate, 1), l_not_before_date, l_not_after_date,
                    l_earliest_ship_date, l_latest_ship_date, h.approved_by,
                    case when h.order_status = 'A' then systimestamp end
                );
                update order_number_reservation set consumed_ind = 'Y' where order_no = h.order_no;
            end if;

            l_details := h.details;
            select count(*) into l_detail_count from json_table(l_details, '$[*]' columns x path '$');
            assert_true(l_detail_count > 0, 'items.details', 'must contain at least one item/location detail');
            for d in (
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
                    select status, original_retail into l_item_status, l_item_retail from item_master where item = d.item;
                exception when no_data_found then
                    fail('items.details.item', 'does not exist: ' || d.item);
                end;
                assert_true(l_item_status = 'A', 'items.details.item', 'must be approved before ordering: ' || d.item);
                select count(*) into l_count
                  from item_supp_country
                 where item = d.item
                   and supplier = h.supplier_no
                   and origin_country_id = d.origin_country_id;
                assert_true(l_count = 1, 'items.details.originCountryId', 'item must be sourced from the order supplier and country');
                select count(*) into l_count
                  from item_loc
                 where item = d.item
                   and location = d.location
                   and loc_type = d.loc_type
                   and status = 'A';
                assert_true(l_count = 1, 'items.details.location', 'item must be active at the order location');
                assert_true(d.qty_ordered > 0 and d.qty_ordered = trunc(d.qty_ordered), 'items.details.qtyOrdered', 'must be a positive whole number');
                assert_true(d.unit_cost >= 0, 'items.details.unitCost', 'must be zero or greater');

                merge into ordsku target
                using (select h.order_no order_no, d.item item from dual) source
                   on (target.order_no = source.order_no and target.item = source.item)
                when matched then update set
                    target.qty_ordered = target.qty_ordered + d.qty_ordered,
                    target.unit_cost = d.unit_cost,
                    target.origin_country_id = d.origin_country_id
                when not matched then insert (
                    order_no, item, origin_country_id, unit_cost, qty_ordered
                ) values (
                    h.order_no, d.item, d.origin_country_id, d.unit_cost, d.qty_ordered
                );

                insert into ordloc(
                    order_no, item, location, loc_type, origin_country_id,
                    qty_ordered, unit_cost, unit_retail, earliest_ship_date, latest_ship_date
                ) values (
                    h.order_no, d.item, d.location, d.loc_type, d.origin_country_id,
                    d.qty_ordered, d.unit_cost, l_item_retail, l_earliest_ship_date, l_latest_ship_date
                );
            end loop;

            update ordhead oh
               set (total_qty_ordered, total_cost, updated_at) = (
                   select sum(qty_ordered), sum(qty_ordered * unit_cost), systimestamp
                     from ordloc ol
                    where ol.order_no = oh.order_no
               )
             where order_no = h.order_no;
        end loop;
        o_response := success_response;
    end;

    procedure get_purchase_order(p_order_no in varchar2, o_response out clob) is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_order json_object_t := json_object_t();
        l_details json_array_t := json_array_t();
        l_detail json_object_t;
    begin
        for h in (select * from ordhead where order_no = to_number(p_order_no)) loop
            l_order.put('orderNo', h.order_no);
            l_order.put('supplier', h.supplier);
            l_order.put('dept', h.dept);
            l_order.put('status', h.status);
            l_order.put('currencyCode', h.currency_code);
            l_order.put('exchangeRate', h.exchange_rate);
            l_order.put('notBeforeDate', to_char(h.not_before_date, 'YYYY-MM-DD'));
            l_order.put('notAfterDate', to_char(h.not_after_date, 'YYYY-MM-DD'));
            l_order.put('earliestShipDate', to_char(h.earliest_ship_date, 'YYYY-MM-DD'));
            l_order.put('latestShipDate', to_char(h.latest_ship_date, 'YYYY-MM-DD'));
            l_order.put('totalQtyOrdered', h.total_qty_ordered);
            l_order.put('totalCost', h.total_cost);
            for d in (select * from ordloc where order_no = h.order_no order by item, location) loop
                l_detail := json_object_t();
                l_detail.put('item', d.item);
                l_detail.put('location', d.location);
                l_detail.put('locationType', d.loc_type);
                l_detail.put('originCountryId', d.origin_country_id);
                l_detail.put('qtyOrdered', d.qty_ordered);
                l_detail.put('unitCost', d.unit_cost);
                l_details.append(l_detail);
            end loop;
            l_order.put('details', l_details);
            l_items.append(l_order);
        end loop;
        assert_true(l_items.get_size = 1, 'orderNo', 'order was not found: ' || p_order_no);
        l_root.put('items', l_items);
        l_root.put('hasMore', false);
        l_root.put('limit', 1000);
        l_root.put('count', 1);
        l_root.put('links', json_array_t());
        o_response := l_root.to_clob;
    exception when value_error then
        fail('orderNo', 'must be numeric');
    end;

    procedure get_operation_status(p_target_corr in varchar2, o_response out clob) is
        l_root json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_node json_object_t := json_object_t();
        l_found boolean := false;
    begin
        for r in (
            select *
              from (
                  select e.* from local_mfcs_rest_event e
                   where e.correlation_id = p_target_corr
                   order by event_id desc
              )
             where rownum = 1
        ) loop
            l_node.put('requestId', to_char(r.event_id));
            l_node.put('xCorrelationId', r.correlation_id);
            l_node.put('method', r.http_method);
            l_node.put('serviceUrl', r.service_name);
            l_node.put('responseCode', r.response_code);
            l_node.put('requestTimestamp', to_char(r.started_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            l_node.put('responseTimestamp', to_char(r.completed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
            if r.request_payload is not null then l_node.put('requestPayload', dbms_lob.substr(r.request_payload, 32000, 1)); else l_node.put_null('requestPayload'); end if;
            if r.response_payload is not null then l_node.put('responsePayload', dbms_lob.substr(r.response_payload, 32000, 1)); else l_node.put_null('responsePayload'); end if;
            l_items.append(l_node);
            l_found := true;
        end loop;
        l_root.put('items', l_items);
        l_root.put('hasMore', false);
        l_root.put('limit', 1000);
        l_root.put('count', case when l_found then 1 else 0 end);
        l_root.put('links', json_array_t());
        o_response := l_root.to_clob;
    end;

    procedure state_snapshot(o_response out clob) is
        l_root json_object_t := json_object_t();
        l_counts json_object_t := json_object_t();
        l_items json_array_t := json_array_t();
        l_orders json_array_t := json_array_t();
        l_node json_object_t;
        l_count number;
    begin
        select count(*) into l_count from item_master; l_counts.put('ITEM_MASTER', l_count);
        select count(*) into l_count from item_supplier; l_counts.put('ITEM_SUPPLIER', l_count);
        select count(*) into l_count from item_supp_country; l_counts.put('ITEM_SUPP_COUNTRY', l_count);
        select count(*) into l_count from item_loc; l_counts.put('ITEM_LOC', l_count);
        select count(*) into l_count from ordhead; l_counts.put('ORDHEAD', l_count);
        select count(*) into l_count from ordsku; l_counts.put('ORDSKU', l_count);
        select count(*) into l_count from ordloc; l_counts.put('ORDLOC', l_count);
        l_root.put('tableCounts', l_counts);
        for r in (select item, item_parent, item_level, tran_level, item_desc, status, diff_1, diff_2, diff_3 from item_master order by created_at, item) loop
            l_node := json_object_t();
            l_node.put('item', r.item);
            if r.item_parent is null then l_node.put_null('itemParent'); else l_node.put('itemParent', r.item_parent); end if;
            l_node.put('itemLevel', r.item_level);
            l_node.put('tranLevel', r.tran_level);
            l_node.put('itemDescription', r.item_desc);
            l_node.put('status', r.status);
            if r.diff_1 is not null then l_node.put('diff1', r.diff_1); end if;
            if r.diff_2 is not null then l_node.put('diff2', r.diff_2); end if;
            if r.diff_3 is not null then l_node.put('diff3', r.diff_3); end if;
            l_items.append(l_node);
        end loop;
        for r in (select order_no, supplier, status, total_qty_ordered, total_cost from ordhead order by order_no) loop
            l_node := json_object_t();
            l_node.put('orderNo', r.order_no);
            l_node.put('supplier', r.supplier);
            l_node.put('status', r.status);
            l_node.put('totalQtyOrdered', r.total_qty_ordered);
            l_node.put('totalCost', r.total_cost);
            l_orders.append(l_node);
        end loop;
        l_root.put('items', l_items);
        l_root.put('orders', l_orders);
        o_response := l_root.to_clob;
    end;

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

    procedure handle(
        p_resource        in varchar2,
        p_http_method     in varchar2,
        p_request_payload in clob default null,
        p_correlation_id  in varchar2 default null,
        p_order_no        in varchar2 default null,
        p_status_corr_id  in varchar2 default null,
        o_http_status     out number,
        o_response        out clob
    ) is
        l_corr varchar2(100) := correlation_id(p_correlation_id);
        l_started timestamp with time zone := systimestamp;
        l_error varchar2(4000);
        l_field varchar2(4000);
        l_message varchar2(4000);
        l_separator number;
        l_root json_object_t;
    begin
        case upper(p_resource)
            when 'TOKEN' then
                l_root := json_object_t();
                l_root.put('access_token', 'public-contract-token');
                l_root.put('token_type', 'Bearer');
                l_root.put('expires_in', 3600);
                o_response := l_root.to_clob;
            when 'RESERVE_ITEM_NUMBERS' then
                reserve_item_numbers(p_request_payload, l_corr, o_response);
            when 'ITEMS' then
                upsert_items(p_request_payload, upper(p_http_method) = 'PUT', o_response);
            when 'ITEMS_UPDATE' then
                upsert_items(p_request_payload, true, o_response);
            when 'ITEM_SUPPLIERS' then
                upsert_item_suppliers(p_request_payload, o_response);
            when 'ITEM_UDAS' then
                upsert_item_udas(p_request_payload, o_response);
            when 'ITEM_LOCATIONS' then
                upsert_item_locations(p_request_payload, o_response);
            when 'RESERVE_ORDER_NUMBERS' then
                reserve_order_numbers(p_request_payload, l_corr, o_response);
            when 'PURCHASE_ORDERS' then
                upsert_purchase_orders(p_request_payload, upper(p_http_method) = 'PUT', o_response);
            when 'GET_ORDER' then
                get_purchase_order(p_order_no, o_response);
            when 'GET_STATUS' then
                get_operation_status(p_status_corr_id, o_response);
            when 'STATE' then
                state_snapshot(o_response);
            when 'RESET' then
                reset_transactional_data;
                o_response := success_response;
            else
                fail('resource', 'is not implemented: ' || p_resource);
        end case;
        o_http_status := 200;
        insert into local_mfcs_rest_event(
            event_id, correlation_id, service_name, http_method, response_code,
            request_payload, response_payload, started_at, completed_at
        ) values (
            local_mfcs_event_seq.nextval, l_corr, upper(p_resource), upper(p_http_method), o_http_status,
            p_request_payload, o_response, l_started, systimestamp
        );
        commit;
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
            o_http_status := 400;
            o_response := error_response(l_field, l_message);
            insert into local_mfcs_rest_event(
                event_id, correlation_id, service_name, http_method, response_code,
                request_payload, response_payload, started_at, completed_at
            ) values (
                local_mfcs_event_seq.nextval, l_corr, upper(p_resource), upper(p_http_method), o_http_status,
                p_request_payload, o_response, l_started, systimestamp
            );
            commit;
    end;
end local_mfcs_service_pkg;
/

show errors package body local_mfcs_service_pkg

prompt Local MFCS service package body created

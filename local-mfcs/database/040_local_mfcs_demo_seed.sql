set define off
whenever sqlerror exit failure rollback

prompt Seeding Local MFCS demonstration style and order

-- Stable identifiers make the state viewer useful immediately after deployment.
-- The values are outside the simulator sequence ranges used by ordinary tests.
merge into item_master d
using (
    select '3900000' item, cast(null as varchar2(25)) item_parent,
           1 item_level, 2 tran_level, 'Local Demo Leather Trainer' item_desc,
           'Demo Trainer' short_desc, cast(null as varchar2(10)) diff_1,
           cast(null as varchar2(6)) diff_1_type,
           cast(null as varchar2(10)) diff_2, cast(null as varchar2(6)) diff_2_type
      from dual
    union all
    select '3900001', '3900000', 2, 2, 'Local Demo Leather Trainer 7 Standard',
           'Demo Trainer 7', '7', 'S', 'STANDARD', 'W' from dual
    union all
    select '3900002', '3900000', 2, 2, 'Local Demo Leather Trainer 8 Standard',
           'Demo Trainer 8', '8', 'S', 'STANDARD', 'W' from dual
) s
on (d.item = s.item)
when matched then update set
    d.item_parent = s.item_parent,
    d.item_level = s.item_level,
    d.tran_level = s.tran_level,
    d.item_desc = s.item_desc,
    d.short_desc = s.short_desc,
    d.dept = 100,
    d.class = 10,
    d.subclass = 1,
    d.diff_1 = s.diff_1,
    d.diff_1_type = s.diff_1_type,
    d.diff_2 = s.diff_2,
    d.diff_2_type = s.diff_2_type,
    d.diff_3 = 'BLACK',
    d.diff_3_type = 'C',
    d.status = 'A',
    d.approve_ind = 'Y',
    d.original_retail = 69.99,
    d.approved_by = 'LOCAL_DEMO_SEED',
    d.approved_at = systimestamp,
    d.updated_at = systimestamp
when not matched then insert (
    item, item_number_type, item_parent, item_level, tran_level,
    item_desc, short_desc, dept, class, subclass, status, approve_ind,
    diff_1, diff_1_type, diff_2, diff_2_type, diff_3, diff_3_type,
    original_retail, approved_by, approved_at
) values (
    s.item, 'ITEM', s.item_parent, s.item_level, s.tran_level,
    s.item_desc, s.short_desc, 100, 10, 1, 'A', 'Y',
    s.diff_1, s.diff_1_type, s.diff_2, s.diff_2_type, 'BLACK', 'C',
    69.99, 'LOCAL_DEMO_SEED', systimestamp
);

merge into item_supplier d
using (
    select '3900001' item, 70001 supplier from dual
    union all select '3900002', 70001 from dual
) s
on (d.item = s.item and d.supplier = s.supplier)
when matched then update set
    d.primary_supp_ind = 'Y', d.vpn = 'LOCAL-DEMO-TRAINER', d.updated_at = systimestamp
when not matched then insert (item, supplier, primary_supp_ind, vpn)
values (s.item, s.supplier, 'Y', 'LOCAL-DEMO-TRAINER');

merge into item_supp_country d
using (
    select '3900001' item, 70001 supplier, 'CN' origin_country_id from dual
    union all select '3900002', 70001, 'CN' from dual
) s
on (d.item = s.item and d.supplier = s.supplier and d.origin_country_id = s.origin_country_id)
when matched then update set
    d.primary_country_ind = 'Y', d.unit_cost = 22.75,
    d.currency_code = 'USD', d.updated_at = systimestamp
when not matched then insert (
    item, supplier, origin_country_id, primary_country_ind, unit_cost, currency_code
) values (s.item, s.supplier, s.origin_country_id, 'Y', 22.75, 'USD');

merge into item_loc d
using (
    select '3900001' item, 98 location, 'S' loc_type from dual
    union all select '3900002', 98, 'S' from dual
) s
on (d.item = s.item and d.location = s.location and d.loc_type = s.loc_type)
when matched then update set
    d.status = 'A', d.primary_supp = 70001, d.unit_retail = 69.99,
    d.updated_at = systimestamp
when not matched then insert (
    item, location, loc_type, status, primary_supp, unit_retail
) values (s.item, s.location, s.loc_type, 'A', 70001, 69.99);

merge into ordhead d
using (select 11900000 order_no from dual) s
on (d.order_no = s.order_no)
when matched then update set
    d.order_type = 'N/B', d.supplier = 70001, d.dept = 100,
    d.status = 'A', d.currency_code = 'USD', d.exchange_rate = 1,
    d.not_before_date = date '2026-10-12', d.not_after_date = date '2026-10-18',
    d.earliest_ship_date = date '2026-08-20', d.latest_ship_date = date '2026-08-30',
    d.approved_by = 'LOCAL_DEMO_SEED', d.approved_at = systimestamp,
    d.total_qty_ordered = 270, d.total_cost = 6142.50,
    d.source_system = 'LOCAL_DEMO_SEED',
    d.updated_at = systimestamp
when not matched then insert (
    order_no, order_type, supplier, dept, status, currency_code,
    exchange_rate, not_before_date, not_after_date,
    earliest_ship_date, latest_ship_date, approved_by, approved_at,
    total_qty_ordered, total_cost, source_system
) values (
    s.order_no, 'N/B', 70001, 100, 'A', 'USD', 1,
    date '2026-10-12', date '2026-10-18', date '2026-08-20', date '2026-08-30',
    'LOCAL_DEMO_SEED', systimestamp, 270, 6142.50, 'LOCAL_DEMO_SEED'
);

merge into ordsku d
using (
    select 11900000 order_no, '3900001' item, 120 qty_ordered from dual
    union all select 11900000, '3900002', 150 from dual
) s
on (d.order_no = s.order_no and d.item = s.item)
when matched then update set
    d.origin_country_id = 'CN', d.unit_cost = 22.75, d.qty_ordered = s.qty_ordered
when not matched then insert (
    order_no, item, origin_country_id, unit_cost, qty_ordered
) values (s.order_no, s.item, 'CN', 22.75, s.qty_ordered);

merge into ordloc d
using (
    select 11900000 order_no, '3900001' item, 98 location, 'S' loc_type, 120 qty_ordered from dual
    union all select 11900000, '3900002', 98, 'S', 150 from dual
) s
on (
    d.order_no = s.order_no and d.item = s.item
    and d.location = s.location and d.loc_type = s.loc_type
)
when matched then update set
    d.origin_country_id = 'CN', d.qty_ordered = s.qty_ordered,
    d.unit_cost = 22.75, d.unit_retail = 69.99,
    d.earliest_ship_date = date '2026-08-20', d.latest_ship_date = date '2026-08-30'
when not matched then insert (
    order_no, item, location, loc_type, origin_country_id,
    qty_ordered, unit_cost, unit_retail, earliest_ship_date, latest_ship_date
) values (
    s.order_no, s.item, s.location, s.loc_type, 'CN',
    s.qty_ordered, 22.75, 69.99, date '2026-08-20', date '2026-08-30'
);

commit;

prompt Demo seed ready: style 3900000, SKUs 3900001/3900002, order 11900000

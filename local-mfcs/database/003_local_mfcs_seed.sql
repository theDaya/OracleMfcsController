set define off

prompt Seeding Local MFCS foundation data

merge into local_mfcs_system_options d
using (
    select 'DEFAULT_CURRENCY' option_name, 'USD' option_value from dual union all
    select 'ITEM_RESERVATION_DAYS', '14' from dual union all
    select 'ORDER_RESERVATION_DAYS', '14' from dual union all
    select 'RMS_COMPATIBILITY_LEVEL', '16' from dual
) s
on (d.option_name = s.option_name)
when matched then update set d.option_value = s.option_value, d.updated_at = systimestamp
when not matched then insert (option_name, option_value) values (s.option_name, s.option_value);

merge into sups d
using (select 70001 supplier, 'Local MFCS Footwear Supplier' sup_name, 'USD' currency_code, 'A' status from dual) s
on (d.supplier = s.supplier)
when matched then update set d.sup_name = s.sup_name, d.currency_code = s.currency_code, d.status = s.status, d.updated_at = systimestamp
when not matched then insert (supplier, sup_name, currency_code, status) values (s.supplier, s.sup_name, s.currency_code, s.status);

merge into country d
using (
    select 'CN' country_id, 'China' country_desc, 'CNY' currency_code from dual union all
    select 'ZA', 'South Africa', 'ZAR' from dual union all
    select 'US', 'United States', 'USD' from dual
) s
on (d.country_id = s.country_id)
when matched then update set d.country_desc = s.country_desc, d.currency_code = s.currency_code
when not matched then insert (country_id, country_desc, currency_code) values (s.country_id, s.country_desc, s.currency_code);

merge into store d
using (select 98 store, 'Local MFCS Test Store 98' store_name, 'Y' stockholding_ind, 'A' status from dual) s
on (d.store = s.store)
when matched then update set d.store_name = s.store_name, d.stockholding_ind = s.stockholding_ind, d.status = s.status
when not matched then insert (store, store_name, stockholding_ind, status) values (s.store, s.store_name, s.stockholding_ind, s.status);

merge into wh d
using (select 1001 wh, 'Local MFCS Test Warehouse' wh_name, 1001 physical_wh, 'Y' stockholding_ind, 'A' status from dual) s
on (d.wh = s.wh)
when matched then update set d.wh_name = s.wh_name, d.physical_wh = s.physical_wh, d.stockholding_ind = s.stockholding_ind, d.status = s.status
when not matched then insert (wh, wh_name, physical_wh, stockholding_ind, status) values (s.wh, s.wh_name, s.physical_wh, s.stockholding_ind, s.status);

merge into deps d using (select 100 dept, 'Footwear' dept_name from dual) s on (d.dept = s.dept)
when matched then update set d.dept_name = s.dept_name
when not matched then insert (dept, dept_name) values (s.dept, s.dept_name);

merge into class d using (select 100 dept, 10 class, 'Shoes' class_name from dual) s on (d.dept = s.dept and d.class = s.class)
when matched then update set d.class_name = s.class_name
when not matched then insert (dept, class, class_name) values (s.dept, s.class, s.class_name);

merge into subclass d using (select 100 dept, 10 class, 1 subclass, 'Fashion Shoes' subclass_name from dual) s
on (d.dept = s.dept and d.class = s.class and d.subclass = s.subclass)
when matched then update set d.subclass_name = s.subclass_name
when not matched then insert (dept, class, subclass, subclass_name) values (s.dept, s.class, s.subclass, s.subclass_name);

merge into diff_type d
using (
    select 'S' diff_type, 'Size' diff_type_desc from dual union all
    select 'W', 'Width' from dual union all
    select 'C', 'Colour' from dual
) s
on (d.diff_type = s.diff_type)
when matched then update set d.diff_type_desc = s.diff_type_desc
when not matched then insert (diff_type, diff_type_desc) values (s.diff_type, s.diff_type_desc);

merge into diff_ids d
using (
    select '6' diff_id, 'S' diff_type, 'Size 6' diff_desc, 6 display_seq from dual union all
    select '7', 'S', 'Size 7', 7 from dual union all
    select '8', 'S', 'Size 8', 8 from dual union all
    select '9', 'S', 'Size 9', 9 from dual union all
    select '10', 'S', 'Size 10', 10 from dual union all
    select '11', 'S', 'Size 11', 11 from dual union all
    select '12', 'S', 'Size 12', 12 from dual union all
    select '13', 'S', 'Size 13 (outside standard group)', 13 from dual union all
    select 'STANDARD', 'W', 'Standard Width', 1 from dual union all
    select 'WIDE', 'W', 'Wide Width', 2 from dual union all
    select 'NARROW', 'W', 'Narrow Width', 3 from dual union all
    select 'BLACK', 'C', 'Black', 1 from dual union all
    select 'WHITE', 'C', 'White', 2 from dual union all
    select 'BROWN', 'C', 'Brown', 3 from dual union all
    select 'RED', 'C', 'Red', 4 from dual union all
    select 'BLUE', 'C', 'Blue', 5 from dual
) s
on (d.diff_id = s.diff_id)
when matched then update set d.diff_type = s.diff_type, d.diff_desc = s.diff_desc, d.display_seq = s.display_seq
when not matched then insert (diff_id, diff_type, diff_desc, display_seq) values (s.diff_id, s.diff_type, s.diff_desc, s.display_seq);

merge into diff_group_head d
using (
    select 'SHOE_SIZE' diff_group_id, 'S' diff_type, 'Shoe Sizes' diff_group_desc, 100 dept, 10 class, 1 subclass from dual union all
    select 'WIDTH_STD', 'W', 'Footwear Widths', 100, 10, 1 from dual union all
    select 'COLOR_STD', 'C', 'Standard Colours', 100, 10, 1 from dual
) s
on (d.diff_group_id = s.diff_group_id)
when matched then update set d.diff_type = s.diff_type, d.diff_group_desc = s.diff_group_desc, d.dept = s.dept, d.class = s.class, d.subclass = s.subclass
when not matched then insert (diff_group_id, diff_type, diff_group_desc, dept, class, subclass)
values (s.diff_group_id, s.diff_type, s.diff_group_desc, s.dept, s.class, s.subclass);

merge into diff_group_detail d
using (
    select 'SHOE_SIZE' diff_group_id, '6' diff_id, 1 display_seq from dual union all
    select 'SHOE_SIZE', '7', 2 from dual union all
    select 'SHOE_SIZE', '8', 3 from dual union all
    select 'SHOE_SIZE', '9', 4 from dual union all
    select 'SHOE_SIZE', '10', 5 from dual union all
    select 'SHOE_SIZE', '11', 6 from dual union all
    select 'SHOE_SIZE', '12', 7 from dual union all
    select 'WIDTH_STD', 'STANDARD', 1 from dual union all
    select 'WIDTH_STD', 'WIDE', 2 from dual union all
    select 'WIDTH_STD', 'NARROW', 3 from dual union all
    select 'COLOR_STD', 'BLACK', 1 from dual union all
    select 'COLOR_STD', 'WHITE', 2 from dual union all
    select 'COLOR_STD', 'BROWN', 3 from dual union all
    select 'COLOR_STD', 'RED', 4 from dual union all
    select 'COLOR_STD', 'BLUE', 5 from dual
) s
on (d.diff_group_id = s.diff_group_id and d.diff_id = s.diff_id)
when matched then update set d.display_seq = s.display_seq
when not matched then insert (diff_group_id, diff_id, display_seq) values (s.diff_group_id, s.diff_id, s.display_seq);

commit;

prompt Local MFCS foundation data seeded

set define off

prompt Creating Local MFCS relationships, indexes and reporting views

alter table class add constraint class_deps_fk foreign key (dept) references deps (dept);
alter table subclass add constraint subclass_class_fk foreign key (dept, class) references class (dept, class);
alter table diff_ids add constraint diff_ids_type_fk foreign key (diff_type) references diff_type (diff_type);
alter table diff_group_head add constraint diff_group_head_type_fk foreign key (diff_type) references diff_type (diff_type);
alter table diff_group_head add constraint diff_group_head_subclass_fk foreign key (dept, class, subclass) references subclass (dept, class, subclass);
alter table diff_group_detail add constraint diff_group_detail_head_fk foreign key (diff_group_id) references diff_group_head (diff_group_id);
alter table diff_group_detail add constraint diff_group_detail_id_fk foreign key (diff_id) references diff_ids (diff_id);

alter table item_master add constraint item_master_parent_fk foreign key (item_parent) references item_master (item);
alter table item_master add constraint item_master_grandparent_fk foreign key (item_grandparent) references item_master (item);
alter table item_master add constraint item_master_subclass_fk foreign key (dept, class, subclass) references subclass (dept, class, subclass);
alter table item_supplier add constraint item_supplier_item_fk foreign key (item) references item_master (item);
alter table item_supplier add constraint item_supplier_sups_fk foreign key (supplier) references sups (supplier);
alter table item_supp_country add constraint item_supp_country_supplier_fk foreign key (item, supplier) references item_supplier (item, supplier);
alter table item_supp_country add constraint item_supp_country_country_fk foreign key (origin_country_id) references country (country_id);
alter table item_loc add constraint item_loc_item_fk foreign key (item) references item_master (item);
alter table item_uda add constraint item_uda_item_fk foreign key (item) references item_master (item);
alter table order_number_reservation add constraint order_number_res_sups_fk foreign key (supplier) references sups (supplier);

alter table ordhead add constraint ordhead_sups_fk foreign key (supplier) references sups (supplier);
alter table ordhead add constraint ordhead_deps_fk foreign key (dept) references deps (dept);
alter table ordsku add constraint ordsku_head_fk foreign key (order_no) references ordhead (order_no);
alter table ordsku add constraint ordsku_item_fk foreign key (item) references item_master (item);
alter table ordsku add constraint ordsku_country_fk foreign key (origin_country_id) references country (country_id);
alter table ordloc add constraint ordloc_sku_fk foreign key (order_no, item) references ordsku (order_no, item);
alter table ordloc add constraint ordloc_country_fk foreign key (origin_country_id) references country (country_id);

create unique index item_supplier_primary_uq on item_supplier (
    case when primary_supp_ind = 'Y' then item end,
    case when primary_supp_ind = 'Y' then primary_supp_ind end
);

create unique index item_supp_country_primary_uq on item_supp_country (
    case when primary_country_ind = 'Y' then item end,
    case when primary_country_ind = 'Y' then supplier end,
    case when primary_country_ind = 'Y' then primary_country_ind end
);

create index item_master_parent_ix on item_master (item_parent);
create index item_master_hierarchy_ix on item_master (dept, class, subclass);
create index item_supplier_supplier_ix on item_supplier (supplier, item);
create index item_loc_location_ix on item_loc (location, loc_type, item);
create index ordhead_supplier_ix on ordhead (supplier, status, written_date);
create index ordsku_item_ix on ordsku (item, order_no);
create index ordloc_location_ix on ordloc (location, loc_type, order_no);
create index local_mfcs_rest_event_corr_ix on local_mfcs_rest_event (correlation_id, event_id);

create or replace view local_mfcs_item_v as
select im.item,
       im.item_parent,
       im.item_level,
       im.tran_level,
       im.item_desc,
       im.dept,
       im.class,
       im.subclass,
       im.status,
       im.diff_1,
       im.diff_2,
       im.diff_3,
       ims.supplier,
       isc.origin_country_id,
       isc.unit_cost,
       il.location,
       il.loc_type,
       il.unit_retail
  from item_master im
  left join item_supplier ims
    on ims.item = im.item
   and ims.primary_supp_ind = 'Y'
  left join item_supp_country isc
    on isc.item = ims.item
   and isc.supplier = ims.supplier
   and isc.primary_country_ind = 'Y'
  left join item_loc il
    on il.item = im.item;

create or replace view local_mfcs_order_v as
select oh.order_no,
       oh.status,
       oh.supplier,
       oh.dept,
       oh.currency_code,
       oh.not_before_date,
       oh.not_after_date,
       os.item,
       os.origin_country_id,
       ol.location,
       ol.loc_type,
       ol.origin_country_id ordloc_origin_country_id,
       ol.qty_ordered,
       ol.unit_cost,
       ol.qty_ordered * ol.unit_cost line_cost
  from ordhead oh
  join ordsku os on os.order_no = oh.order_no
  join ordloc ol on ol.order_no = os.order_no and ol.item = os.item;

prompt Local MFCS relationships, indexes and reporting views created

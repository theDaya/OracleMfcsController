set define off

prompt Creating Local MFCS RMS-shaped tables

create table local_mfcs_system_options (
    option_name   varchar2(60) not null,
    option_value  varchar2(4000),
    updated_at    timestamp with time zone default systimestamp not null,
    constraint local_mfcs_system_options_pk primary key (option_name)
);

create table sups (
    supplier       number(10) not null,
    sup_name       varchar2(120) not null,
    currency_code  varchar2(3) not null,
    status         char(1) default 'A' not null,
    created_at     timestamp with time zone default systimestamp not null,
    updated_at     timestamp with time zone default systimestamp not null,
    constraint sups_pk primary key (supplier),
    constraint sups_status_ck check (status in ('A', 'I'))
);

create table country (
    country_id    varchar2(3) not null,
    country_desc  varchar2(120) not null,
    currency_code varchar2(3),
    constraint country_pk primary key (country_id)
);

create table store (
    store          number(10) not null,
    store_name     varchar2(120) not null,
    stockholding_ind char(1) default 'Y' not null,
    status         char(1) default 'A' not null,
    constraint store_pk primary key (store),
    constraint store_stockholding_ck check (stockholding_ind in ('Y', 'N')),
    constraint store_status_ck check (status in ('A', 'I'))
);

create table wh (
    wh             number(10) not null,
    wh_name        varchar2(120) not null,
    physical_wh    number(10),
    stockholding_ind char(1) default 'Y' not null,
    status         char(1) default 'A' not null,
    constraint wh_pk primary key (wh),
    constraint wh_stockholding_ck check (stockholding_ind in ('Y', 'N')),
    constraint wh_status_ck check (status in ('A', 'I'))
);

create table deps (
    dept       number(4) not null,
    dept_name  varchar2(120) not null,
    constraint deps_pk primary key (dept)
);

create table class (
    dept        number(4) not null,
    class       number(4) not null,
    class_name  varchar2(120) not null,
    constraint class_pk primary key (dept, class)
);

create table subclass (
    dept           number(4) not null,
    class          number(4) not null,
    subclass       number(4) not null,
    subclass_name  varchar2(120) not null,
    constraint subclass_pk primary key (dept, class, subclass)
);

create table diff_type (
    diff_type       varchar2(6) not null,
    diff_type_desc  varchar2(120) not null,
    constraint diff_type_pk primary key (diff_type)
);

create table diff_ids (
    diff_id      varchar2(10) not null,
    diff_type    varchar2(6) not null,
    diff_desc    varchar2(120) not null,
    display_seq  number(6),
    constraint diff_ids_pk primary key (diff_id)
);

create table diff_group_head (
    diff_group_id    varchar2(10) not null,
    diff_type        varchar2(6) not null,
    diff_group_desc  varchar2(120) not null,
    dept              number(4),
    class             number(4),
    subclass          number(4),
    constraint diff_group_head_pk primary key (diff_group_id)
);

create table diff_group_detail (
    diff_group_id  varchar2(10) not null,
    diff_id        varchar2(10) not null,
    display_seq    number(6) not null,
    constraint diff_group_detail_pk primary key (diff_group_id, diff_id),
    constraint diff_group_detail_seq_uq unique (diff_group_id, display_seq)
);

create table item_number_reservation (
    item              varchar2(25) not null,
    item_number_type  varchar2(10) not null,
    reserved_at       timestamp with time zone default systimestamp not null,
    expiry_date       timestamp with time zone not null,
    consumed_ind      char(1) default 'N' not null,
    correlation_id    varchar2(100),
    constraint item_number_reservation_pk primary key (item),
    constraint item_number_res_consumed_ck check (consumed_ind in ('Y', 'N'))
);

create table item_master (
    item              varchar2(25) not null,
    item_number_type  varchar2(10) default 'ITEM' not null,
    item_parent       varchar2(25),
    item_grandparent  varchar2(25),
    item_level        number(1) not null,
    tran_level        number(1) not null,
    item_desc         varchar2(250) not null,
    short_desc        varchar2(120),
    dept              number(4) not null,
    class             number(4) not null,
    subclass          number(4) not null,
    status            char(1) default 'W' not null,
    approve_ind       char(1) default 'N' not null,
    standard_uom      varchar2(4) default 'EA' not null,
    merchandise_ind   char(1) default 'Y' not null,
    inventory_ind     char(1) default 'Y' not null,
    sellable_ind      char(1) default 'Y' not null,
    orderable_ind     char(1) default 'Y' not null,
    pack_ind          char(1) default 'N' not null,
    diff_1            varchar2(10),
    diff_1_type       varchar2(6),
    diff_2            varchar2(10),
    diff_2_type       varchar2(6),
    diff_3            varchar2(10),
    diff_3_type       varchar2(6),
    diff_4            varchar2(10),
    diff_4_type       varchar2(6),
    original_retail   number(20,4),
    approved_by       varchar2(120),
    approved_at       timestamp with time zone,
    created_at        timestamp with time zone default systimestamp not null,
    updated_at        timestamp with time zone default systimestamp not null,
    constraint item_master_pk primary key (item),
    constraint item_master_level_ck check (item_level between 1 and 3 and tran_level between item_level and 3),
    constraint item_master_status_ck check (status in ('W', 'S', 'A', 'I', 'D')),
    constraint item_master_approve_ck check (approve_ind in ('Y', 'N')),
    constraint item_master_flags_ck check (
        merchandise_ind in ('Y', 'N') and inventory_ind in ('Y', 'N') and
        sellable_ind in ('Y', 'N') and orderable_ind in ('Y', 'N') and pack_ind in ('Y', 'N')
    )
);

create table item_supplier (
    item                  varchar2(25) not null,
    supplier              number(10) not null,
    primary_supp_ind      char(1) default 'N' not null,
    supp_label            varchar2(30),
    vpn                   varchar2(30),
    direct_ship_ind       char(1) default 'N' not null,
    created_at            timestamp with time zone default systimestamp not null,
    updated_at            timestamp with time zone default systimestamp not null,
    constraint item_supplier_pk primary key (item, supplier),
    constraint item_supplier_flags_ck check (primary_supp_ind in ('Y', 'N') and direct_ship_ind in ('Y', 'N'))
);

create table item_supp_country (
    item                 varchar2(25) not null,
    supplier             number(10) not null,
    origin_country_id    varchar2(3) not null,
    primary_country_ind  char(1) default 'N' not null,
    unit_cost            number(20,4) not null,
    currency_code        varchar2(3) not null,
    lead_time            number(6) default 0 not null,
    pickup_lead_time     number(6) default 0 not null,
    default_uop          varchar2(4) default 'EA' not null,
    supp_pack_size       number(12,4) default 1 not null,
    ti                   number(8),
    hi                   number(8),
    created_at           timestamp with time zone default systimestamp not null,
    updated_at           timestamp with time zone default systimestamp not null,
    constraint item_supp_country_pk primary key (item, supplier, origin_country_id),
    constraint item_supp_country_primary_ck check (primary_country_ind in ('Y', 'N')),
    constraint item_supp_country_cost_ck check (unit_cost >= 0 and supp_pack_size > 0)
);

create table item_loc (
    item            varchar2(25) not null,
    location        number(10) not null,
    loc_type        char(1) not null,
    status          char(1) default 'A' not null,
    primary_supp    number(10),
    source_method   varchar2(10) default 'S' not null,
    unit_retail     number(20,4),
    created_at      timestamp with time zone default systimestamp not null,
    updated_at      timestamp with time zone default systimestamp not null,
    constraint item_loc_pk primary key (item, location, loc_type),
    constraint item_loc_type_ck check (loc_type in ('S', 'W')),
    constraint item_loc_status_ck check (status in ('A', 'I', 'C'))
);

create table item_uda (
    item        varchar2(25) not null,
    uda_id      number(10) not null,
    uda_value   varchar2(250) not null,
    updated_at  timestamp with time zone default systimestamp not null,
    constraint item_uda_pk primary key (item, uda_id)
);

create table order_number_reservation (
    order_no        number(12) not null,
    supplier        number(10),
    reserved_at     timestamp with time zone default systimestamp not null,
    expiry_date     timestamp with time zone not null,
    consumed_ind    char(1) default 'N' not null,
    correlation_id  varchar2(100),
    constraint order_number_reservation_pk primary key (order_no),
    constraint order_number_res_consumed_ck check (consumed_ind in ('Y', 'N'))
);

create table ordhead (
    order_no           number(12) not null,
    order_type         varchar2(6) default 'N/B' not null,
    supplier           number(10) not null,
    dept               number(4) not null,
    status             char(1) default 'W' not null,
    currency_code      varchar2(3) not null,
    exchange_rate      number(20,10) default 1 not null,
    not_before_date    date,
    not_after_date     date,
    earliest_ship_date date,
    latest_ship_date   date,
    written_date       date default trunc(sysdate) not null,
    approved_by        varchar2(120),
    approved_at        timestamp with time zone,
    total_qty_ordered  number(20,4) default 0 not null,
    total_cost         number(20,4) default 0 not null,
    source_system      varchar2(30) default 'LOCAL_MFCS_REST' not null,
    created_at         timestamp with time zone default systimestamp not null,
    updated_at         timestamp with time zone default systimestamp not null,
    constraint ordhead_pk primary key (order_no),
    constraint ordhead_status_ck check (status in ('W', 'S', 'A', 'C')),
    constraint ordhead_exchange_rate_ck check (exchange_rate > 0),
    constraint ordhead_dates_ck check (
        (not_before_date is null or not_after_date is null or not_before_date <= not_after_date) and
        (earliest_ship_date is null or latest_ship_date is null or earliest_ship_date <= latest_ship_date)
    )
);

create table ordsku (
    order_no          number(12) not null,
    item              varchar2(25) not null,
    origin_country_id varchar2(3) not null,
    unit_cost         number(20,4) not null,
    qty_ordered       number(20,4) not null,
    qty_received      number(20,4) default 0 not null,
    qty_cancelled     number(20,4) default 0 not null,
    constraint ordsku_pk primary key (order_no, item),
    constraint ordsku_qty_ck check (qty_ordered > 0 and qty_received >= 0 and qty_cancelled >= 0),
    constraint ordsku_cost_ck check (unit_cost >= 0)
);

create table ordloc (
    order_no          number(12) not null,
    item              varchar2(25) not null,
    location          number(10) not null,
    loc_type          char(1) not null,
    origin_country_id varchar2(3) not null,
    qty_ordered       number(20,4) not null,
    qty_received      number(20,4) default 0 not null,
    qty_cancelled     number(20,4) default 0 not null,
    unit_cost         number(20,4) not null,
    unit_retail       number(20,4),
    earliest_ship_date date,
    latest_ship_date   date,
    constraint ordloc_pk primary key (order_no, item, location, loc_type),
    constraint ordloc_type_ck check (loc_type in ('S', 'W')),
    constraint ordloc_qty_ck check (qty_ordered > 0 and qty_received >= 0 and qty_cancelled >= 0),
    constraint ordloc_cost_ck check (unit_cost >= 0)
);

create table local_mfcs_rest_event (
    event_id          number not null,
    correlation_id    varchar2(100) not null,
    service_name      varchar2(100) not null,
    http_method       varchar2(10) not null,
    response_code     number(3) not null,
    request_payload   clob,
    response_payload  clob,
    started_at        timestamp with time zone not null,
    completed_at      timestamp with time zone not null,
    constraint local_mfcs_rest_event_pk primary key (event_id),
    constraint local_mfcs_rest_event_resp_json_ck check (response_payload is json)
);

create sequence local_mfcs_item_seq start with 3000000 increment by 1 nocache;
create sequence local_mfcs_order_seq start with 10700000 increment by 1 nocache;
create sequence local_mfcs_event_seq start with 1 increment by 1 nocache;

prompt Local MFCS RMS-shaped tables created

set define off

prompt Creating MFCS mock-data tables

create table mfcs_api_capture (
    capture_id       number not null,
    resource_type    varchar2(80) not null,
    resource_key     varchar2(200) not null,
    endpoint_url     varchar2(1000) not null,
    http_status      number(5) not null,
    response_payload clob not null,
    captured_at      timestamp with time zone default systimestamp not null,
    captured_by      varchar2(128) default sys_context('USERENV', 'CURRENT_USER') not null
);

create table mfcs_foundation_item (
    item               varchar2(30) not null,
    item_number_type   varchar2(30),
    status             varchar2(10),
    item_level         number,
    tran_level         number,
    item_description   varchar2(500),
    short_description  varchar2(250),
    sellable_ind       char(1),
    orderable_ind      char(1),
    inventory_ind      char(1),
    dept               number,
    dept_name          varchar2(250),
    class              number,
    class_name         varchar2(250),
    subclass           number,
    subclass_name      varchar2(250),
    diff1              varchar2(80),
    diff1_type         varchar2(30),
    diff1_description  varchar2(250),
    diff2              varchar2(80),
    diff2_type         varchar2(30),
    diff2_description  varchar2(250),
    diff3              varchar2(80),
    diff3_type         varchar2(30),
    diff3_description  varchar2(250),
    diff4              varchar2(80),
    diff4_type         varchar2(30),
    diff4_description  varchar2(250),
    brand_name         varchar2(250),
    brand_description  varchar2(250),
    standard_uom       varchar2(30),
    unit_retail        number,
    retail_currency    varchar2(10),
    primary_image_url  varchar2(1000),
    source_capture_id  number not null,
    last_refreshed_at  timestamp with time zone default systimestamp not null
);

create table mfcs_foundation_supplier (
    item                 varchar2(30) not null,
    supplier             number not null,
    primary_supplier_ind char(1),
    vpn                  varchar2(250),
    supplier_label       varchar2(250),
    source_capture_id    number not null,
    last_refreshed_at    timestamp with time zone default systimestamp not null
);

create table mfcs_foundation_supplier_country (
    item                 varchar2(30) not null,
    supplier             number not null,
    origin_country_id    varchar2(10) not null,
    primary_country_ind  char(1),
    unit_cost            number,
    currency_code        varchar2(10),
    source_capture_id    number not null,
    last_refreshed_at    timestamp with time zone default systimestamp not null
);

create sequence mfcs_api_capture_seq start with 1 increment by 1 nocache;

prompt MFCS mock-data tables created

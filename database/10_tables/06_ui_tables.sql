set define off

prompt Creating OFFICE MFCS APEX UI staging objects

create table ui_draft (
    draft_id             number not null,
    action_request_id    varchar2(80) not null,
    operation_name       varchar2(30) default 'CREATE_ALL' not null,
    source_system        varchar2(60) default 'APEX' not null,
    source_style_ref     varchar2(120),
    source_order_ref     varchar2(120),
    source_version       varchar2(60) default '1',
    user_id              varchar2(255),
    description          varchar2(250),
    style                varchar2(30),
    order_no             varchar2(30),
    department           number,
    class                number,
    subclass             number,
    supplier             number,
    origin_country       varchar2(3),
    import_country       varchar2(3),
    currency_code        varchar2(3),
    colour               varchar2(60),
    unit_cost            number,
    retail_price         number,
    not_before_date      date,
    not_after_date       date,
    otb_eow_date         date,
    earliest_ship_date   date,
    latest_ship_date     date,
    delivery_loc         number,
    order_exchange_rate  number,
    cancel_code          varchar2(20),
    order_amend_msg      varchar2(1000),
    request_payload      clob,
    preview_payload      clob,
    response_payload     clob,
    http_status          number,
    draft_status         varchar2(30) default 'DRAFT' not null,
    created_at           timestamp with time zone default systimestamp not null,
    updated_at           timestamp with time zone default systimestamp not null,
    submitted_at         timestamp with time zone
);

create table ui_draft_sku (
    draft_sku_id       number not null,
    draft_id           number not null,
    source_variant_ref varchar2(120),
    sku_size           varchar2(40),
    sku_width          varchar2(40) default 'ALL',
    sku_qty            number default 1,
    sku_id             varchar2(30),
    created_at         timestamp with time zone default systimestamp not null,
    updated_at         timestamp with time zone default systimestamp not null
);

create sequence ui_draft_seq start with 1 increment by 1 nocache;
create sequence ui_draft_sku_seq start with 1 increment by 1 nocache;

alter table ui_draft add constraint ui_draft_pk primary key (draft_id);
alter table ui_draft add constraint ui_draft_action_uk unique (action_request_id);
alter table ui_draft add constraint ui_draft_operation_ck check (
    operation_name in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL', 'MODIFY_STYLE', 'MODIFY_ORDER')
);
alter table ui_draft add constraint ui_draft_status_ck check (
    draft_status in ('DRAFT', 'VALID', 'INVALID', 'PREVIEWED', 'SUBMITTED', 'COMPLETED', 'PARTIALLY_COMPLETED', 'FAILED')
);
alter table ui_draft add constraint ui_draft_request_json_ck check (request_payload is null or request_payload is json);
alter table ui_draft add constraint ui_draft_preview_json_ck check (preview_payload is null or preview_payload is json);
alter table ui_draft add constraint ui_draft_response_json_ck check (response_payload is null or response_payload is json);

alter table ui_draft_sku add constraint ui_draft_sku_pk primary key (draft_sku_id);
alter table ui_draft_sku add constraint ui_draft_sku_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
alter table ui_draft_sku add constraint ui_draft_sku_qty_ck check (sku_qty is null or sku_qty > 0);
create index ui_draft_sku_ix1 on ui_draft_sku (draft_id);

create or replace trigger ui_draft_biu
    before insert or update on ui_draft
    for each row
begin
    if inserting then
        if :new.draft_id is null then
            :new.draft_id := ui_draft_seq.nextval;
        end if;
        if :new.action_request_id is null then
            :new.action_request_id := 'APEX-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
        end if;
    end if;
    :new.updated_at := systimestamp;
end;
/

create or replace trigger ui_draft_sku_biu
    before insert or update on ui_draft_sku
    for each row
begin
    if inserting and :new.draft_sku_id is null then
        :new.draft_sku_id := ui_draft_sku_seq.nextval;
    end if;
    :new.updated_at := systimestamp;
end;
/

-- UDAs captured against the style. There is no SKU-level table on purpose: SKUs
-- inherit their style's UDAs, which is the contract the backend mapper implements.
create table ui_draft_uda (
    draft_uda_id number not null,
    draft_id     number not null,
    uda_id       number not null,
    uda_value    varchar2(30),
    uda_text     varchar2(250),
    uda_date     date,
    created_at   timestamp with time zone default systimestamp not null,
    updated_at   timestamp with time zone default systimestamp not null
);

-- Barcodes, one row per UPC per SKU. draft_id is denormalised from the parent SKU
-- so the console's grid is a single-table query filtered by the page's draft, and
-- APEX can process its rows automatically. The trigger keeps it true.
create table ui_draft_sku_upc (
    draft_upc_id number not null,
    draft_id     number not null,
    draft_sku_id number not null,
    upc          varchar2(30) not null,
    upc_type     varchar2(10) default 'EAN13',
    primary_yn   varchar2(1)  default 'N',
    created_at   timestamp with time zone default systimestamp not null,
    updated_at   timestamp with time zone default systimestamp not null
);

create sequence ui_draft_uda_seq start with 1 increment by 1 nocache;
create sequence ui_draft_sku_upc_seq start with 1 increment by 1 nocache;

alter table ui_draft_uda add constraint ui_draft_uda_pk primary key (draft_uda_id);
alter table ui_draft_uda add constraint ui_draft_uda_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
-- One row per UDA per draft. A second value for the same UDA is a contradiction,
-- not an addition: every definition on this tenant is singleValueInd Y.
alter table ui_draft_uda add constraint ui_draft_uda_uk unique (draft_id, uda_id);
create index ui_draft_uda_ix1 on ui_draft_uda (draft_id);

alter table ui_draft_sku_upc add constraint ui_draft_sku_upc_pk primary key (draft_upc_id);
alter table ui_draft_sku_upc add constraint ui_draft_sku_upc_fk foreign key (draft_sku_id)
    references ui_draft_sku (draft_sku_id) on delete cascade;
alter table ui_draft_sku_upc add constraint ui_draft_sku_upc_draft_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
-- A barcode identifies exactly one item, so it cannot repeat within a style.
alter table ui_draft_sku_upc add constraint ui_draft_sku_upc_uk unique (draft_id, upc);
alter table ui_draft_sku_upc add constraint ui_draft_sku_upc_primary_ck check (primary_yn in ('Y', 'N'));
create index ui_draft_sku_upc_ix1 on ui_draft_sku_upc (draft_sku_id);

create or replace trigger ui_draft_uda_biu
    before insert or update on ui_draft_uda
    for each row
begin
    if inserting and :new.draft_uda_id is null then
        :new.draft_uda_id := ui_draft_uda_seq.nextval;
    end if;
    :new.updated_at := systimestamp;
end;
/

create or replace trigger ui_draft_sku_upc_biu
    before insert or update on ui_draft_sku_upc
    for each row
begin
    if inserting and :new.draft_upc_id is null then
        :new.draft_upc_id := ui_draft_sku_upc_seq.nextval;
    end if;
    -- Derived, never captured: the grid only asks which SKU the barcode belongs to.
    select s.draft_id into :new.draft_id
      from ui_draft_sku s
     where s.draft_sku_id = :new.draft_sku_id;
    :new.updated_at := systimestamp;
end;
/

-- Seasons, images and tariff codes. All three hang off the draft rather than the
-- SKU, for the same reason UDAs do: a real Office item carries them identically on
-- the style and on every SKU, so the console captures them once and the mapper
-- writes them to both levels.
create table ui_draft_season (
    draft_season_id number not null,
    draft_id        number not null,
    season_id       number not null,
    phase_id        number not null,
    sequence_no     number,
    created_at      timestamp with time zone default systimestamp not null,
    updated_at      timestamp with time zone default systimestamp not null
);

create table ui_draft_image (
    draft_image_id    number not null,
    draft_id          number not null,
    image_name        varchar2(120) not null,
    image_address     varchar2(255),
    image_description varchar2(40),
    image_type        varchar2(6),
    primary_yn        varchar2(1) default 'N',
    display_priority  number,
    created_at        timestamp with time zone default systimestamp not null,
    updated_at        timestamp with time zone default systimestamp not null
);

create table ui_draft_hts (
    draft_hts_id   number not null,
    draft_id       number not null,
    hts            varchar2(25) not null,
    import_country varchar2(3) not null,
    origin_country varchar2(3) not null,
    effect_from    date not null,
    effect_to      date not null,
    created_at     timestamp with time zone default systimestamp not null,
    updated_at     timestamp with time zone default systimestamp not null
);

create sequence ui_draft_season_seq start with 1 increment by 1 nocache;
create sequence ui_draft_image_seq start with 1 increment by 1 nocache;
create sequence ui_draft_hts_seq start with 1 increment by 1 nocache;

alter table ui_draft_season add constraint ui_draft_season_pk primary key (draft_season_id);
alter table ui_draft_season add constraint ui_draft_season_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
-- A style sits in a season once. A second phase for the same season is a
-- contradiction rather than an addition.
alter table ui_draft_season add constraint ui_draft_season_uk unique (draft_id, season_id);
create index ui_draft_season_ix1 on ui_draft_season (draft_id);

alter table ui_draft_image add constraint ui_draft_image_pk primary key (draft_image_id);
alter table ui_draft_image add constraint ui_draft_image_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
alter table ui_draft_image add constraint ui_draft_image_uk unique (draft_id, image_name);
alter table ui_draft_image add constraint ui_draft_image_primary_ck check (primary_yn in ('Y', 'N'));
create index ui_draft_image_ix1 on ui_draft_image (draft_id);

alter table ui_draft_hts add constraint ui_draft_hts_pk primary key (draft_hts_id);
alter table ui_draft_hts add constraint ui_draft_hts_fk foreign key (draft_id)
    references ui_draft (draft_id) on delete cascade;
-- One tariff code per importing country per style.
alter table ui_draft_hts add constraint ui_draft_hts_uk unique (draft_id, hts, import_country);
alter table ui_draft_hts add constraint ui_draft_hts_dates_ck check (effect_to >= effect_from);
create index ui_draft_hts_ix1 on ui_draft_hts (draft_id);

create or replace trigger ui_draft_season_biu
    before insert or update on ui_draft_season
    for each row
begin
    if inserting and :new.draft_season_id is null then
        :new.draft_season_id := ui_draft_season_seq.nextval;
    end if;
    :new.updated_at := systimestamp;
end;
/

create or replace trigger ui_draft_image_biu
    before insert or update on ui_draft_image
    for each row
begin
    if inserting and :new.draft_image_id is null then
        :new.draft_image_id := ui_draft_image_seq.nextval;
    end if;
    :new.updated_at := systimestamp;
end;
/

create or replace trigger ui_draft_hts_biu
    before insert or update on ui_draft_hts
    for each row
begin
    if inserting and :new.draft_hts_id is null then
        :new.draft_hts_id := ui_draft_hts_seq.nextval;
    end if;
    :new.updated_at := systimestamp;
end;
/

prompt OFFICE MFCS APEX UI staging objects created

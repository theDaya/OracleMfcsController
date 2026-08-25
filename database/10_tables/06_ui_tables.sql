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

prompt OFFICE MFCS APEX UI staging objects created

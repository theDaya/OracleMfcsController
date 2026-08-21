set define off

prompt Creating OFFICE MFCS master-data cache

-- Local cache of MFCS foundation data.
--
-- Two population routes, recorded per row in SOURCE:
--   ENDPOINT:<path>  read directly from a foundation service that returns rows
--   DERIVED:<path>   harvested from the item or order feed, because the matching
--                    foundation publish queue is empty on this tenant
--
-- The derived route exists because merchhier, diffid, supplier, store, warehouse
-- and uda all return HTTP 200 with zero rows here: they are publish/delta feeds
-- and nothing has been queued into them. The item feed still carries dept,
-- class, subclass, diff and supplier values, so those are recovered from it.

declare
    l_exists number;
begin
    select count(*) into l_exists from user_tables where table_name = 'MASTER_DATA';
    if l_exists = 0 then
        execute immediate q'[
            create table master_data (
                data_type    varchar2(40)  not null,
                data_code    varchar2(120) not null,
                parent_code  varchar2(120) default '~' not null,
                description  varchar2(400),
                attributes   clob,
                source       varchar2(200),
                refreshed_at timestamp with time zone default systimestamp not null
            )
        ]';
        execute immediate 'alter table master_data add constraint master_data_pk '
                       || 'primary key (data_type, data_code, parent_code)';
        execute immediate 'create index master_data_ix1 on master_data (data_type, parent_code)';
    end if;
end;
/

declare
    l_exists number;
begin
    select count(*) into l_exists from user_tables where table_name = 'MASTER_REFRESH';
    if l_exists = 0 then
        execute immediate q'[
            create table master_refresh (
                data_type    varchar2(40) not null,
                source       varchar2(200),
                http_status  number,
                row_count    number,
                message      varchar2(1000),
                started_at   timestamp with time zone,
                completed_at timestamp with time zone
            )
        ]';
        execute immediate 'alter table master_refresh add constraint master_refresh_pk '
                       || 'primary key (data_type)';
    end if;
end;
/

prompt OFFICE MFCS master-data cache created

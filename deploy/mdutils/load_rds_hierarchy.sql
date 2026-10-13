set define off
set serveroutput on
set feedback off

-- Loads the merchandise hierarchy from an RDS extract into MASTER_DATA.
--
--   deploy/mdutils/sql.sh deploy/mdutils/load_rds_hierarchy.sql     (from the repo root)
--
-- Why this exists: foundation/merchhier/* publishes nothing on STG, so the only
-- hierarchy the refresh could find was what happened to appear on items - 4
-- departments of 21. Validation rejects every department it has not seen, so a
-- style in any of the other 17 could not be sent at all. The extract is the
-- tenant's own DEPS, CLASS, SUBCLASS and GROUPS tables, read out of RDS.
--
-- Expects, in "RDS extract/" at the repo root (gitignored - the audit columns
-- carry the creating user's email address):
--   rds_wv_groups.csv  rds_wv_deps.csv  rds_wv_class.csv  rds_wv_subclass.csv
--
-- Only codes, names and the ids that link them reach MASTER_DATA. The staging
-- tables hold every column, as text, because LOAD ... NEW guesses types badly
-- from dates like 7/23/2026; they are dropped at the end so the audit columns
-- never persist here. LOAD is told to skip the header and map by position:
-- matching by name fails on any header over 30 characters
-- (INVENTORY_LAYER_IDENTIFIER_TYPE is 31), even when the column exists. So the
-- staging columns must stay in the extract's column order.
--
-- Rows are written the shape the item harvest writes them - CLASS under its
-- department, SUBCLASS under "dept.class" - because validation and the console
-- lists read exactly that shape. The source is stamped EXPORT:RDS, and the
-- harvest leaves an existing row alone, so a later refresh does not relabel it.
--
-- Re-runnable: a new extract merges over the old. It does not delete - a code
-- missing from a later extract is reported, not removed, because an extract
-- that came out short should not silently narrow what validation accepts.
-- Deleted rows in the extract (LAST_DML_TYPE = 'D') are skipped.

prompt Staging the extract

-- Left behind only by a run that failed part way.
begin
    for t in (select table_name from user_tables
               where table_name in ('STG_RDS_GROUPS', 'STG_RDS_DEPS', 'STG_RDS_CLASS', 'STG_RDS_SUBCLASS')) loop
        execute immediate 'drop table ' || t.table_name || ' purge';
    end loop;
end;
/

whenever sqlerror exit failure rollback

create table stg_rds_groups (
    group_no varchar2(4000), group_name varchar2(4000), buyer varchar2(4000),
    merch varchar2(4000), division varchar2(4000), create_id varchar2(4000),
    create_datetime varchar2(4000), last_update_id varchar2(4000),
    last_update_datetime varchar2(4000), target_commit_datetime varchar2(4000),
    csn_nbr varchar2(4000), last_dml_type varchar2(4000)
);

create table stg_rds_deps (
    dept varchar2(4000), dept_name varchar2(4000), buyer varchar2(4000),
    merch varchar2(4000), profit_calc_type varchar2(4000), purchase_type varchar2(4000),
    group_no varchar2(4000), bud_int varchar2(4000), bud_mkup varchar2(4000),
    total_market_amt varchar2(4000), markup_calc_type varchar2(4000),
    otb_calc_type varchar2(4000), max_avg_counter varchar2(4000),
    avg_tolerance_pct varchar2(4000), dept_vat_incl_ind varchar2(4000),
    inventory_layer_identifier_type varchar2(4000), create_id varchar2(4000),
    create_datetime varchar2(4000), last_update_id varchar2(4000),
    last_update_datetime varchar2(4000), last_dml_type varchar2(4000),
    csn_nbr varchar2(4000), target_commit_datetime varchar2(4000)
);

create table stg_rds_class (
    dept varchar2(4000), class varchar2(4000), class_name varchar2(4000),
    class_vat_ind varchar2(4000), create_id varchar2(4000),
    create_datetime varchar2(4000), class_id varchar2(4000),
    last_update_id varchar2(4000), last_update_datetime varchar2(4000),
    inventory_layer_identifier_type varchar2(4000), last_dml_type varchar2(4000),
    csn_nbr varchar2(4000), target_commit_datetime varchar2(4000)
);

create table stg_rds_subclass (
    dept varchar2(4000), class varchar2(4000), subclass varchar2(4000),
    sub_name varchar2(4000), create_id varchar2(4000), create_datetime varchar2(4000),
    subclass_id varchar2(4000), include_up_chrg_in_prc_cost varchar2(4000),
    default_ic_tsf_price varchar2(4000), last_update_id varchar2(4000),
    last_update_datetime varchar2(4000), upd_sell_date_on_st_ord_receipt_ind varchar2(4000),
    upd_sell_date_on_wh2st_receipt_ind varchar2(4000),
    upd_sell_date_on_st2st_receipt_ind varchar2(4000),
    min_units_for_sell_date_reset varchar2(4000), last_dml_type varchar2(4000),
    csn_nbr varchar2(4000), target_commit_datetime varchar2(4000)
);

-- SQLcl's LOAD takes no quoted path, so change into the folder rather than name it.
set loadformat csv column_names off skip_rows 1
cd RDS extract
load stg_rds_groups rds_wv_groups.csv
load stg_rds_deps rds_wv_deps.csv
load stg_rds_class rds_wv_class.csv
load stg_rds_subclass rds_wv_subclass.csv
cd ..

prompt Merging into MASTER_DATA

declare
    c_source constant varchar2(200) := 'EXPORT:RDS STG3 2026-09-28';
    l_started timestamp with time zone := systimestamp;
    l_rows number := 0;
    l_missing number;

    procedure put(
        p_type   in varchar2,
        p_code   in varchar2,
        p_parent in varchar2,
        p_desc   in varchar2,
        p_attrs  in clob
    ) is
    begin
        merge into master_data d
        using (select p_type dt, p_code dc, nvl(p_parent, '~') pc from dual) s
        on (d.data_type = s.dt and d.data_code = s.dc and d.parent_code = s.pc)
        when matched then update set
            d.description = p_desc,
            d.attributes = p_attrs,
            d.source = c_source,
            d.refreshed_at = systimestamp
        when not matched then insert (data_type, data_code, parent_code, description, attributes, source)
        values (s.dt, s.dc, s.pc, p_desc, p_attrs, c_source);
        l_rows := l_rows + 1;
    end;
begin
    -- LOAD reports a failure but does not raise one, so a file that did not
    -- load would otherwise merge as "nothing to add" and look like success.
    for t in (select 'STG_RDS_GROUPS' n, (select count(*) from stg_rds_groups) c from dual union all
              select 'STG_RDS_DEPS', (select count(*) from stg_rds_deps) from dual union all
              select 'STG_RDS_CLASS', (select count(*) from stg_rds_class) from dual union all
              select 'STG_RDS_SUBCLASS', (select count(*) from stg_rds_subclass) from dual) loop
        if t.c = 0 then
            raise_application_error(-20990, t.n || ' is empty: its CSV did not load. Nothing merged.');
        end if;
    end loop;

    for r in (select * from stg_rds_groups where nvl(last_dml_type, 'I') <> 'D') loop
        put('MERCH_GROUP', trim(r.group_no), null, trim(r.group_name),
            json_object('division' value trim(r.division)));
    end loop;

    for r in (select * from stg_rds_deps where nvl(last_dml_type, 'I') <> 'D') loop
        put('DEPARTMENT', trim(r.dept), null, trim(r.dept_name),
            json_object('groupNo' value trim(r.group_no)));
    end loop;

    for r in (select * from stg_rds_class where nvl(last_dml_type, 'I') <> 'D') loop
        put('CLASS', trim(r.class), trim(r.dept), trim(r.class_name),
            json_object('classId' value trim(r.class_id)));
    end loop;

    for r in (select * from stg_rds_subclass where nvl(last_dml_type, 'I') <> 'D') loop
        put('SUBCLASS', trim(r.subclass), trim(r.dept) || '.' || trim(r.class), trim(r.sub_name),
            json_object('subclassId' value trim(r.subclass_id)));
    end loop;

    merge into master_refresh m
    using (select 'RDS_HIERARCHY' dt from dual) s
    on (m.data_type = s.dt)
    when matched then update set
        m.source = c_source, m.http_status = null, m.row_count = l_rows,
        m.message = 'Groups, departments, classes and subclasses from an RDS extract.',
        m.started_at = l_started, m.completed_at = systimestamp
    when not matched then insert (data_type, source, http_status, row_count, message, started_at, completed_at)
    values (s.dt, c_source, null, l_rows,
            'Groups, departments, classes and subclasses from an RDS extract.', l_started, systimestamp);

    commit;
    dbms_output.put_line('Merged ' || l_rows || ' rows.');

    -- Reported, not deleted: see the header.
    select count(*)
      into l_missing
      from master_data m
     where m.data_type in ('DEPARTMENT', 'CLASS', 'SUBCLASS')
       and m.source <> c_source;
    dbms_output.put_line('Hierarchy rows this extract did not include: ' || l_missing);
end;
/

prompt Dropping the staging tables

drop table stg_rds_groups purge;
drop table stg_rds_deps purge;
drop table stg_rds_class purge;
drop table stg_rds_subclass purge;

set feedback on
select data_type, count(*) as row_count
  from master_data
 where data_type in ('MERCH_GROUP', 'DEPARTMENT', 'CLASS', 'SUBCLASS')
 group by data_type
 order by data_type;

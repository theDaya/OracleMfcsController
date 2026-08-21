set define off

prompt Creating OFFICE MFCS event log objects

begin
    execute immediate
        'create table event_log (' ||
        'log_id number not null,' ||
        'action_request_id varchar2(80),' ||
        'step_code varchar2(60),' ||
        'attempt_id number,' ||
        'event_level varchar2(10) default ''INFO'' not null,' ||
        'event_phase varchar2(80) not null,' ||
        'message varchar2(1000),' ||
        'detail_payload clob,' ||
        'created_at timestamp with time zone default systimestamp not null' ||
        ')';
exception
    when others then
        if sqlcode != -955 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'create sequence event_log_seq ' ||
        'start with 1 increment by 1 nocache';
exception
    when others then
        if sqlcode != -955 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'alter table event_log add constraint ' ||
        'event_log_pk primary key (log_id)';
exception
    when others then
        if sqlcode != -2260 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'alter table event_log add constraint ' ||
        'event_level_ck check ' ||
        '(event_level in (''DEBUG'', ''INFO'', ''WARN'', ''ERROR''))';
exception
    when others then
        if sqlcode != -2264 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'alter table event_log add constraint ' ||
        'event_detail_json_ck check ' ||
        '(detail_payload is null or detail_payload is json)';
exception
    when others then
        if sqlcode != -2264 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'create index event_log_ix1 on ' ||
        'event_log (action_request_id, created_at)';
exception
    when others then
        if sqlcode != -955 then
            raise;
        end if;
end;
/

begin
    execute immediate
        'create index event_log_ix2 on ' ||
        'event_log (event_phase, created_at)';
exception
    when others then
        if sqlcode != -955 then
            raise;
        end if;
end;
/

prompt OFFICE MFCS event log objects ready

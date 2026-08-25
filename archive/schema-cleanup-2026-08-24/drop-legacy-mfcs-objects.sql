set define off
set serveroutput on

prompt Dropping legacy OFFICE_MFCS and mock capture objects

begin
    for p in (
        select column_value object_name
          from table(sys.odcivarchar2list(
              'MFCS_MOCK_CAPTURE_PKG',
              'OFFICE_MFCS_API_PKG',
              'OFFICE_MFCS_CLIENT_PKG',
              'OFFICE_MFCS_MAPPING_PKG',
              'OFFICE_MFCS_ORCHESTRATOR_PKG',
              'OFFICE_MFCS_PUBLIC_CONTRACT_PKG',
              'OFFICE_MFCS_RECOVERY_PKG',
              'OFFICE_MFCS_REQUEST_PKG',
              'OFFICE_MFCS_VALIDATION_PKG'
          ))
    ) loop
        begin
            execute immediate 'drop package ' || p.object_name;
            dbms_output.put_line('Dropped package ' || p.object_name);
        exception
            when others then
                if sqlcode = -4043 then
                    dbms_output.put_line('Package absent: ' || p.object_name);
                else
                    raise;
                end if;
        end;
    end loop;

    for t in (
        select column_value object_name
          from table(sys.odcivarchar2list(
              'OFFICE_MFCS_ATTEMPT',
              'OFFICE_MFCS_EVENT_LOG',
              'OFFICE_MFCS_STEP',
              'OFFICE_MFCS_REQUEST',
              'OFFICE_MFCS_ENTITY_MAP',
              'OFFICE_MFCS_CONFIG',
              'OFFICE_MFCS_SECRET'
          ))
    ) loop
        begin
            execute immediate 'drop table ' || t.object_name || ' cascade constraints purge';
            dbms_output.put_line('Dropped table ' || t.object_name);
        exception
            when others then
                if sqlcode = -942 then
                    dbms_output.put_line('Table absent: ' || t.object_name);
                else
                    raise;
                end if;
        end;
    end loop;

    for s in (
        select column_value object_name
          from table(sys.odcivarchar2list(
              'OFFICE_MFCS_ATTEMPT_SEQ',
              'OFFICE_MFCS_EVENT_LOG_SEQ'
          ))
    ) loop
        begin
            execute immediate 'drop sequence ' || s.object_name;
            dbms_output.put_line('Dropped sequence ' || s.object_name);
        exception
            when others then
                if sqlcode = -2289 then
                    dbms_output.put_line('Sequence absent: ' || s.object_name);
                else
                    raise;
                end if;
        end;
    end loop;
end;
/

prompt Legacy cleanup complete

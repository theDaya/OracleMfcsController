-- Removes the RDS layer from mdutils, where it is installed beside the original
-- only to be compiled and previewed (rds/tests/README.md). NEVER RUN THIS IN RDS.
--
-- Drops every IE_MFCS_* object in the current schema and nothing else.

begin
    for o in (select object_name, object_type
                from user_objects
               where object_name like 'IE\_MFCS\_%' escape '\'
                 and object_type in ('PACKAGE', 'VIEW', 'SEQUENCE', 'TABLE')
               order by decode(object_type, 'PACKAGE', 1, 'VIEW', 2, 'SEQUENCE', 3, 'TABLE', 4)) loop
        execute immediate 'drop ' || o.object_type || ' ' || o.object_name
            || case when o.object_type = 'TABLE' then ' cascade constraints purge' end;
    end loop;
end;
/

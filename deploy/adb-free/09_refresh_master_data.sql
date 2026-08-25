set define off
set serveroutput on size unlimited
set lines 240

-- Run as MFCS_INTEGRATION after the bearer token/config has been set.
-- This is read-only against MFCS and populates MASTER_DATA for the APEX LOVs.

declare
    l_summary clob;
begin
    master_pkg.refresh_all(l_summary);
    dbms_output.put_line(dbms_lob.substr(l_summary, 32000, 1));
end;
/

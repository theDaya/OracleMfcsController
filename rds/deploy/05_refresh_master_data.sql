-- Starts the master data load, and is the first thing to call MFCS from RDS -
-- so it is also the test of the credential and the network ACLs. Reads only:
-- every call is a GET against a foundation feed.
-- Run in APEX: SQL Workshop > SQL Scripts.
--
-- It runs as a one-off scheduler job rather than in this script, because it
-- takes four to five minutes (measured on mdutils: 4m19s, nearly all of it the
-- UDA, diff and code feeds) and a SQL Scripts run that long can be cut off by
-- the web tier while the database carries on. This returns at once. Run
-- 06_refresh_status.sql after five minutes or so to see how it went. The job
-- drops itself when it finishes.

begin
    dbms_scheduler.create_job(
        job_name   => 'IE_MFCS_REFRESH_MASTER_DATA',
        job_type   => 'PLSQL_BLOCK',
        job_action => 'declare l_summary clob; begin ie_mfcs_master_data.refresh_all(l_summary); end;',
        enabled    => true,
        auto_drop  => true,
        comments   => 'One-off master data load for the IE_MFCS controller.'
    );
end;
/

select job_name, state, start_date
  from user_scheduler_jobs
 where job_name = 'IE_MFCS_REFRESH_MASTER_DATA';

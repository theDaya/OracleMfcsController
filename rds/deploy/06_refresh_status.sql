-- How the master data load started by 05 went. Safe to run as often as you
-- like. Run in APEX: SQL Workshop > SQL Scripts.

-- 1. The job. A row here with state RUNNING means it has not finished. No row
--    means it finished and dropped itself - then step 2 says how it ended.
select job_name, state, start_date, last_start_date
  from user_scheduler_jobs
 where job_name = 'IE_MFCS_REFRESH_MASTER_DATA';

-- 2. How the run ended. Expect SUCCEEDED. On FAILED, errors says why.
select log_date, status, error#, errors
  from user_scheduler_job_run_details
 where job_name = 'IE_MFCS_REFRESH_MASTER_DATA'
 order by log_date desc
 fetch first 3 rows only;

-- 3. One row per source. Expect HTTP 200 throughout, RDS_HIERARCHY with about
--    417 rows and no message, UDA 27, DIFF and DIFF_GROUP with rows.
--      401 everywhere: the credential's id or secret is wrong, or the workspace
--        is not being found.
--      403: the credential belongs to another tenant.
--      ORA-24247 or ORA-29273 in a message: a network ACL is missing - for this
--        schema, or for the APEX engine schema, which needs its own.
select data_type, http_status, row_count, message, source
  from ie_mfcs_log_master_refresh
 order by data_type;

-- 4. What landed, by type and origin.
select data_type, source, count(*) as row_count
  from ie_mfcs_ref_master_data
 group by data_type, source
 order by data_type, source;

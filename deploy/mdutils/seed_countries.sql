-- Countries, from the STG front-end export in docs/foundationExports.
-- Generated - do not hand-edit.
--
-- The tenant serves no country feed, so validation had nothing to check
-- ORIGIN_COUNTRY and IMPORT_COUNTRY against except a handful of MAP.COUNTRY.*
-- config rows. This is the same list the front end shows.
--
--   deploy/mdutils/sql.sh deploy/mdutils/seed_countries.sql

set define off

merge into master_data d using (select '99' c, 'Multiple' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AD' c, 'Andorra' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AE' c, 'United Arab Emirates' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AF' c, 'Afghanistan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AG' c, 'Antigua and Barbuda' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AI' c, 'Anguilla' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AL' c, 'Albania' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AM' c, 'Armenia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AO' c, 'Angola' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AQ' c, 'Antarctica' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AR' c, 'Argentina' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AS' c, 'American Samoa' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AT' c, 'Austria' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AU' c, 'Australia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AW' c, 'Aruba' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AX' c, 'Åland Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'AZ' c, 'Azerbaijan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BA' c, 'Bosnia and Herzegovina' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BB' c, 'Barbados' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BD' c, 'Bangladesh' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BE' c, 'Belgium' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BF' c, 'Burkina Faso' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BG' c, 'Bulgaria' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BH' c, 'Bahrain' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BI' c, 'Burundi' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BJ' c, 'Benin' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BL' c, 'Saint Barthélemy' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BM' c, 'Bermuda' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BN' c, 'Brunei Darussalam' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BO' c, 'Bolivia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BQ' c, 'Bonaire, Sint Eustatius and Saba' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BR' c, 'Brazil' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BS' c, 'Bahamas' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BT' c, 'Bhutan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BV' c, 'Bouvet Island' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BW' c, 'Botswana' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BY' c, 'Belarus' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'BZ' c, 'Belize' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CA' c, 'Canada' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CC' c, 'Cocos (Keeling) Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CD' c, 'Congo, Democratic Republic Of The' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CF' c, 'Central African Republic' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CG' c, 'Congo' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CH' c, 'Switzerland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CI' c, 'Cote d''Ivoire' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CK' c, 'Cook Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CL' c, 'Chile' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CM' c, 'Cameroon' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CN' c, 'China' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CO' c, 'Colombia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CR' c, 'Costa Rica' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CU' c, 'Cuba' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CV' c, 'Cabo Verde' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CW' c, 'Curaçao' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CX' c, 'Christmas Island' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CY' c, 'Cyprus' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'CZ' c, 'Czech Republic' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DE' c, 'Germany' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DJ' c, 'Djibouti' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DK' c, 'Denmark' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DM' c, 'Dominica' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DO' c, 'Dominican Republic' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'DZ' c, 'Algeria' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'EC' c, 'Ecuador' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'EE' c, 'Estonia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'EG' c, 'Egypt' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'EH' c, 'Western Sahara' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ER' c, 'Eritrea' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ES' c, 'Spain' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ET' c, 'Ethiopia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FI' c, 'Finland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FJ' c, 'Fiji' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FK' c, 'Falkland Islands, Malvinas' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FM' c, 'Micronesia, Federated States Of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FO' c, 'Faroe Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'FR' c, 'France' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GA' c, 'Gabon' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GB' c, 'United Kingdom' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GD' c, 'Grenada' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GE' c, 'Georgia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GF' c, 'French Guiana' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GG' c, 'Guernsey' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GH' c, 'Ghana' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GI' c, 'Gibraltar' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GL' c, 'Greenland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GM' c, 'Gambia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GN' c, 'Guinea' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GP' c, 'Guadeloupe' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GQ' c, 'Equatorial Guinea' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GR' c, 'Greece' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GS' c, 'South Georgia and the South Sandwich Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GT' c, 'Guatemala' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GU' c, 'Guam' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GW' c, 'Guinea-Bissau' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'GY' c, 'Guyana' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HK' c, 'Hong Kong' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HM' c, 'Heard Island and McDonald Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HN' c, 'Honduras' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HR' c, 'Croatia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HT' c, 'Haiti' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'HU' c, 'Hungary' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ID' c, 'Indonesia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IE' c, 'Ireland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IL' c, 'Israel' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IM' c, 'Isle of Man' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IN' c, 'India' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IO' c, 'British Indian Ocean Territory' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IQ' c, 'Iraq' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IR' c, 'Iran, Islamic Republic Of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IS' c, 'Iceland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'IT' c, 'Italy' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'JE' c, 'Jersey' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'JM' c, 'Jamaica' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'JO' c, 'Jordan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'JP' c, 'Japan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KE' c, 'Kenya' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KG' c, 'Kyrgyzstan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KH' c, 'Cambodia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KI' c, 'Kiribati' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KM' c, 'Comoros' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KN' c, 'Saint Kitts and Nevis' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KP' c, 'Korea, Democratic Peoples Republic Of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KR' c, 'Korea,Republic Of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KW' c, 'Kuwait' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KY' c, 'Cayman Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'KZ' c, 'Kazakhstan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LA' c, 'Lao Peoples Democratic Republic' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LB' c, 'Lebanon' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LC' c, 'Saint Lucia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LI' c, 'Liechtenstein' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LK' c, 'Sri Lanka' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LR' c, 'Liberia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LS' c, 'Lesotho' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LT' c, 'Lithuania' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LU' c, 'Luxembourg' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LV' c, 'Latvia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'LY' c, 'Libya' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MA' c, 'Morocco' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MC' c, 'Monaco' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MD' c, 'Moldova, Republic Of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ME' c, 'Montenegro' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MF' c, 'Saint Martin (French part)' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MG' c, 'Madagascar' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MH' c, 'Marshall Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MK' c, 'Macedonia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ML' c, 'Mali' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MM' c, 'Myanmar' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MN' c, 'Mongolia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MO' c, 'Macao' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MP' c, 'Northern Mariana Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MQ' c, 'Martinique' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MR' c, 'Mauritania' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MS' c, 'Montserrat' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MT' c, 'Malta' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MU' c, 'Mauritius' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MV' c, 'Maldives' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MW' c, 'Malawi' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MX' c, 'Mexico' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MY' c, 'Malaysia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'MZ' c, 'Mozambique' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NA' c, 'Namibia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NC' c, 'New Caledonia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NE' c, 'Niger' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NF' c, 'Norfolk Island' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NG' c, 'Nigeria' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NI' c, 'Nicaragua' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NL' c, 'Netherlands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NO' c, 'Norway' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NP' c, 'Nepal' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NR' c, 'Nauru' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NU' c, 'Niue' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'NZ' c, 'New Zealand' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'OM' c, 'Oman' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PA' c, 'Panama' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PE' c, 'Peru' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PF' c, 'French Polynesia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PG' c, 'Papua New Guinea' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PH' c, 'Philippines' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PK' c, 'Pakistan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PL' c, 'Poland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PM' c, 'Saint Pierre and Miquelon' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PN' c, 'Pitcairn' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PR' c, 'Puerto Rico' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PS' c, 'Palestine, State of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PT' c, 'Portugal' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PW' c, 'Palau' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'PY' c, 'Paraguay' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'QA' c, 'Qatar' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'RE' c, 'Réunion' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'RO' c, 'Romania' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'RS' c, 'Serbia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'RU' c, 'Russian Federation' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'RW' c, 'Rwanda' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SA' c, 'Saudi Arabia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SB' c, 'Solomon Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SC' c, 'Seychelles' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SD' c, 'Sudan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SE' c, 'Sweden' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SG' c, 'Singapore' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SH' c, 'Saint Helena, Ascension and Tristan da Cunha' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SI' c, 'Slovenia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SJ' c, 'Svalbard and Jan Mayen' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SK' c, 'Slovakia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SL' c, 'Sierra Leone' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SM' c, 'San Marino' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SN' c, 'Senegal' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SO' c, 'Somalia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SR' c, 'Suriname' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SS' c, 'South Sudan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ST' c, 'Sao Tome and Principe' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SV' c, 'El Salvador' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SX' c, 'Sint Maarten (Dutch part)' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SY' c, 'Syrian Arab Republic' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'SZ' c, 'Swaziland' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TC' c, 'Turks and Caicos Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TD' c, 'Chad' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TF' c, 'French Southern Territories' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TG' c, 'Togo' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TH' c, 'Thailand' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TJ' c, 'Tajikistan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TK' c, 'Tokelau' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TL' c, 'Timor-Leste' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TM' c, 'Turkmenistan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TN' c, 'Tunisia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TO' c, 'Tonga' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TR' c, 'Turkey' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TT' c, 'Trinidad and Tobago' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TV' c, 'Tuvalu' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TW' c, 'Taiwan (Province of China)' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'TZ' c, 'Tanzania, United Republic of' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'UA' c, 'Ukraine' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'UG' c, 'Uganda' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'UM' c, 'United States Minor Outlying Islands' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'US' c, 'United States of America' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'UY' c, 'Uruguay' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'UZ' c, 'Uzbekistan' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VA' c, 'Holy See [Vatican City State]' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VC' c, 'Saint Vincent and the Grenadines' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VE' c, 'Venezuela' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VG' c, 'Virgin Islands, British' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VI' c, 'Virgin Islands, U.S.' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VN' c, 'Viet Nam' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'VU' c, 'Vanuatu' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'WF' c, 'Wallis and Futuna' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'WS' c, 'Samoa' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'YE' c, 'Yemen' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'YT' c, 'Mayotte' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ZA' c, 'South Africa' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ZM' c, 'Zambia' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');
merge into master_data d using (select 'ZW' c, 'Zimbabwe' n from dual) s
  on (d.data_type = 'COUNTRY' and d.data_code = s.c and d.parent_code = '~')
  when matched then update set d.description = s.n, d.refreshed_at = systimestamp
  when not matched then insert (data_type, data_code, parent_code, description, source)
    values ('COUNTRY', s.c, '~', s.n, 'EXPORT:Countries');

commit;

select count(*) countries from master_data where data_type = 'COUNTRY';

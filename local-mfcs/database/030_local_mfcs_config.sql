set define off
set serveroutput on

prompt Enabling Local MFCS controller mode

merge into office_mfcs_config target
using (
    select 'DEFAULT' environment, 'MFCS_CLIENT_MODE' config_key, 'LOCAL_MFCS' config_value from dual
    union all
    select 'DEFAULT', 'MFCS_SCHEMA_READY_YN', 'Y' from dual
    union all
    select 'DEFAULT', 'MFCS_BASE_URL', 'https://localhost:8443/ords/office_mfcs_app/local-mfcs' from dual
) source
on (target.environment = source.environment and target.config_key = source.config_key)
when matched then update set
    target.config_value = source.config_value,
    target.enabled_ind = 'Y',
    target.updated_at = systimestamp
when not matched then insert (
    environment, config_key, config_value, enabled_ind
) values (
    source.environment, source.config_key, source.config_value, 'Y'
);

commit;

prompt Local MFCS controller mode enabled

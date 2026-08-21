set define off

-- Environment configuration lookup.

prompt Creating config_pkg

create or replace package config_pkg authid definer as
    function get_config(
        p_key         in varchar2,
        p_default     in varchar2 default null,
        p_environment in varchar2 default 'DEFAULT'
    ) return varchar2;
end config_pkg;
/

show errors

create or replace package body config_pkg as
    function get_config(
        p_key         in varchar2,
        p_default     in varchar2 default null,
        p_environment in varchar2 default 'DEFAULT'
    ) return varchar2 is
        l_value varchar2(32767);
    begin
        select dbms_lob.substr(config_value, 32767, 1)
          into l_value
          from config
         where environment = p_environment
           and config_key = p_key
           and enabled_ind = 'Y';

        return l_value;
    exception
        when no_data_found then
            return p_default;
    end;
end config_pkg;
/

show errors

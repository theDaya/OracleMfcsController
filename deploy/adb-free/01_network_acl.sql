-- Run as ADMIN.
-- Allows APEX_WEB_SERVICE calls from MFCS_INTEGRATION out to the MFCS service host
-- and the IDCS identity domain that issues the bearer token.
--
-- These are two different hosts and both are required:
--   MFCS service : rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com
--   IDCS token   : idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com
--
-- Note: 'resolve' is a host-level privilege and cannot be appended with a port
-- range (ORA-24244). It is granted in a separate call from 'connect'/'http'.

set define off
set serveroutput on

declare
    type host_list is table of varchar2(400);
    l_hosts host_list := host_list(
        'rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com',
        'idcs-c994c399babd4611b2505c507dbcf5a5.identity.oraclecloud.com'
    );
begin
    for i in 1 .. l_hosts.count loop
        -- Port-scoped: outbound HTTPS.
        dbms_network_acl_admin.append_host_ace(
            host => l_hosts(i),
            lower_port => 443,
            upper_port => 443,
            ace => xs$ace_type(
                privilege_list => xs$name_list('connect', 'http'),
                principal_name => 'MFCS_INTEGRATION',
                principal_type => xs_acl.ptype_db
            )
        );

        -- Host-scoped: DNS resolution. No ports permitted here.
        dbms_network_acl_admin.append_host_ace(
            host => l_hosts(i),
            ace => xs$ace_type(
                privilege_list => xs$name_list('resolve'),
                principal_name => 'MFCS_INTEGRATION',
                principal_type => xs_acl.ptype_db
            )
        );

        dbms_output.put_line('ACEs appended for ' || l_hosts(i));
    end loop;
    commit;
end;
/

prompt Network ACLs configured

set lines 200 pages 100
col host for a62
col principal for a14
col privilege for a10
select host, lower_port, upper_port, principal, privilege, grant_type
  from dba_host_aces
 where principal = 'MFCS_INTEGRATION'
 order by host, privilege;

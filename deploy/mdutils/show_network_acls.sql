set define off
set linesize 220
set pagesize 200

-- Run as SYS. Read-only: changes nothing.
--
-- MFCS_INTEGRATION already reaches the MFCS host, so a working ACE for it
-- exists somewhere. The point of this script is to see its exact shape and
-- copy it, rather than guess at what append_host_ace will accept.

prompt == Which container am I in? ACLs are per-PDB; FREEPDB1 is the target.
select sys_context('userenv', 'con_name') as container,
       sys_context('userenv', 'current_user') as connected_as
  from dual;

prompt
prompt == Every host ACE for this schema. Note whether the working MFCS host
prompt == carries explicit ports or NULLs - that is the thing to match.
column host format a62
column principal format a22
column privilege format a12
select a.host, a.lower_port, a.upper_port,
       p.principal, p.privilege, p.is_grant, p.principal_type
  from dba_host_acls a
  left join dba_host_aces p
    on p.host = a.host
   and nvl(p.lower_port, -1) = nvl(a.lower_port, -1)
 where upper(p.principal) = 'MFCS_INTEGRATION'
    or p.principal is null
 order by a.host, a.lower_port;

prompt
prompt == Everything assigned, unfiltered, in case the grant is via a role or PUBLIC
select host, lower_port, upper_port, principal, privilege, principal_type
  from dba_host_aces
 order by host, lower_port;

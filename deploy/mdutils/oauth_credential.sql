set define off
set serveroutput on

-- Registers the MFCS OAuth2 credential. Run once per environment.
--
-- THIS SCRIPT CONTAINS NO CREDENTIALS AND MUST NEVER CONTAIN ANY. It creates an
-- empty credential; the client id and secret go in through a separate call that
-- is deliberately not scripted here - see the prompt it prints at the end.
--
-- That split is the point. apex_credential.create_credential does not accept a
-- secret, so everything that describes the credential can live in a repository
-- with a public remote, and the two values that cannot are set by hand, once,
-- by someone who has them.
--
-- Once set, neither value can be read back. APEX_WORKSPACE_CREDENTIALS has no
-- column for either, and credentials are excluded from application exports.

declare
    l_workspace varchar2(100) := 'TW_TEST';
    l_static_id varchar2(100) := 'MFCS_OAUTH';
    l_scope     varchar2(200);
    l_exists    number;
begin
    select dbms_lob.substr(config_value, 200, 1) into l_scope
      from config where config_key = 'MFCS_SCOPE' and environment = 'DEFAULT';

    apex_util.set_workspace(p_workspace => l_workspace);

    select count(*) into l_exists
      from apex_workspace_credentials where static_id = l_static_id;

    if l_exists > 0 then
        dbms_output.put_line('Credential ' || l_static_id || ' already exists; leaving it alone.');
        dbms_output.put_line('To replace its id and secret, just run set_persistent_credentials again.');
    else
        apex_credential.create_credential(
            p_credential_name      => 'MFCS OAuth2 (client credentials)',
            p_credential_static_id => l_static_id,
            p_authentication_type  => 'OAUTH2_CLIENT_CREDENTIALS',
            p_scope                => l_scope,
            p_credential_comment   =>
                'Client credentials for the MFCS tenant. Set the id and secret with '
                || 'apex_credential.set_persistent_credentials; they cannot be read back.');
        dbms_output.put_line('Created credential ' || l_static_id || ' with scope ' || l_scope || '.');
    end if;
end;
/

prompt
prompt ============================================================================
prompt  Now set the id and secret yourself. Type it; do not save it to a file,
prompt  and do not paste it into a chat or an issue.
prompt
prompt    begin
prompt        apex_util.set_workspace(p_workspace => 'TW_TEST');
prompt        apex_credential.set_persistent_credentials(
prompt            p_credential_static_id => 'MFCS_OAUTH',
prompt            p_client_id            => '<client id>',
prompt            p_client_secret        => '<client secret>');
prompt    end;
prompt    /
prompt
prompt  Then switch the auth mode over:
prompt
prompt    update config set config_value = 'OAUTH_CLIENT_CREDENTIALS'
prompt     where config_key = 'MFCS_AUTH_MODE' and environment = 'DEFAULT';
prompt    commit;
prompt
prompt  The same thing is available in APEX Builder if you prefer a UI:
prompt  Workspace Utilities > Web Credentials.
prompt ============================================================================
prompt

select static_id, name, credential_type, scope
  from apex_workspace_credentials order by static_id;

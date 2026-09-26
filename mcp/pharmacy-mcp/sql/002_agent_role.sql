-- Read-only login role for pharmacy-mcp. It can read the agent schema and nothing else.
-- Run after 001_agent_views.sql, as a role allowed to create roles (e.g. the superuser).
-- Set the password separately; do not commit it:
--   ALTER ROLE agent_ro PASSWORD '<secret>';

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'agent_ro') then
    create role agent_ro login;
  end if;
end $$;

-- Reads only, and bounded.
alter role agent_ro set default_transaction_read_only = on;
alter role agent_ro set statement_timeout = '15s';
alter role agent_ro set idle_in_transaction_session_timeout = '30s';

-- No access to the application tables; views run with their owner's rights.
revoke all on all tables in schema public from agent_ro;

grant usage on schema agent to agent_ro;
grant select on all tables in schema agent to agent_ro;   -- includes views
grant execute on function agent.today() to agent_ro;
alter default privileges in schema agent grant select on tables to agent_ro;

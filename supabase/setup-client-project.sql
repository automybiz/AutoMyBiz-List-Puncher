-- =============================================================================
-- LIST PUNCHER - one-time setup for a CLIENT'S OWN Supabase project
-- -----------------------------------------------------------------------------
-- Run this in the SQL Editor of the client's project (the one that client owns).
-- Safe to re-run: every statement is idempotent.
--
-- AFTER running this, in the dashboard:
--   Project Settings -> Data API -> Exposed schemas -> add "list_puncher" -> Save
--
-- Then copy Project URL + Publishable key and connect them in List Puncher
-- (button: "Cloud Project"). Full walkthrough: docs/CLIENT-SUPABASE-SETUP.md
-- =============================================================================

begin;

create schema if not exists list_puncher;

create table if not exists list_puncher.lists (
  id uuid primary key default gen_random_uuid(),
  location_id text not null,
  project_id text not null,
  -- The whole punch list as text. Named after the CONTENT, not a format: this is
  -- List Puncher's own checklist shorthand (YAML-flavoured headers + markdown-flavoured
  -- checkboxes), which is neither valid YAML nor strict Markdown.
  checklist_text text not null default '',
  updated_at timestamptz not null default now()
);

-- The unique key the app's upsert targets:
--   POST /rest/v1/lists?on_conflict=location_id,project_id
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'list_puncher.lists'::regclass
      and conname = 'lists_location_id_project_id_key'
  ) then
    alter table list_puncher.lists
      add constraint lists_location_id_project_id_key unique (location_id, project_id);
  end if;
end $$;

-- NULLs do NOT collide in a UNIQUE constraint, so a NULL tenant column would let the
-- upsert insert duplicates forever. Both are always supplied by the app.
alter table list_puncher.lists alter column location_id set not null;
alter table list_puncher.lists alter column project_id set not null;

alter table list_puncher.lists enable row level security;

-- The app talks to this table with the PUBLISHABLE key from inside a GHL iframe, and
-- GHL is the only login boundary, so the API roles need these table privileges. RLS is
-- the gate. NOTE: DELETE is deliberately NOT granted - the app only ever inserts or
-- updates, so nothing in the browser can destroy a row.
grant usage on schema list_puncher to anon, authenticated;
grant select, insert, update on list_puncher.lists to anon, authenticated;

drop policy if exists lists_anon_all on list_puncher.lists;
create policy lists_anon_all on list_puncher.lists
  for all
  to anon, authenticated
  using (true)
  with check (true);

commit;

-- Verify (expect rls_enabled = true, privilege rows for anon/authenticated):
--   select relrowsecurity from pg_class where oid = 'list_puncher.lists'::regclass;
--   select grantee, string_agg(privilege_type, ', ')
--     from information_schema.role_table_grants
--    where table_schema = 'list_puncher' group by grantee;

-- -----------------------------------------------------------------------------
-- OPTIONAL: expose the schema from SQL instead of the dashboard toggle.
-- This REPLACES the whole exposed-schema list, so keep the existing names.
-- -----------------------------------------------------------------------------
-- alter role authenticator set pgrst.db_schemas = 'public, storage, graphql_public, list_puncher';
-- notify pgrst, 'reload config';

-- -----------------------------------------------------------------------------
-- MIGRATING AN OLDER PROJECT (created before v1.27, when the column was called "yaml"):
--   alter table list_puncher.lists rename column yaml to checklist_text;
-- Renaming preserves every row. The app auto-detects either name, so the order of this
-- migration vs. the next app deploy does not matter.
-- -----------------------------------------------------------------------------

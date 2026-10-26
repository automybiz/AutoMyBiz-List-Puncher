-- =============================================================================
-- LIST PUNCHER - AGENCY HUB
-- One project, many clients, REAL tenant isolation, zero setup for a new client.
-- -----------------------------------------------------------------------------
-- TABLE NAMES AS OF BUILD 1.47 (migration `rename_to_list_headers_list_items_legacy_list_blobs`):
--   list_puncher.list_headers        one row per list: name, sort_order, tenant, lifecycle.
--                                    Written by get_directory / apply_directory_changes.
--   list_puncher.list_items          one row per task OR section (level 0 = section).
--                                    Written by get_list_items / apply_list_item_changes.
--   list_puncher.legacy_list_blobs   the retiring BLOB transport - one LPF row per list. This is
--                                    the table every function below refers to. `?storage=blob`
--                                    reads/writes it.
-- `list_headers` + `list_items` share the `list_` prefix because they are the pair; the blob table
-- is marked `legacy_` so it cannot be mistaken for part of that pair.
-- This script predates the row tables; they are created by the phase3_* / phase4_* migrations and
-- documented in docs/HANDOVER.md.
-- -----------------------------------------------------------------------------
-- How it works
--   * each GHL sub-account (location) gets its own random secret, stored as the GHL
--     custom value "list_puncher_secret" so every device in that sub-account has it
--   * the secret is never trusted to Row Level Security (Postgres cannot see request
--     headers/params), so SECURITY DEFINER functions verify it and only ever touch
--     that one tenant's row
--   * anon gets NO table privileges - only EXECUTE on the functions below, so direct
--     REST access to list_puncher.legacy_list_blobs becomes impossible
--
-- PHASE 1 (run now)   : creates tenants + functions, leaves the old policy alone so the
--                       currently deployed build keeps working.
-- PHASE 2 (run LATER) : revoke direct table access - only after the RPC build is live.
-- =============================================================================

begin;

create table if not exists list_puncher.tenants (
  location_id  text primary key,
  secret_hash  text not null,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz
);

alter table list_puncher.tenants enable row level security;
-- Deliberately NO policies: tenants are only reachable through the functions below.
revoke all on list_puncher.tenants from anon, authenticated;

-- sha256() is built in (PG 11+), so no pgcrypto/extensions dependency.
-- NB: never upper()/lower() this - the hash must be exact or every secret breaks.
create or replace function list_puncher.hash_secret(p_secret text)
returns text
language sql
immutable
as $$
  select encode(sha256(convert_to(coalesce(p_secret, ''), 'UTF8')), 'hex');
$$;

-- Registers a tenant on first use (trust-on-first-use) and returns the stored hash.
-- The FIRST secret presented for a location wins; later mismatches get nothing.
create or replace function list_puncher.ensure_tenant(p_location text, p_secret text)
returns text
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_hash   text := list_puncher.hash_secret(p_secret);
  v_stored text;
begin
  if coalesce(p_location, '') = '' or coalesce(p_secret, '') = '' then
    return null;
  end if;

  insert into list_puncher.tenants (location_id, secret_hash, last_seen_at)
  values (p_location, v_hash, now())
  on conflict (location_id) do update set last_seen_at = now()
  returning secret_hash into v_stored;

  if v_stored is distinct from v_hash then
    return null;   -- someone else's secret already owns this location
  end if;
  return v_stored;
end;
$$;

create or replace function list_puncher.get_list(p_location text, p_project text, p_secret text)
returns table (checklist_text text, updated_at timestamptz)
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
begin
  -- Wrong or missing secret returns nothing, which is indistinguishable from "no list".
  if list_puncher.ensure_tenant(p_location, p_secret) is null then
    return;
  end if;

  return query
    select l.checklist_text, l.updated_at
    from list_puncher.legacy_list_blobs l
    where l.location_id = p_location
      and l.project_id  = p_project
    limit 1;
end;
$$;

create or replace function list_puncher.upsert_list(p_location text, p_project text, p_secret text, p_text text)
returns timestamptz
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_now timestamptz := now();
begin
  if list_puncher.ensure_tenant(p_location, p_secret) is null then
    raise exception 'invalid tenant secret' using errcode = '28000';
  end if;

  insert into list_puncher.legacy_list_blobs (location_id, project_id, checklist_text, updated_at)
  values (p_location, p_project, coalesce(p_text, ''), v_now)
  on conflict (location_id, project_id)
  do update set checklist_text = excluded.checklist_text,
                updated_at     = excluded.updated_at;

  return v_now;
end;
$$;

-- Used by the "move my lists to my own Supabase" upgrade: wipes this tenant's row from
-- the hub once it has been pushed to the client's own project.
create or replace function list_puncher.delete_list(p_location text, p_project text, p_secret text)
returns boolean
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_count integer;
begin
  if list_puncher.ensure_tenant(p_location, p_secret) is null then
    raise exception 'invalid tenant secret' using errcode = '28000';
  end if;

  delete from list_puncher.legacy_list_blobs
  where location_id = p_location and project_id = p_project;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- anon may ONLY call the tenant-facing functions; the helpers stay private.
revoke all on function list_puncher.hash_secret(text) from public, anon, authenticated;
revoke all on function list_puncher.ensure_tenant(text, text) from public, anon, authenticated;
grant execute on function list_puncher.get_list(text, text, text) to anon, authenticated;
grant execute on function list_puncher.upsert_list(text, text, text, text) to anon, authenticated;
grant execute on function list_puncher.delete_list(text, text, text) to anon, authenticated;

commit;

-- -----------------------------------------------------------------------------
-- PHASE 2 - removes the "anyone with the publishable key can read/write/delete" hole.
-- APPLIED to the agency project on 2026-10-24 (migration phase2_lock_table_and_add_ping)
-- after Phase 1B was verified and the real row had been re-pushed by the app.
--
-- From here on the ONLY way into list_puncher.legacy_list_blobs is the tenant functions: anon and
-- authenticated hold no table privileges at all and RLS has no policies, so
-- GET /rest/v1/legacy_list_blobs answers 401 while POST /rest/v1/rpc/get_list still works.
-- -----------------------------------------------------------------------------
begin;

revoke all on list_puncher.legacy_list_blobs from anon, authenticated;
drop policy if exists lists_anon_all on list_puncher.legacy_list_blobs;

-- Health check for the daily keep-alive workflow (it used to probe /rest/v1/legacy_list_blobs,
-- which is now closed). Returns the server clock, writes nothing, leaks nothing.
create or replace function list_puncher.ping()
returns timestamptz
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select now();
$$;

revoke all on function list_puncher.ping() from public;
grant execute on function list_puncher.ping() to anon, authenticated;

commit;

-- ROLLBACK (only if something still needs the old table path - it re-opens the hole):
--   grant usage on schema list_puncher to anon, authenticated;
--   grant select, insert, update on list_puncher.legacy_list_blobs to anon, authenticated;
--   create policy lists_anon_all on list_puncher.legacy_list_blobs for all to anon, authenticated
--     using (true) with check (true);

-- Verify (expect 5 functions, and NO grant rows for anon/authenticated on any table):
--   select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'list_puncher' order by proname;
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema = 'list_puncher' order by table_name, grantee;
--   select relname, relrowsecurity, (select count(*) from pg_policy
--     where polrelid = c.oid) as policies
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'list_puncher' and relkind = 'r';


-- =============================================================================
-- PHASE 1B - SECURITY FIX (run AFTER Phase 1; safe to re-run)
-- -----------------------------------------------------------------------------
-- Phase 1 registered a tenant on first use keyed ONLY by location_id, so whoever
-- called first "owned" that location and could then read its existing row.
-- Now every list row carries the hash of the tenant that wrote it, and tenants are
-- keyed by (location_id, secret_hash), so an impostor who claims a location can
-- only reach rows carrying their own hash - i.e. none.
--
-- APPLIED to the agency project (dhuhkinuruxbwddhffwk) on 2026-10-24 as migrations
--   phase1b_backup_snapshot / phase1b_tenant_hash_isolation.
-- This block is what ran, verbatim: every DDL step is guarded so a second run is a
-- no-op instead of "constraint already exists".
-- =============================================================================

-- 0. safety copies - TAKEN ON THE LIVE PROJECT, NOT HERE.
--    The applied migration created `lists_backup_pre1b` / `tenants_backup_pre1b`; both were dropped on
--    2026-10-26 after being confirmed unreferenced (the live blob rows had superseded their content).
--    A fresh rebuild has nothing to snapshot yet, so this script no longer recreates them.

begin;

-- 1. tenants: several rows per location (one per secret); "first caller wins" is gone
alter table list_puncher.tenants drop constraint if exists tenants_pkey;
alter table list_puncher.tenants drop constraint if exists tenants_location_id_secret_hash_key;
delete from list_puncher.tenants;

do $do$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'list_puncher.tenants'::regclass and contype = 'p'
  ) then
    alter table list_puncher.tenants add primary key (location_id, secret_hash);
  end if;
end
$do$;

-- 2. lists: tag each row with the tenant that wrote it
alter table list_puncher.legacy_list_blobs add column if not exists tenant_hash text;
alter table list_puncher.legacy_list_blobs drop constraint if exists lists_location_id_project_id_key;
delete from list_puncher.legacy_list_blobs where tenant_hash is null;   -- pre-fix row; the app re-pushes it
alter table list_puncher.legacy_list_blobs alter column tenant_hash set not null;

do $do$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'list_puncher.legacy_list_blobs'::regclass
      and conname  = 'lists_location_project_tenant_key'
  ) then
    alter table list_puncher.legacy_list_blobs
      add constraint lists_location_project_tenant_key
      unique (location_id, project_id, tenant_hash);
  end if;
end
$do$;

-- 3. register = insert-if-absent, and always return the caller's OWN hash
create or replace function list_puncher.ensure_tenant(p_location text, p_secret text)
returns text
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_hash text := list_puncher.hash_secret(p_secret);
begin
  if coalesce(p_location, '') = '' or coalesce(p_secret, '') = '' then
    return null;
  end if;

  insert into list_puncher.tenants (location_id, secret_hash, last_seen_at)
  values (p_location, v_hash, now())
  on conflict (location_id, secret_hash) do update set last_seen_at = now();

  return v_hash;
end;
$$;

create or replace function list_puncher.get_list(p_location text, p_project text, p_secret text)
returns table (checklist_text text, updated_at timestamptz)
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_hash text := list_puncher.ensure_tenant(p_location, p_secret);
begin
  if v_hash is null then
    return;
  end if;

  return query
    select l.checklist_text, l.updated_at
    from list_puncher.legacy_list_blobs l
    where l.location_id = p_location
      and l.project_id  = p_project
      and l.tenant_hash = v_hash
    limit 1;
end;
$$;

create or replace function list_puncher.upsert_list(p_location text, p_project text, p_secret text, p_text text)
returns timestamptz
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_hash text := list_puncher.ensure_tenant(p_location, p_secret);
  v_now  timestamptz := now();
begin
  if v_hash is null then
    raise exception 'invalid tenant secret' using errcode = '28000';
  end if;

  insert into list_puncher.legacy_list_blobs (location_id, project_id, tenant_hash, checklist_text, updated_at)
  values (p_location, p_project, v_hash, coalesce(p_text, ''), v_now)
  on conflict (location_id, project_id, tenant_hash)
  do update set checklist_text = excluded.checklist_text,
                updated_at     = excluded.updated_at;

  return v_now;
end;
$$;

create or replace function list_puncher.delete_list(p_location text, p_project text, p_secret text)
returns boolean
language plpgsql
security definer
set search_path = list_puncher, pg_temp
as $$
declare
  v_hash  text := list_puncher.ensure_tenant(p_location, p_secret);
  v_count integer;
begin
  if v_hash is null then
    raise exception 'invalid tenant secret' using errcode = '28000';
  end if;

  delete from list_puncher.legacy_list_blobs
  where location_id = p_location
    and project_id  = p_project
    and tenant_hash = v_hash;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

commit;


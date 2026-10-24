-- =============================================================================
-- LIST PUNCHER - AGENCY HUB
-- One project, many clients, REAL tenant isolation, zero setup for a new client.
-- -----------------------------------------------------------------------------
-- How it works
--   * each GHL sub-account (location) gets its own random secret, stored as the GHL
--     custom value "list_puncher_secret" so every device in that sub-account has it
--   * the secret is never trusted to Row Level Security (Postgres cannot see request
--     headers/params), so SECURITY DEFINER functions verify it and only ever touch
--     that one tenant's row
--   * anon gets NO table privileges - only EXECUTE on the functions below, so direct
--     REST access to list_puncher.lists becomes impossible
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
    from list_puncher.lists l
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

  insert into list_puncher.lists (location_id, project_id, checklist_text, updated_at)
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

  delete from list_puncher.lists
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
-- PHASE 2 - run ONLY after the RPC build of the app is live and verified.
-- This removes the "anyone with the publishable key can read/write/delete" hole.
-- -----------------------------------------------------------------------------
-- begin;
-- revoke all on list_puncher.lists from anon, authenticated;
-- drop policy if exists lists_anon_all on list_puncher.lists;
-- commit;

-- Verify (expect 4 functions, and no anon grants on the two tables):
--   select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'list_puncher' order by proname;
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema = 'list_puncher' order by table_name, grantee;


-- =============================================================================
-- PHASE 1B - SECURITY FIX (run AFTER Phase 1; safe to re-run)
-- -----------------------------------------------------------------------------
-- Phase 1 registered a tenant on first use keyed ONLY by location_id, so whoever
-- called first "owned" that location and could then read its existing row.
-- Now every list row carries the hash of the tenant that wrote it, and tenants are
-- keyed by (location_id, secret_hash), so an impostor who claims a location can
-- only reach rows carrying their own hash - i.e. none.
-- =============================================================================

begin;

-- 1. tenants: several rows per location (one per secret); "first caller wins" is gone
alter table list_puncher.tenants drop constraint if exists tenants_pkey;
delete from list_puncher.tenants;
alter table list_puncher.tenants add primary key (location_id, secret_hash);

-- 2. lists: tag each row with the tenant that wrote it
alter table list_puncher.lists add column if not exists tenant_hash text;
alter table list_puncher.lists drop constraint if exists lists_location_id_project_id_key;
delete from list_puncher.lists where tenant_hash is null;   -- pre-fix row; the app re-pushes it
alter table list_puncher.lists alter column tenant_hash set not null;
alter table list_puncher.lists
  add constraint lists_location_project_tenant_key unique (location_id, project_id, tenant_hash);

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
    from list_puncher.lists l
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

  insert into list_puncher.lists (location_id, project_id, tenant_hash, checklist_text, updated_at)
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

  delete from list_puncher.lists
  where location_id = p_location
    and project_id  = p_project
    and tenant_hash = v_hash;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

commit;


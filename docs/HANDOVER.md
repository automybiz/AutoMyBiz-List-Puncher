# HANDOVER — List Puncher (read this first)

Kickoff for a new Cline task:

> **Read `docs/HANDOVER.md`, then do the CURRENT TASK section.**

---

## 1. Snapshot

| | |
|---|---|
| Repo | `github.com/automybiz/AutoMyBiz-List-Puncher` (public, branch `main`) |
| Local | `x:\DATA\_SOFTWARE\_3D_PRINTING\_PROJECTS\_WEB\CODE\AutoMyBiz List Puncher` |
| App | single-file `index.html` + `index.css`, served by GitHub Pages, embedded in GoHighLevel via a Custom Menu Link |
| Build | **1.30** (`APP_BUILD`, `index.css?v=`, `--lp-css-build` — keep all three in sync) |
| Database | Supabase project ref `dhuhkinuruxbwddhffwk` (org AutoMyBiz, us-west-2, free plan), schema `list_puncher` |
| Product goal | zero-touch onboarding per GHL sub-account (agency hosts the data, per-tenant isolation), with an optional upgrade path to a client's own Supabase project |

## 2. How cloud sync works right now

`resolveCloudTarget()` runs once at startup and picks the Supabase target, first hit wins:

1. URL params `?sb_url=&sb_key=` 2. this browser (`list_puncher_<loc>_cloud_target`)
3. the sub-account's GHL custom values `list_puncher_supabase_url` / `_key`
4. `LEGACY_FALLBACK_CLOUD` (the agency pilot project — meant to be nulled once every sub-account is migrated)

Then `finalizeCloudTarget()` resolves a **tenant secret** (link param `lp_secret` → browser → GHL custom value `list_puncher_secret` → mint 32 random bytes and publish via the PIT) and picks a mode:

- **`rpc`** (agency hub): calls `get_list` / `upsert_list` with `(p_location, p_project, p_secret, p_text)`. Row-level isolation via `tenant_hash`.
- **`table`** (a client's own project): plain REST on `list_puncher.lists`; used automatically when the RPC functions are absent (`PGRST202`).

Permissions: `evaluatePermissions()` reads editors/viewers from the link param → GHL custom values (`list_puncher_editors` / `_viewers`) → defaults `ADMINS` / `ALL`.

## 3. Database state at this handover

| Item | State |
|---|---|
| `list_puncher.lists` | exists; text column is **`checklist_text`** (renamed from `yaml`, no legacy fallback in the app) |
| `list_puncher.tenants` | exists, **PK on `location_id` only** (Phase 1) — will change in Phase 1B |
| Functions | Phase 1 versions of `hash_secret`, `ensure_tenant`, `get_list`, `upsert_list`, `delete_list` (all `SECURITY DEFINER` except `hash_secret`) |
| **Phase 1B** | ❌ **NOT APPLIED — this is the current task** |
| Phase 2 | ❌ not applied (correct: it depends on 1B) |
| Policy `lists_anon_all` | still active: `FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)` |
| `lists` rows | 1 row: `A9eEmuUJ1FM6sBhYESfO` / `default_onboarding`, 20,400 bytes |

### Why Phase 1B matters
Phase 1's `ensure_tenant` registers a tenant keyed **only by `location_id`, on first use**, so whoever calls first "owns" that location and can read its existing row. This was reproduced live: `get_list` with a junk secret against the real location returned the full list. Phase 1B tags every row with the writer's `tenant_hash` and keys tenants by `(location_id, secret_hash)`.

## 4. CURRENT TASK — apply Phase 1B, verify, report

**Step 1 — safety copy** (run alone):
```sql
create table if not exists list_puncher.lists_backup_pre1b as select * from list_puncher.lists;
```

**Step 2 —** run the block under the header `PHASE 1B - SECURITY FIX` in `supabase/setup-agency-hub.sql`. It:
- drops `tenants_pkey`, clears `tenants`, adds PK `(location_id, secret_hash)`
- adds `lists.tenant_hash`, drops the old `lists_location_id_project_id_key`, deletes the untagged row, sets `tenant_hash NOT NULL`, adds `lists_location_project_tenant_key UNIQUE (location_id, project_id, tenant_hash)`
- replaces `ensure_tenant` (insert-if-absent, returns the caller's own hash) and adds `tenant_hash` filtering to `get_list` / `upsert_list` / `delete_list`

**Step 3 — verify (no MCP needed; use the publishable key from `index.html`)**

```powershell
# wrong secret against the real location MUST now return []
$h = Get-Content 'index.html' -Raw
$key = [regex]::Match($h, "key: '(sb_publishable_[^']+)'").Groups[1].Value
Invoke-WebRequest -Uri 'https://dhuhkinuruxbwddhffwk.supabase.co/rest/v1/rpc/get_list' -Method POST `
  -Headers @{ apikey=$key; 'Accept-Profile'='list_puncher'; 'Content-Profile'='list_puncher'; 'Content-Type'='application/json' } `
  -Body '{"p_location":"A9eEmuUJ1FM6sBhYESfO","p_project":"default_onboarding","p_secret":"WRONG"}' -UseBasicParsing | Select-Object -Expand Content
```

| Check | Expect |
|---|---|
| wrong-secret `get_list` | `[]` (before the fix it returned the whole list) |
| constraints | `lists_location_project_tenant_key UNIQUE (location_id, project_id, tenant_hash)` + `lists_pkey` |
| `tenants` | empty until the app next calls it |
| after the user opens List Puncher (v1.30) | 1 `lists` row with `tenant_hash IS NOT NULL` and ~20,400 bytes |

**Step 4 — report** what changed and the verification output. If any DDL call fails with
`403 … after trying upscoping`, the OAuth grant is still read-only — see §6.

## 5. After Phase 1B, in this order

1. **Phase 2** (`supabase/setup-agency-hub.sql`, commented block): `revoke all on list_puncher.lists from anon, authenticated;` + `drop policy if exists lists_anon_all`. Then verify the same REST probe now returns `401`/permission denied, and that `rpc/get_list` still works with the right secret. This is the actual security win.
2. **Client #2 onboarding** (should be zero-touch): create the GHL sub-account → ensure its `automybiz_api_token` custom value holds a PIT → open List Puncher once. It mints a tenant secret, registers `(location_id, hash)`, and seeds its row.
3. **Bootstrap punch list** (`docs/BOOTSTRAP.md`): the whole setup written in List Puncher's own checklist format so a new machine + new Supabase project can be provisioned in minutes. Include the OAuth traps below.

## 6. Environment / MCP facts

- MCP server entry name: `supabase`
  `https://mcp.supabase.com/mcp?project_ref=dhuhkinuruxbwddhffwk&features=database%2Cdocs%2Cdebugging`
  (no `read_only`; `account`/`development` intentionally excluded)
- OAuth grant: READ+WRITE to org **AutoMyBiz**. Tokens live in
  `~/.cline/data/settings/cline_mcp_settings.json` (mirrored into the extension's globalStorage config)
- Tools bind at **task start**. If calls fail with `No connection found for server: supabase`, start a new task.
- `autoApprove` is empty: every call needs a user click.
- Read-only mode is one URL param away (`&read_only=true`) if you ever want to lock it down again.

## 7. Traps already hit — do not rediscover these

| Symptom | Cause / fix |
|---|---|
| `Authenticate` opens no browser | VS Code `openExternal` fails here. Drive OAuth manually: run a small node listener on `127.0.0.1:1456`, use Cline's stored `client_id` / `client_secret` / `codeVerifier`, build the authorize URL with the S256 challenge, capture `?code=`, POST it to `https://api.supabase.com/v1/oauth/token`, then write `oauth.tokens` into the config |
| `OAuth authorization failed: state mismatch` | Injecting your own `state` into **Cline's** flow — Cline validates it. Only work when *your own listener* receives the callback |
| `422 Unrecognized client_id` | Stale cached client registration → delete the `oauth` block and re-register |
| `403 … after trying upscoping` | The grant is read-only; the `read_only` URL param only *requests*, never *grants*. Revoke + re-authorize with write scopes |
| `<ref>.supabase.co` NXDOMAIN | The project ref is exactly **20 characters**; a 19-char typo makes the hostname not exist. Always copy it, never transcribe |
| REST 404 on `lists` | `list_puncher` must be in **Settings → Data API → Exposed schemas**, and every request needs `Accept-Profile` / `Content-Profile: list_puncher` |
| 401 on REST | Wrong key type: publishable keys go on `apikey` only (never `Authorization: Bearer`); legacy anon JWTs go on both |
| Free project pauses | 7 days inactivity → `list_puncher` goes offline. `.github/workflows/supabase-keepalive.yml` pings every project in `.github/supabase-keepalive-targets.json` daily; GitHub disables scheduled workflows after 60 days of repo inactivity |

## 8. File map

```
index.html                                  app (build markers at the top)
index.css                                   styles (--lp-css-build at the top)
supabase/setup-agency-hub.sql               agency-hub schema: Phase 1, Phase 1B, Phase 2 (commented)
supabase/setup-client-project.sql           one-paste setup for a client's OWN project
docs/CLIENT-SUPABASE-SETUP.md               the two modes + per-client walkthrough
docs/HANDOVER.md                            this file
.github/workflows/supabase-keepalive.yml    daily ping for every project in the targets JSON
.github/supabase-keepalive-targets.json     [{name, url, key}] — publishable keys only
```

## 9. House rules

- Never put a **secret** key (`sb_secret_…`) in the page; `normalizeCloudTarget()` rejects it on purpose.
- Only **publishable** keys go in `index.html` and the keep-alive targets file (both are public).
- Don't run Phase 2 until Phase 1B is verified.
- `checklist_text` only — no legacy `yaml` fallback.
- Keep `APP_BUILD`, `index.css?v=` and `--lp-css-build` identical, and verify with `node --check` on the extracted inline script before committing.
- Update this file when the state changes.


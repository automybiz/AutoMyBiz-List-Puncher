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
| `list_puncher.lists` | exists; text column is **`checklist_text`** (renamed from `yaml`, no legacy fallback in the app); **`tenant_hash text NOT NULL`**; constraints `lists_pkey (id)` + `lists_location_project_tenant_key UNIQUE (location_id, project_id, tenant_hash)` |
| `list_puncher.tenants` | exists, **PK `tenants_pkey (location_id, secret_hash)`** (Phase 1B) — one row per secret, so "first caller wins" is gone |
| Functions | `hash_secret`, `ensure_tenant` (insert-if-absent, returns the caller's own hash), `get_list` / `upsert_list` / `delete_list` (all filter on `tenant_hash`; `SECURITY DEFINER` except `hash_secret`), plus **`ping()`** → `now()` for the keep-alive workflow |
| **Phase 1B** | ✅ applied + verified 2026-10-24 (`phase1b_backup_snapshot`, `phase1b_tenant_hash_isolation`) |
| **Phase 2** | ✅ applied + verified 2026-10-24 (`phase2_lock_table_and_add_ping`) — table access revoked, `lists_anon_all` dropped |
| Table grants | **none** for `anon` / `authenticated` on any `list_puncher` table; RLS on all four tables, **zero policies** → `GET /rest/v1/lists` answers `401 permission denied` (`42501`) |
| Backups | `lists_backup_pre1b` (1 row, 20,400 bytes, `A9eEmuUJ1FM6sBhYESfO` / `default_onboarding`) and `tenants_backup_pre1b` (2 rows) — RLS on, no grants |
| `lists` rows | **1**: `A9eEmuUJ1FM6sBhYESfO` / `default_onboarding`, `tenant_hash` = `530bdffbfb1f…`, 20,400 bytes, byte-identical to the backup — re-pushed by the app 13:43 UTC after 1B |
| `tenants` rows | **1**: `(A9eEmuUJ1FM6sBhYESfO, 530bdffbfb1f…)` — the browser's real secret, registered/proven by that push |

### Why Phase 1B matters
Phase 1's `ensure_tenant` registers a tenant keyed **only by `location_id`, on first use**, so whoever calls first "owns" that location and can read its existing row. Reproduced live: `get_list` with a junk secret against the real location returned the full list (the pre-1B `tenants` row for `A9eEmuUJ1FM6sBhYESfO` hashed to `sha256('WRONG')`, i.e. the probe secret had claimed the location, which is why the real app could never read its own row). Phase 1B tags every row with the writer's `tenant_hash` and keys tenants by `(location_id, secret_hash)`.

## 4. Phase 1B — DONE (applied + verified 2026-10-24)

Applied through the `supabase` MCP as two migrations, both safe to re-run:

| Migration | What it did |
|---|---|
| `phase1b_backup_snapshot` | `list_puncher.lists_backup_pre1b` (1 row, 20,400 bytes) + `list_puncher.tenants_backup_pre1b` (2 rows); RLS on, `anon` / `authenticated` revoked |
| `phase1b_tenant_hash_isolation` | the `PHASE 1B - SECURITY FIX` block of `supabase/setup-agency-hub.sql` — same text as the file, including the `if not exists` guards on both `add constraint`s and the `tenants` PK |

Result: `tenants` PK `(location_id, secret_hash)`; `lists.tenant_hash text NOT NULL`;
`lists_location_id_project_id_key` dropped; `lists_location_project_tenant_key UNIQUE
(location_id, project_id, tenant_hash)` added; `ensure_tenant` / `get_list` / `upsert_list` /
`delete_list` replaced; the untagged pre-1B row deleted (it is in the backup).

### Verification log (publishable key from `index.html`, plain REST — no MCP)

```powershell
$h = Get-Content 'index.html' -Raw
$key = [regex]::Match($h, "key: '(sb_publishable_[^']+)'").Groups[1].Value
$hdrs = @{ apikey=$key; 'Accept-Profile'='list_puncher'; 'Content-Profile'='list_puncher'; 'Content-Type'='application/json' }
Invoke-WebRequest -Uri 'https://dhuhkinuruxbwddhffwk.supabase.co/rest/v1/rpc/get_list' -Method POST `
  -Headers $hdrs -Body '{"p_location":"A9eEmuUJ1FM6sBhYESfO","p_project":"default_onboarding","p_secret":"WRONG"}' -UseBasicParsing
```

| Probe | Result |
|---|---|
| `get_list` real location + secret `WRONG` | `200 []` — before 1B this returned the whole 20,400-byte list |
| `get_list` real location + empty secret | `200 []` |
| `get_list` unknown location | `200 []` |
| `upsert_list` `P1B_SELFTEST` / `secret-alpha` | `2026-10-24T13:28:25.539784+00:00` |
| `get_list` `P1B_SELFTEST` / `secret-alpha` | `[{"checklist_text":"section: self test",…}]` |
| `get_list` `P1B_SELFTEST` / `secret-bravo` | `[]` ← the isolation fix |
| `get_list` `P1B_SELFTEST` / junk | `[]` |
| `GET /rest/v1/lists` (direct table) | `200 []` **at 1B time** — still open then; closed in §4c |
| Phase 1B block re-run inside `begin … rollback` | no errors → the guards make it idempotent |

All probe rows were deleted afterwards (`P1B_SELFTEST`, `NO_SUCH_LOCATION`, `ALPHATEST1`, plus
the `sha256('WRONG')` tenant on the real location). That left `lists` / `tenants` empty until the
app re-pushed — see §4b.

### Advisor baseline after Phase 2 (`get_advisors security`)

| Lint | Status |
|---|---|
| `anon_security_definer_function_executable` ×4 | **expected** — `get_list` / `upsert_list` / `delete_list` / `ping` *are* the API |
| `authenticated_security_definer_function_executable` ×4 | same, for the signed-in role |
| `rls_enabled_no_policy` ×4 (all four tables) | **expected** — no policies on purpose, no table grants at all |
| `function_search_path_mutable` (`hash_secret`) | cosmetic; fixing it means `create or replace … set search_path = pg_catalog, pg_temp` |
| `lists_anon_all` (`USING true`) | ✅ **gone** (Phase 2) |

## 4b. Re-seed — DONE 2026-10-24 13:43 UTC

Phase 1B deleted the untagged row, so the browser had to re-push it. The app was opened
(hard refresh) in the browser that already held the list, in the `Europe Parts West`
sub-account (`A9eEmuUJ1FM6sBhYESfO`); pill `☁ Synced`. `hydrateFromCloud()` saw "no cloud row,
local text present" and called `scheduleCloudSave(localText)`, which registered
`(location, sha256(real secret))` and upserted through the RPC.

| Check | Result |
|---|---|
| `lists` | 1 row, `tenant_hash` = `530bdffbfb1f…`, **20,400 bytes**, `checklist_text` **byte-identical to `lists_backup_pre1b`** |
| `tenants` | 1 row `(A9eEmuUJ1FM6sBhYESfO, 530bdffbfb1f…)`, created 13:43:36, last seen 13:46:06 |
| mode used | RPC (`tenant_hash` was populated; a plain-REST insert would have failed `NOT NULL`) |

⚠️ Order still matters on a *new* tenant: a browser with no local copy, opened while the row is
absent, runs `seedOnboardingBlueprint()` and pushes the starter list. The backup table is the
undo button.

## 4c. Phase 2 — DONE (applied + verified 2026-10-24)

Migration `phase2_lock_table_and_add_ping`: `revoke all on list_puncher.lists from anon,
authenticated` + `drop policy lists_anon_all` + new `list_puncher.ping()` (executable by anon,
returns `now()`, writes nothing).

| Probe | Result |
|---|---|
| `GET /rest/v1/lists?select=id` (publishable key) | **`401`** `{"code":"42501","message":"permission denied for table lists"}` ← the hole is closed |
| `POST /rest/v1/rpc/ping` (`Content-Profile: list_puncher`) | `200` `"2026-10-24T13:49:03.013753+00:00"` |
| `POST /rest/v1/rpc/get_list` real location + `WRONG` | `200 []` |
| `POST /rest/v1/rpc/get_list` junk location | `200 []` |
| grants for `anon` / `authenticated` | **none** on any `list_puncher` table |
| RLS / policies | `lists`, `tenants`, both backups: RLS on, **0 policies** |

Rollback (re-opens the hole, kept in `setup-agency-hub.sql`): re-grant
`select/insert/update` + recreate `lists_anon_all`.

Also fixed in the same pass: `.github/workflows/supabase-keepalive.yml` used to probe
`/rest/v1/lists`, which is now `401`. It now POSTs `rpc/ping` and only falls back to the table
probe when that answers `404` (a client's own project). A POST selects its schema with
**`Content-Profile`** — `Accept-Profile` alone makes PostgREST look in `public` and answer
`PGRST202`.

## 5. CURRENT TASK — client #2, then bootstrap

1. **Client #2 onboarding** (should be zero-touch): create the GHL sub-account → ensure its `automybiz_api_token` custom value holds a PIT → open List Puncher once. It mints a tenant secret, registers `(location_id, hash)`, and seeds its row. Then confirm from the DB side that it produced exactly one `tenants` row + one `lists` row for the new `location_id`, and that `get_list` with a junk secret against it returns `[]`.
2. **Bootstrap punch list** (`docs/BOOTSTRAP.md`): the whole setup written in List Puncher's own checklist format so a new machine + new Supabase project can be provisioned in minutes. Include the OAuth traps below.

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
| Direct table insert fails `null value in column "tenant_hash"` | Expected after Phase 1B — hub rows are only written by `upsert_list`. `'table'` mode (plain REST, no `tenant_hash`) must never point at the agency hub, only at a client's own project |
| `401 {"code":"42501","message":"permission denied for table lists"}` | **Correct after Phase 2** — use `POST /rest/v1/rpc/get_list` |
| `PGRST202 Could not find the function public.<name>` on an RPC | A POST picks its schema from **`Content-Profile`**; `Accept-Profile` alone leaves it in `public`. Send `Content-Profile: list_puncher` (GET requests use `Accept-Profile`) |
| A browser stuck on `☁ Offline` while others sync fine | That profile has `list_puncher_cloud_mode_<url> = 'table'` cached (from the pre-RPC era). Table mode now gets `401`; clear that key or add a fallback that reverses the mode on `401/403` (app change, build 1.31) |
| Hub sync works but the list came back as the starter blueprint | A device with no local copy opened the app before the original browser re-pushed the row (§4b step 1); recover the text from `list_puncher.lists_backup_pre1b` |
| Free project pauses | 7 days inactivity → `list_puncher` goes offline. `.github/workflows/supabase-keepalive.yml` pings every project in `.github/supabase-keepalive-targets.json` daily; GitHub disables scheduled workflows after 60 days of repo inactivity |

## 8. File map

```
index.html                                  app (build markers at the top)
index.css                                   styles (--lp-css-build at the top)
supabase/setup-agency-hub.sql               agency-hub schema: Phase 1, Phase 1B (applied), Phase 2 (commented)
                                            → also creates list_puncher.lists_backup_pre1b / tenants_backup_pre1b
supabase/setup-client-project.sql           one-paste setup for a client's OWN project
docs/CLIENT-SUPABASE-SETUP.md               the two modes + per-client walkthrough
docs/HANDOVER.md                            this file
.github/workflows/supabase-keepalive.yml    daily ping: POST rpc/ping (agency hub), table probe fallback (client projects)
.github/supabase-keepalive-targets.json     [{name, url, key}] — publishable keys only
```

## 9. House rules

- Never put a **secret** key (`sb_secret_…`) in the page; `normalizeCloudTarget()` rejects it on purpose.
- Only **publishable** keys go in `index.html` and the keep-alive targets file (both are public).
- Phase 1B **and** Phase 2 are applied and verified. The hub is RPC-only: never `grant` table privileges or recreate `lists_anon_all` on it. Client-owned projects are the opposite — they *need* the table grant (`setup-client-project.sql`).
- `checklist_text` only — no legacy `yaml` fallback.
- Keep `APP_BUILD`, `index.css?v=` and `--lp-css-build` identical, and verify with `node --check` on the extracted inline script before committing.
- Update this file when the state changes.


---

## 10. Build 1.32 - three-state tasks (2026-10-24)

The checkbox is now YES / NO / BLANK. `[x]` no longer means done.

| Marker | State | Meaning |
|---|---|---|
| `[ ]` | `blank` | untouched / undecided |
| `[v]` | `yes` | approved / done |
| `[x]` | `no` | rejected / ignored - kept in the list, struck through in `#F50` |

- **Format stamp.** Every saved list starts with `# lp-format: 2`. Text *without* the stamp is v1 and gets `[x]` rewritten to `[v]` exactly once, inside `parseYamlToTasks` (so local load, cloud pull and paste all migrate).
- **Model.** `task.checked` -> `task.state`. `taskState(task)` still reads a legacy `checked` boolean so blueprint/seed/cached data keeps working.
- **Render.** Native checkbox replaced by `<button class="task-state">` (a checkbox cannot express three states). Click cycles blank -> yes -> no -> blank.
- **Bulk.** YesAll / NoAll / BlankAll, explicit set (not toggle), on milestone headers and on branch toolbars, each behind the confirm dialog. `confirmSectionState(idx, state)` / `confirmBranchState(idx, state)`.
- **Progress.** `yes / (total - no)`, with ` - N no` appended when anything is ignored. Sections count `allDone` the same way.
- **Parsers.** All `[ xX]` character classes widened to `[^\]]{0,3}` (4 detection helpers too, otherwise `[v]` lines were not recognised as tasks). Aliases accepted: `v y yes done approved ok true` and `x n no skip skipped ignored rejected false`.
- **Prompt.** The AI legend now documents the three markers and forbids `[x]` for done.

Verification used in this build (all green): `node --check` on the extracted inline script, a 23-assert state-contract harness, a 17-assert format/parse round-trip harness, and a 10-assert harness that parses `docs/BOOTSTRAP.md` and proves a lossless re-serialisation.

`docs/BOOTSTRAP.md` is the bootstrap punch list written in this format (7 sections, 74 items): paste it into List Puncher to get a working checklist.

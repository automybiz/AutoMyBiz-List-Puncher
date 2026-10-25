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
| Build | **1.38** (`APP_BUILD`, `index.css?v=`, `--lp-css-build` — keep all three in sync) |
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

### Read/write loop (build 1.38)

- **Write:** `saveState()` → `localStorage` (instant) → `scheduleCloudSave()` → 800 ms debounce → `flushCloudSaves()` → `upsert_list`. A failed push stays queued, retries every 15 s and on the browser `online` event.
- **Read:** `hydrateFromCloud(projId, announce)` is the **only** read path. It is called at load, on tab focus / `visibilitychange`, on a cross-tab `storage` event, and from `pollCloudOnce()` every **3 s** (`CLOUD_POLL_MS`) while the tab is visible and no dialog is open.
- **Conflict rule:** still last-write-wins, comparing the row's `updated_at` with this device's `localSavedAt`. §16 replaces it.
- **Pill:** `⚠ Cloud off` (no target) and `⚠ Not syncing` (target unreachable) are sticky red; `☁ Synced` flashes for 1.6 s after a real success.

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
| `lists` rows | **3** (2026-10-25 12:50 UTC), all location `A9eEmuUJ1FM6sBhYESfO`, all `tenant_hash` `530bdffbfb1f…`: `default_onboarding` 20,416 B (byte-identical to the backup apart from the re-push), `proj_supabase_setup_1792913084870` 2,690 B, `proj_supabase_setup_and_mcp_connection_1792913935559` 17,590 B |
| ⚠ Fallback trap | A `location_id` **with no GHL custom values still resolves to `LEGACY_FALLBACK_CLOUD`**, so an unknown/test sub-account writes straight into the AGENCY project. Verified the hard way on 2026-10-25: a headless-Chrome run with `?location_id=loc_test_138` created a real `lists` row + `tenants` row, which had to be deleted by hand. **When testing locally, always pass a bogus `sb_url` as well**, or you are writing to production. |
| `tenants` rows | **4**: `(A9eEmuUJ1FM6sBhYESfO, 530bdffbfb1f…)` — the real secret, registered/proven by that push — plus **3 leftover secrets for `default_subaccount`** (`8d0f21dd142d…`, `495440976386…`, `dd2a9dc75fdd…`, all created 2026-10-25 08:19–08:21 by local browser testing). They own no `lists` rows and are harmless; delete them whenever convenient. |

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
docs/SETUP-SUPABASE-MCP.md                  Supabase + VS Code MCP runbook, in list format - paste it into the app
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


---

## 11. Build 1.34 - new lists start empty, and say so (2026-10-25)

`+ New Project List...` used to seed `ONBOARDING_BLUEPRINT` into every new list, so a fresh list
opened showing the demo sections - which reads as "the previous list is still here". It now starts
genuinely empty and renders a guidance panel instead.

**The empty-list contract**

| Piece | Rule |
|---|---|
| `EMPTY_LIST_SENTINEL` | `# lp-empty: 1` - written to the project key instead of a blank string |
| Why a sentinel | the parser skips `#` comments (0 tasks) but the KEY EXISTS, which is how "deliberately empty" is told apart from "never opened on this device" |
| `loadCurrentProjectData()` | `rawYaml !== null` is authoritative: 0 tasks renders the empty state and STOPS |
| `saveState()` | writes the sentinel when `TASKS_DATA` is empty; skips the cloud push unless a row already exists |
| `hydrateFromCloud()` | `cloudWins = (!localExists OR cloudAt > localAt)` - an empty local list is a real answer, an absent one is not |

**Three traps that would have reappeared the moment lists stopped being seeded.** The first two
copied another list's tasks into the active project and then persisted it with `saveState()`:

1. the `list_puncher_yaml` legacy cross-key in `loadCurrentProjectData()` - now DEFAULT-list only;
2. `recoverStoredListFromAnyKey()` - adopts the richest `list_puncher_*_yaml` in the browser; now
   returns `false` unless `ACTIVE_PROJECT_ID === DEFAULT_PROJECT_ID`;
3. `saveState()` no longer writes the legacy cross-key while a user list is active, so the default
   list's backup survives a create.

**Header.** Removed the native `title` tooltip from the 📁 switcher (kept `aria-label` for screen
readers) and dropped the hardcoded `// Client Onboarding` breadcrumb - it lied whenever another
list was active, and the active name is already in the switcher pill.

**Empty state.** `buildEmptyStateHtml()` plus `.empty-state*` in `index.css`: three numbered cards
(build by hand / AI prompt + List Editor / reuse another list via the milestone and branch paste
buttons), each wired to the handlers that already existed.

Verification (all green): `node --check` on all three inline script blocks, CSS braces balanced, a
27-assert harness calling the real `promptCreateProject` / `loadCurrentProjectData` /
`switchActiveProject` / `seedOnboardingBlueprint` / `saveState` against an in-memory localStorage
(create -> reload -> switch back -> default-list recovery -> delete-all), and headless-Chrome
screenshots of both the empty state and the first-run blueprint.

---

## 12. Build 1.35 - an empty list reports 0 / 0 (2026-10-25)

`renderAll()` returns early for an empty list, and `updateProgress()` only ran at the bottom of that
function - so an empty list kept the previous list's readout ("7 / 13 Completed (54%)") above the
empty-state panel. The early return now calls `updateProgress()` as well.

**Reading the cloud table** (`list_puncher.lists` = one row per `location_id` + `project_id` +
`tenant_hash`). The 📁 switcher is built from `localStorage`, never from this table, so the row count
and the list count are unrelated:

| What you see | Why |
|---|---|
| 3 lists in the switcher | `PROJECTS_LIST` in `localStorage` - the table is never listed |
| 4 rows in `list_puncher.lists` | two sub-accounts: the real location id plus `default_subaccount` |
| Two rows with `project_id = default_onboarding` | different `location_id` (and different `tenant_hash`) - the unique key includes the location, so they are NOT duplicates |

`default_subaccount` is the fallback in
`LOCATION_ID = urlParams.get('location_id') || 'default_subaccount'` (index.html:455): any load
without `?location_id=` (a raw Pages visit, a `file://` open, a headless screenshot) mints its own
tenant there. Nothing under it can leak into a real sub-account, because `get_list` filters on
`location_id` **and** `project_id` **and** `tenant_hash`.


---

## 13. Build 1.36 - no more native dialogs (2026-10-25)

`window.prompt()` / `confirm()` / `alert()` render as OS dialogs inside the GHL iframe and cannot be
themed, so the list actions looked like a different product from the rest of the app. Everything in
that path now uses the app's own cards (the same shell as the milestone Check All confirmation):

| Action | Before | Now |
|---|---|---|
| New Project List... | `prompt()` | `#lpPromptModal`, name pre-filled |
| Rename Active List... | `prompt()` | same card, current name pre-selected |
| Delete Active List | `confirm()` | `openConfirmModal()` -> `CONFIRM_CONTEXT {type:'project'}` -> `deleteProjectList()` |
| + New Section | `prompt()` | same card, via `addNewSection()` |
| "paste a list first" / "could not read" | `alert()` | `showToast()` |

**Prompt engine.** `openTextPrompt({title, label, value, placeholder, okLabel, hintHtml, validate,
onSubmit})` plus `submitTextPrompt()` / `closeTextPrompt()` / `handlePromptKey(e)` /
`setPromptError(msg)`. Enter submits, Escape closes, an overlay click closes, the field is
pre-selected, and `validate` returns a string that is shown inline - a duplicate list name is refused
*while the card is still open* instead of silently returning `null`. New CSS: `.prompt-field`,
`.prompt-label`, `.prompt-input` (`.is-invalid`), `.prompt-hint`, `.prompt-error`,
`.btn-modal-primary`.

**Deleting a list now switches to another one.** `deleteProjectList()` drops the project's yaml + ui
keys, removes the entry from `PROJECTS_LIST`, makes `PROJECTS_LIST[0]` active and reloads. The old
inline code left the board pointing at the deleted list until the next switch.

Verification: 55-assert harness (the `prompt` / `confirm` / `alert` stubs now THROW, so any regression
fails the run instead of passing quietly), `node --check` on all three inline script blocks, CSS braces
balanced, and headless-Chrome screenshots of the card in both its clean and rejected-name states.


---

## 14. Build 1.37 - the list switcher sizes itself (2026-10-25)

The pill was capped at `max-width: 240px`, so every real list name was cut off with an ellipsis
("Supabase Setup and MC..."), and the menu was a fixed 250-320px. Both are now driven by one CSS
variable, `--lp-project-width`, which `applyProjectSwitcherWidth()` sets from the **longest** name in
`PROJECTS_LIST`:

- `renderProjectDropdownUI()` calls it on every load / switch / create / rename / delete.
- The name is measured in an off-screen `.project-measure` span using the pill label's own computed
  font (family / size / weight / letter-spacing), then `+ 64px` for the folder icon, caret and
  padding, capped at `PROJECT_SWITCHER_MAX_WIDTH` (430px).
- `.project-select-btn` and `.project-dropdown-menu` both use `width: var(--lp-project-width)`, so the
  menu is exactly as wide as the pill and long names wrap inside an item instead of being clipped.
  Measurement failures are swallowed - the CSS default (250px) still works.

Sizing from the **longest** name (not the active one) is deliberate: the pill never jumps when you
switch lists, and `PROJECTS_LIST` is the only source of truth for names anyway.

**Layout.** `.header-pills-cluster` is now a column: the switcher on the first row and the mode +
storage pills in a new `.header-status-row` beneath it. That frees the horizontal space the switcher
needed, and `.header-top`'s reserved gutter went from 560px to 470px, so the action buttons gained a
little room instead of losing it. Under 860px the cluster stays static and left-aligned.

Verification: `node --check` on all three inline script blocks, CSS braces balanced, and headless-Chrome
screenshots of the real app with a 31-character and a 54-character list name (both fit, pills on the
row below) plus a static render of the open menu proving it matches the pill's width.

## 15. Build 1.38 - the shared list keeps itself current (2026-10-25)

Two people on the same list now see each other's ticks with nobody alt-tabbing, and a dead Supabase
target is impossible to miss.

### Polling (not Realtime, and not instead of it)
`CLOUD_POLL_MS = 3000` drives `pollCloudOnce()` from `startCloudPolling()`, armed once in
`initCloudSync()` and re-armed by `resetCloudRuntime()` when the target changes. Each tick is
`hydrateFromCloud(ACTIVE_PROJECT_ID, false)` - the same function the focus/visibility handlers already
used, so there is exactly one read path.

A GHL iframe is a poor place to hold a WebSocket open, and Supabase's own troubleshooting guide says
Realtime delivery is not guaranteed across reconnects: *"treat the Realtime event as a signal to
re-fetch state - not as the only source of truth."* So polling is the read path either way; a Realtime
channel would only ever be a doorbell that shortens the delay below 3 s. Also: Realtime is **not
currently enabled** on `list_puncher.lists` (`pg_publication_tables` for `supabase_realtime` is empty),
and it would need the table added to the publication plus a `select` grant for the subscribing role.

Every reason to skip a tick lives in `pollCloudOnce()` / `listIsBusyForCloudPull()`, in one readable
block: hidden tab, `navigator.onLine === false`, push or pull already in flight, any of `yamlModal` /
`deleteModal` / `cloudSetupModal` open, `AUTOSAVE_TIMER` set, or a queued push (which is flushed first
and the pull deferred to the next tick).

### Why `deleteModal` blocks polling
`deleteModal` is the themed confirm card, and it holds `CONFIRM_CONTEXT` **indices** into `TASKS_DATA`
(`targetIndex` / `headerIdx` / `branchIdx` / `range`). Adopting a new cloud copy underneath it would
make "Confirm" delete the wrong row. Same reasoning for the YAML editor (unsaved copy of the list).

### The pill answers "is my work reaching the cloud?"
The failure states used to be drawn as `☁ Offline` / `☁ Not connected`, and 'offline' reverted after
6 s. Now `basePillState()` returns `⚠ Cloud off` (no Supabase target) and `⚠ Not syncing` (target
unreachable), both `status-restricted` (red, pulsing), and `setCloudStatus('offline')` writes them
**persistently** - only a real success clears them. `⚠` is used for every failure so the glyph itself
carries the meaning.

### Two bugs found while wiring this up
1. `executeAutoSave()` did `clearTimeout(AUTOSAVE_TIMER)` but never `AUTOSAVE_TIMER = null`.
   `clearTimeout` does not clear the handle, so "is a save still pending?" answered **yes forever**
   after the first keystroke - which silently disabled the cross-tab `storage` reload guard and would
   have disabled the poll gate too. Fixed.
2. `hydrateFromCloud()` called `setCloudStatus('synced')` unconditionally. At a 3 s cadence that
   re-flashed `☁ Synced` every tick. It now only fires when the status actually changes.

### Verification
- `node --check` equivalent (`new Function`) on all three inline script blocks: 3/3 compile.
- `$env:TEMP\lp-empty-list-test.js`: unchanged, exit 0, ALL CHECKS PASSED (no regression).
- `$env:TEMP\lp-poll-test.js`: **33 asserts, all pass** - extracts the real `pollCloudOnce`,
  `listIsBusyForCloudPull`, `startCloudPolling`, `stopCloudPolling`, `basePillState`, `setCloudStatus`
  and `executeAutoSave`, then drives all 8 skip-gates, the flush-before-pull ordering, all four pill
  states, and asserts no `☁ Offline` / `☁ Not connected` text survives anywhere.
- Headless Chrome against the real `index.html`: boots and renders normally; with
  `?sb_url=https://no-such-project.invalid` the DOM contains `<span id="pillText">⚠ Not syncing</span>`
  and the screenshot shows the red pill beside the mode pill.

### Conflict model - still unchanged
The read still resolves by comparing `remote.updated_at` with this device's `localSavedAt`
(`cloudWins = !localExists || cloudAt > localAt`). 1.38 does not change that; it shortens the window.
Removing the clock comparison only makes sense together with §16, which deletes it.

## 16. NEXT CHANGE (designed, not built) - one row per task

### The problem it removes
`lists.checklist_text` holds the **whole list** as one YAML string. Two people ticking different tasks
therefore produce two whole-list writes, and whichever lands second silently reverts the other's tick.
1.38 shortens the window to ~3 s; it does not remove the loss.

### Why this is cheaper than it looks
The page's model is **already a table**. Every item in `TASKS_DATA` is
`{ visible, id, parentId, level, order, state, title, notes }` (`parseStrictPuncherYaml` ~4770). The
YAML string is only a serialization of that array. So this change replaces the **transport**, not the
data model - `renderAll()`, progress, switcher, modals, empty state and the pill are untouched.

```
today:      TASKS_DATA (rows) -> YAML string -> 1 row in lists
row storage: TASKS_DATA (rows) -> diff -> N row upserts in tasks -> (other device) N rows -> TASKS_DATA
```
No blob exists anywhere on the page in the second pipeline. The blob survives only at the edges:
copy/paste, the YAML editor modal, import/export, AI output, and the GHL custom field - all
unchanged, because YAML is the *interchange* format (think CSV, not the database).

### Two prerequisites, both small
1. **Stable ids.** `generateSlugId('task', title, index)` derives the id from the title AND its
   position, so a rename or a reorder changes it - fatal for row identity. Ids must be generated once
   at creation (`crypto.randomUUID()`), then carried in the local cache and the DB.
2. **`parentId` must be authoritative.** The strict parser sets `parentId: ''` and encodes nesting
   with `level` + array order; user-created tasks DO set `parentId` (~3724). Derive `parentId` from the
   parser's `taskStack` so rows always have a parent.

Anything arriving as YAML has no ids, so it is an **import** (fresh ids) - correct, and paste therefore
replaces rather than merges. Anything else would be a guess.

### Schema
```sql
create table list_puncher.tasks (
  id             uuid primary key default gen_random_uuid(),  -- DB row identity, never reused
  location_id    text not null,
  project_id     text not null,
  tenant_hash    text not null,
  task_id        text not null,          -- OUR id: stable across rename / reorder / reload
  parent_task_id text,
  level          int  not null default 0,
  sort_order     int  not null default 0,
  state          text not null default 'blank',
  title          text not null default '',
  notes          text not null default '',
  visible        boolean not null default true,
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,            -- soft delete ONLY
  unique (location_id, project_id, tenant_hash, task_id)
);
```
Both ids on purpose: the uuid PK is the database's own (never reused, never sent); `task_id` is the
client's. Keeping `task_id` inside a composite unique (not as the PK) is what lets the same list - and
therefore the same `task_id`s - be **copied into another project**.

**Deletion is always explicit** (`deleted_at`), never inferred from absence. That single rule is what
prevents the classic "my copy didn't have row 9, so row 9 got deleted" data loss.

One RPC, `apply_task_changes(p_location, p_project, p_secret, p_changes jsonb)`: upsert the diff in
one transaction and **return the full current list**, so the pusher converges in the same round trip.
Different tasks touched by two people both survive; the same task is last-write-wins, which is the
correct semantic for one cell.

`EMPTY_LIST_SENTINEL` (`# lp-empty: 1`) disappears from the sync path - "empty" becomes "zero
non-deleted rows", which is what the sentinel was working around.

### Rollout (feature flag, NOT a fork - decided 2026-10-25)
`?storage=rows` switches the backend; no param keeps today's blob path byte-for-byte. Revert is a URL
change. A physical fork was rejected because two HTML files on the same origin share `localStorage` -
the fork would read and write the live app's keys - and every later build would have to be applied
twice.

- Local cache in rows mode: JSON **with ids** under a namespaced key (`list_puncher_rows_...`), never
  YAML, or every reload would regenerate ids and duplicate every row.
- Backfill: first open in rows mode with no rows -> read the existing YAML (local key, else
  `lists.checklist_text`), split into rows, write them. `lists` and the old keys stay untouched as the
  live backup.
- Seam (the only functions that swap): `loadCurrentProjectData`, `saveState`, `hydrateFromCloud`,
  `scheduleCloudSave`, `flushCloudSaves`, `saveFromEditor`.
- Once two-browser testing passes, flip the default and keep `?storage=blob` for one release.

### What this makes easy afterwards
- Realtime becomes genuinely cheap: one `postgres_changes` event = one row to apply, no merge problem.
- Presence ("👤 Bob is viewing") is safe to add - an indicator, never a lock. Locks were rejected:
  a closed laptop or an offline editor would lock everyone else out, and Google Sheets itself does not
  lock cells (it does operational transform plus presence).

### Also outstanding (from the original sync audit)
- `PROJECTS_LIST` (which lists exist) is still local-only, so a brand-new list made by Person A does
  not appear for Person B. Moving that directory to Supabase is a separate, smaller step.
- Unsent edits are still lost if the tab closes during the 800 ms debounce; the fix is a persisted
  per-project `pendingPush` flag, which the row design replaces with a persisted change set.


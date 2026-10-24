# Client Supabase setup (one project per GHL sub-account)

Each GHL sub-account gets its **own** Supabase project. That keeps one client's lists out of
another's database, and spreads the (free) project slots across client accounts instead of
paying for every project on one bill.

---

## Part 1 — Create the project (client, or you on their behalf)

1. Sign up at <https://supabase.com> (free plan, GitHub or email login, no card).
2. **New project**
   - Name: `List Puncher` (anything works — the app never reads the name)
   - Region: closest to that client. **Permanent choice.**
   - Database password: let Supabase generate it; you will not need it.
3. Wait ~2 minutes for provisioning.
4. **SQL Editor → New query** → paste the whole of
   [`supabase/setup-client-project.sql`](../supabase/setup-client-project.sql) → **Run**.
   Safe to re-run at any time.
5. **Project Settings → Data API → Exposed schemas** → add **`list_puncher`** → **Save**.
   (Skip this and every request returns 404 — the table lives outside `public`.)
6. **Project Settings → API Keys** → copy the **Publishable key** (`sb_publishable_…`).
   ⚠️ Never copy the **Secret** key (`sb_secret_…`) — it bypasses RLS entirely.
7. **Project Settings → General** → copy the **Project ID** (20 characters) or use
   `https://<project-id>.supabase.co`.

Send the agency two values: **project URL** + **publishable key**.

---

## Part 2 — Point the sub-account at it (agency)

The app resolves its target at startup, first hit wins:

| # | Source | Use when |
|---|---|---|
| 1 | URL params `&sb_url=…&sb_key=…` on the Custom Menu Link | quickest one-off, per-location links |
| 2 | This browser (set by the dialog) | testing on your own machine |
| 3 | **GHL custom values** `list_puncher_supabase_url` / `list_puncher_supabase_key` | **recommended** — every device in the sub-account inherits it |
| 4 | `LEGACY_FALLBACK_CLOUD` in `index.html` | the agency pilot project, until every sub-account is migrated |

### Option A — GHL custom values (recommended)
In that sub-account: **Settings → Custom Values → Add**
- Name `list_puncher_supabase_url`, value `https://<project-id>.supabase.co`
- Name `list_puncher_supabase_key`, value `sb_publishable_…`

Every browser in that sub-account picks them up on next load. No per-device setup.

### Option B — the in-app dialog
Inside the sub-account, open List Puncher → **☁ Cloud Project** →
paste URL + key → **🔌 Test connection** (must say *table reachable*) →
**✓ Save & Connect**. Tick *"also save to this sub-account's GHL custom values"*
to get Option A for free (needs the `pit-…` token in the menu link).

### Option C — menu-link parameters
Append to the Custom Menu Link URL:
`&sb_url=https://<project-id>.supabase.co&sb_key=sb_publishable_…`

---

## Part 3 — Keep it awake

Add every client project to
[`.github/supabase-keepalive-targets.json`](../.github/supabase-keepalive-targets.json):

```json
{ "name": "Euro Parts West", "url": "https://<ref>.supabase.co", "key": "sb_publishable_..." }
```

The workflow pings all of them daily. Free projects pause after **7 days** without activity —
paused is not data loss, but sync stops for that client until it is restored.

---

## Verify it end-to-end

1. Open List Puncher from that sub-account's menu link.
2. Storage pill should read `☁ Synced` after any edit (not `☁ Not connected`).
3. That client's project → **Table Editor → `list_puncher` → `lists`** → one row with their
   `location_id` and `project_id`.
4. Open the same link in a different browser: it must pull the shared row instead of seeding a
   fresh onboarding blueprint.

Console helper in either case: `lpStorageReport()` prints the resolved target, its source and
any queued pushes.

---

## Gotchas worth knowing

- **Free plan = 2 active projects per account.** One client with one project is fine.
- **Region is permanent** at project creation.
- **Publishable key is public by design** — it ships in the page. RLS is the security boundary.
- **The Connect dialog rejects `sb_secret_…`** on purpose, and refuses non-`https://` URLs.
- **Switching a target migrates** the list already cached in that browser into the new project
  (that is how you move a pilot list onto a client's own project).
- **When every sub-account has its own project**, set `LEGACY_FALLBACK_CLOUD = null` in
  `index.html` so a misconfigured sub-account can never fall back into the agency project.
- **RLS model**: the app has no Supabase Auth session (GHL is the login boundary), so `anon`
  holds `select/insert/update` on the one table. `DELETE` is deliberately **not** granted, so
  nothing in a browser can destroy rows. If you later want writes gated, route them through
  the Cloudflare Worker with the secret key and revoke `insert/update` from `anon`.

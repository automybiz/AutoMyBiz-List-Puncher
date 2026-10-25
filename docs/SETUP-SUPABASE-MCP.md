# lp-format: 2
#
# LIST: Supabase Setup and VS Code MCP Connection
# A project-agnostic runbook. Stands up Supabase, connects VS Code through MCP, then wires List Puncher to it.
#
# Legend: [ ] to do   [v] already done   [x] REFUSED ON PURPOSE - a trap. Read the note before deciding you know better.
#
# The visible list title comes from the project pill, not from this text. Task one below fixes that.

# ==========================================
# 1. PREREQUISITES AND ACCOUNTS
# ==========================================
section: "Prerequisites and Accounts"
description: |
  Objectives: get every tool and account in place before touching Supabase, so nothing downstream stalls on a
  missing prerequisite. About 20 minutes, a browser that can complete an OAuth popup, and admin rights on the machine.
  Starting a runbook mid-way? Do this section anyway. Every trap later in the list traces back to skipping it.
tasks:
  - [ ] Name this list in the app
    notes: "The checklist text has no title field. List Puncher shows the project pill, so create or rename a project to Supabase and MCP Setup and this runbook matches its own file name."
    - [ ] Create or rename the project pill so the header reads the same as this list
  - [ ] Install the local tools
    notes: "Only Node is strictly required, and only for the pre-commit syntax check. The app needs no build step."
    - [ ] Node 18 or newer
    - [ ] Git for Windows
    - [ ] VS Code
    - [ ] The Cline extension inside VS Code
    - [v] List Puncher itself needs no build step, no npm install and no bundler
    - [x] Skip Node because the app runs in a browser anyway
      notes: "The house rule is node --check on the extracted inline script before every commit. No Node means that check silently stops happening."
  - [ ] Create the Supabase account and organisation
    - [ ] Sign up with GitHub or email login
    - [ ] Confirm the organisation that will own the projects
    - [ ] Confirm the Free plan limits: 2 active projects per account
    - [x] Share one login between everyone who needs access
      notes: "Use organisation members instead. A shared login makes every OAuth grant and every audit trail anonymous."
  - [ ] Learn the two key types before creating anything
    - [ ] Publishable key, sb_publishable_..., is public by design and ships in the page
    - [ ] Secret key, sb_secret_..., bypasses RLS and must never leave your machine
    - [x] Treat the publishable key as a secret and hide it
      notes: "It ships in index.html, which is public. RLS is the security boundary, not the key."

# ==========================================
# 2. CREATE THE SUPABASE PROJECT
# ==========================================
section: "Create the Supabase Project"
description: |
  Objectives: create one project every tool can point at, and record its coordinates correctly the first time.
  Already have a project? Use this section to VERIFY the coordinates instead of creating a second one.
tasks:
  - [ ] Create the project
    - [ ] New project in the dashboard
    - [ ] Give it a name you will recognise in a list of projects
    - [ ] Choose the region closest to the people who will use it
    - [ ] Let Supabase generate the database password and store it in your password manager
    - [x] Pick a region you might want to change later
      notes: "Region is permanent at creation. Changing it later means creating a new project and migrating everything into it."
    - [x] Invent your own database password to keep things simple
      notes: "You will not need it. Let Supabase generate it, store it, and move on."
  - [ ] Wait for provisioning to finish
    - [ ] Wait about two minutes until the dashboard stops showing progress
    - [ ] Confirm the project reports healthy before running any SQL
    - [x] Open the SQL editor while it is still provisioning
      notes: "Queries fail in confusing ways during provisioning. Two minutes of patience saves an hour of doubt."
  - [ ] Record the coordinates
    - [ ] Copy the project ref from Settings, General
    - [ ] Build the project URL as https://YOUR-PROJECT-REF.supabase.co
    - [ ] Paste that URL into a browser tab and confirm something answers
    - [x] Transcribe the ref by hand from a screenshot or an email
      notes: "The ref is exactly 20 characters. A 19-character typo makes the hostname not resolve at all, which looks like an outage."
  - [ ] Respect the plan limits
    - [x] Create one project per team member as a scratch pad
      notes: "Free plan allows 2 active projects per account. Scratch projects quietly consume a client slot."

# ==========================================
# 3. DATABASE SETUP
# ==========================================
section: "Database Setup"
description: |
  Objectives: get the schema, the exposed API surface and the text column right in one pass.
  Prerequisites: section 2 complete. You can do all of this in the SQL editor without MCP, so MCP never blocks you.
tasks:
  - [ ] Run the schema script
    - [ ] Open SQL Editor, New query
    - [ ] Paste the whole of setup-client-project.sql for a client-owned project, or setup-agency-hub.sql for the hub
    - [v] Both scripts already exist in the repo under supabase/, so there is nothing to write from scratch
    - [ ] Run it once and read the notices before closing the tab
    - [ ] Re-run it to confirm it is idempotent
    - [x] Hand-edit the script to tidy it up before the first run
      notes: "The scripts are the source of truth for grants and policies. Edit them in the repo and commit, never in the SQL box."
    - [x] Run only the CREATE TABLE part and skip the grants
      notes: "The grants are what make the app work. A table with no grant returns 401 forever."
  - [ ] Expose the schema to the API
    - [ ] Settings, Data API, Exposed schemas
    - [ ] Add list_puncher to the list
    - [ ] Save, then reload the API settings page to confirm it stuck
    - [x] Skip this because the table lives outside public and should just work
      notes: "Schemas outside public are invisible to the REST API until exposed. Every request returns 404 and looks like a wrong URL."
  - [ ] Confirm the schema shape
    - [ ] The text column is checklist_text, and nothing else
    - [ ] Confirm tables lists, tenants and the backup tables exist
    - [x] Rename the text column to yaml, or add a yaml fallback for old rows
      notes: "The stored text is List Puncher shorthand, not YAML. There is deliberately no legacy fallback and adding one means maintaining two readers."

# ==========================================
# 4. KEYS AND THE SECURITY MODEL
# ==========================================
section: "Keys and the Security Model"
description: |
  Objectives: put each key where it belongs, then understand why the hub answering 401 is a feature.
  Prerequisites: section 3 complete. Read this before you paste any key anywhere.
tasks:
  - [ ] Decide which key goes where
    - [ ] Publishable key in index.html, in the keepalive targets JSON, and in GHL custom values
    - [ ] Secret key only in the Cloudflare Worker environment
    - [x] Put the secret key in index.html
      notes: "normalizeCloudTarget rejects it on purpose. If it ever slipped past that check, the page is public and RLS is gone."
    - [x] Put the secret key in .github/supabase-keepalive-targets.json
      notes: "That file is committed to a public repository. Publishable keys only, always."
  - [ ] Understand why the hub answers 401
    - [ ] Anon holds no table grants on the hub, only the RPC functions
    - [ ] A 401 on GET /rest/v1/lists is the correct, expected answer
    - [ ] Test the hub through POST /rest/v1/rpc/get_list instead
    - [x] Fix the 401 by granting table privileges to anon
      notes: "That undoes tenant isolation. The hub is RPC-only by design, after Phase 2."
    - [x] Recreate the lists_anon_all policy on the hub
      notes: "It was removed on purpose. Recreating it re-opens exactly the hole Phase 2 closed."
  - [ ] Keep client-owned projects the opposite way round
    - [ ] They DO need the table grant that setup-client-project.sql creates
    - [ ] They deliberately omit DELETE so a browser can never destroy rows
    - [ ] They rely on RLS as the only boundary, because GHL is the login
    - [x] Grant DELETE to anon for convenience
      notes: "Row deletion from a browser is unrecoverable. The backup tables exist for a reason."
    - [x] Point table mode at the agency hub
      notes: "Table mode writes no tenant_hash, so a direct insert fails with a null value error. Table mode is for client projects only."

# ==========================================
# 5. CONNECT VS CODE TO SUPABASE
# ==========================================
section: "Connect VS Code to Supabase"
description: |
  Objectives: give the editor a real, authenticated MCP connection to the project so tools can read and write.
  Prerequisites: section 2 complete for the project ref, section 4 read. Expect one browser round trip.
tasks:
  - [ ] Add the MCP server entry
    - [ ] Server name supabase
    - [ ] URL carries project_ref plus features=database,docs,debugging
    - [ ] Save the MCP settings file
    - [x] Add account or development features you do not use
      notes: "Every extra feature is another tool surface to authorise and audit."
    - [x] Add read_only when you actually need to write
      notes: "The URL param only REQUESTS read-only, it never grants write. A 403 after trying upscoping means the grant itself is read-only."
  - [ ] Authenticate
    - [ ] Trigger Authenticate from the MCP panel
    - [ ] Complete OAuth in the browser with READ and WRITE scopes
    - [ ] Confirm the token landed in the MCP settings file
    - [x] Assume the grant is read-write because the button said Authorise
      notes: "Check the scopes. A read-only grant fails much later, after trying upscoping, which reads as a permissions mystery."
    - [x] Commit the MCP settings file with tokens in it
      notes: "It contains oauth tokens. It stays out of git."
  - [ ] Verify the tools are live
    - [ ] Ask for a table list and confirm real tables come back
    - [ ] Confirm the SQL and table tools are both present
    - [x] Assume tools work inside a task that was already running
      notes: "Tools bind at task start. After installing or changing MCP, start a new task or every call fails with no connection found for server supabase."

# ==========================================
# 6. MCP AND REST TROUBLESHOOTING
# ==========================================
section: "MCP and REST Troubleshooting"
description: |
  Objectives: recognise each known failure by its symptom, then apply the fix that does not cost you a client.
  Prerequisites: sections 4 and 5. Consult this section the moment something fails instead of improvising a fix.
tasks:
  - [ ] Authenticate opens no browser
    - [ ] Run a small listener on 127.0.0.1:1456
    - [ ] Use the stored client_id, client_secret and code verifier
    - [ ] Build the S256 challenge, capture the code, exchange it at the token endpoint
    - [ ] Write the returned tokens back into the config
    - [x] Inject your own state value into the editor OAuth flow
      notes: "The editor validates state itself and answers state mismatch. Only your own listener may own the state it receives."
  - [ ] 422 Unrecognised client_id
    - [ ] Delete the oauth block and re-register
    - [x] Keep retrying the same cached registration
      notes: "A stale registration never becomes valid again. Delete and re-register."
  - [ ] 403 after trying upscoping
    - [ ] Revoke the grant and re-authorise with write scopes
    - [x] Believe the read_only URL param grants write access
      notes: "The param requests, it never grants. Only the authorisation screen sets scopes."
  - [ ] REST 404 on lists
    - [ ] Add list_puncher to Exposed schemas
    - [ ] GET sends Accept-Profile, POST sends Content-Profile
    - [x] Send only Accept-Profile on a POST
      notes: "A POST picks its schema from Content-Profile. Accept-Profile alone leaves it in public and answers PGRST202 could not find the function."
  - [ ] 401 on a REST read
    - [ ] Publishable key goes on apikey only
    - [ ] Legacy anon JWT goes on apikey and Authorization Bearer
    - [x] Send a publishable key as Authorization Bearer
      notes: "Publishable keys are not JWTs. Sending one as a bearer token produces a 401 that looks like an RLS problem."
  - [ ] One browser stuck on Offline while the others sync
    - [ ] Clear the cached list_puncher_cloud_mode entry for that URL
    - [ ] Reload and confirm the pill recovers
    - [x] Clear all site data or reinstall the app
      notes: "One stale key is the whole problem. Clearing everything also destroys that browser local list."

# ==========================================
# 7. CONNECT LIST PUNCHER TO THE PROJECT
# ==========================================
section: "Connect List Puncher to the Project"
description: |
  Objectives: point the app at this project so every device in that sub-account inherits it.
  Prerequisites: sections 2, 3 and 4. This is the only section that is specific to List Puncher rather than to Supabase.
tasks:
  - [ ] Choose the wiring method
    - [ ] Option A, GHL custom values, recommended, inherited by every device
    - [ ] Option B, the in-app Cloud Project dialog, best while testing
    - [ ] Option C, menu link parameters, one-off only
    - [x] Use menu link parameters for production
      notes: "The key ends up in the URL, in browser history and in screenshots other people can see."
  - [ ] Test before saving
    - [ ] Paste the project URL and the publishable key
    - [ ] Click Test connection and require the words table reachable
    - [x] Save a failed test and fix it later
      notes: "A saved failure leaves a half-connected browser and the storage pill then lies to you."
  - [ ] Save and connect
    - [ ] Save and Connect
    - [ ] Tick the box that also writes the GHL custom values, when the token param is present
    - [ ] Confirm the header shows the expected project name
    - [x] Re-point one client at another client project to reuse a setup
      notes: "Switching a target migrates the cached list into the new project. That is exactly how one client list leaks into another."

# ==========================================
# 8. VERIFY END TO END
# ==========================================
section: "Verify End to End"
description: |
  Objectives: prove the whole chain works from three independent vantage points before you call it done.
  Prerequisites: sections 3, 5 and 7 complete. Do not skip the second browser.
tasks:
  - [ ] Verify from the app
    - [ ] Make one edit and wait for the storage pill to read Synced
    - [ ] Open the same link in a second browser and confirm it pulls the shared row instead of re-seeding
    - [ ] Run lpStorageReport in the console and read the resolved target plus its source
    - [x] Accept it because it looked fine on one machine
      notes: "One browser proves nothing about the target. The second browser is the check that catches a misconfigured sub-account."
  - [ ] Verify from the API
    - [ ] Hub: POST /rest/v1/rpc/get_list with the publishable key returns the list
    - [ ] Hub: a junk secret returns an empty array
    - [ ] Client project: a plain table read returns 200
    - [x] Treat the hub 401 as a failure and start changing grants
      notes: "401 on GET /rest/v1/lists is correct on the hub. Silencing it by adding grants breaks tenant isolation."
  - [ ] Verify from the database
    - [ ] Exactly one lists row per location_id
    - [ ] Exactly one tenants row per location_id on the hub
    - [x] Trust the app because it displayed a list
      notes: "The app shows whatever it has cached locally. The rows are the source of truth."

# ==========================================
# 9. ROLLOUT AND KEEP-ALIVE
# ==========================================
section: "Rollout and Keep-Alive"
description: |
  Objectives: repeat the setup per client without re-deriving the order, and stop free projects from pausing.
  Prerequisites: section 8 green for at least one client. Everything here is repeatable per sub-account.
tasks:
  - [ ] Roll a client out on the hub, zero touch
    - [ ] Ensure automybiz_api_token holds a PIT in that sub-account
    - [ ] Append the token parameter to the Custom Menu Link
    - [ ] Open List Puncher once in that sub-account and let it provision itself
    - [ ] Confirm exactly one tenants row and one lists row appeared
    - [ ] Confirm get_list with a junk secret against it returns an empty array
    - [x] Pre-create the tenant row by hand to save time
      notes: "The app mints that secret. A hand-made row has a hash nobody knows and the first load overwrites your work."
  - [ ] Roll a client out on their own project
    - [ ] Repeat sections 2, 3 and 7 against that client project
    - [ ] Confirm the client project kept its table grant
    - [x] Put two clients in one project to save project slots
      notes: "Isolation is the whole point. Two clients in one project means a single RLS mistake leaks both."
  - [ ] Keep it awake
    - [ ] Add the project to .github/supabase-keepalive-targets.json with a publishable key
    - [v] supabase-keepalive.yml already runs daily for every registered target
    - [ ] Confirm the daily workflow lists the new target
    - [ ] Check the target answers after the first scheduled run
    - [x] Rely on everyday activity to keep the project from pausing
      notes: "Free projects pause after 7 days without activity. Pausing is not data loss, but sync stops silently."
    - [x] Let the repository sit idle for two months
      notes: "GitHub disables scheduled workflows after 60 days of repository inactivity, and the pings simply stop."

# ==========================================
# HOW TO WORK THIS LIST QUICKLY
# ==========================================
# Every group of sub-tasks sits under a parent on purpose.
# When you have finished a whole group, use YesAll on the parent and the whole branch turns green in one click.
# Use NoAll only on a trap you have read and consciously rejected, so the reasoning stays in the list.

# lp-format: 2

# Paste this file into List Puncher (Paste button) to turn it into a working checklist.
# [ ] = to do, [v] = already done, [x] = deliberately NOT done (a trap).

# ==========================================
# 1. NEW MACHINE
# ==========================================
section: "1. New machine"
tasks:
  - [ ] Install Node 18 or newer (nodejs.org)
    - [v] Only needed for the pre-commit syntax check, the app itself runs in any browser
  - [ ] Install Git for Windows
  - [ ] Clone https://github.com/automybiz/AutoMyBiz-List-Puncher
  - [ ] Open index.html directly in the browser
    - [v] No build step, no npm install, no bundler
  - [ ] Check the version pill against APP_BUILD at the top of index.html

# ==========================================
# 2. SUPABASE PROJECT
# ==========================================
section: "2. Supabase project"
tasks:
  - [ ] Create the Supabase account (GitHub or email login, free plan, no card)
  - [ ] New project, name it List Puncher, pick the region closest to the client
    - [x] Assume the region can be changed later - it is permanent
  - [ ] Wait about two minutes for provisioning to finish
  - [ ] SQL Editor, New query, paste all of supabase/setup-client-project.sql, Run
    - [v] The script is written to be safe to re-run at any time
  - [ ] Settings, Data API, Exposed schemas, add list_puncher, Save
    - [x] Skip this step - every request then returns 404 because the table is outside public
  - [ ] Settings, API Keys, copy the publishable key (sb_publishable_...)
    - [x] Copy the secret key (sb_secret_...) - it bypasses RLS completely
  - [ ] Settings, General, copy the Project ID and be sure it is exactly 20 characters
    - [x] Transcribe the ID by hand - a 19 character typo makes the hostname not exist
  - [ ] Respect the free plan limit: 2 active projects per account
  - [ ] Send the agency two values only: the project URL and the publishable key

# ==========================================
# 3. WIRE THE SUB-ACCOUNT
# ==========================================
section: "3. Wire the sub-account"
tasks:
  - [ ] Pick the mode for this client
    - [v] Agency hub: zero setup per client, rows isolated per sub-account by a secret the app mints
    - [ ] Own project: one Supabase project per client, better isolation, more admin
  - [ ] Hub mode: make sure the custom value automybiz_api_token holds a PIT
    - [ ] Append and token={{custom_values.automybiz_api_token}} to the Custom Menu Link
    - [ ] Open List Puncher once in that sub-account and let it provision itself
  - [ ] Own-project mode: Settings, Custom Values, Add the two values
    - [ ] list_puncher_supabase_url = the project URL from step 2
    - [ ] list_puncher_supabase_key = the publishable key from step 2
  - [ ] Alternative wiring: open List Puncher, click Cloud Project, paste URL and key
    - [ ] Test connection must say table reachable before you save
    - [ ] Save and Connect, and tick the box that also writes the GHL custom values
  - [x] Append sb_url and sb_key to a menu link that every client can see
    - [v] Acceptable for a one-off test link, wrong for production
  - [ ] Confirm the Storage pill reads Synced after one edit, not Not connected

# ==========================================
# 4. KEEP IT AWAKE
# ==========================================
section: "4. Keep it awake"
tasks:
  - [ ] Add every client project to .github/supabase-keepalive-targets.json
    - [ ] One object per project with name, url and the publishable key
    - [x] Put a secret key in that file - the repository is public
  - [ ] Let the workflow supabase-keepalive.yml ping every target daily
    - [v] Free projects pause after 7 days without activity - pausing is not data loss
    - [ ] Watch for GitHub disabling scheduled workflows after 60 days of repo inactivity

# ==========================================
# 5. VERIFY END TO END
# ==========================================
section: "5. Verify end to end"
tasks:
  - [ ] Open List Puncher from that sub-account menu link
  - [ ] Make one edit and wait for the Storage pill to read Synced
  - [ ] Open the client project, Table Editor, list_puncher, lists
    - [ ] Exactly one row, carrying that client location_id and project_id
  - [ ] Open the same link in a second browser
    - [ ] It pulls the shared row instead of seeding a fresh onboarding blueprint
  - [ ] Run lpStorageReport in the console to print the resolved target and its source

# ==========================================
# 6. AGENCY HUB
# ==========================================
section: "6. Agency hub"
tasks:
  - [v] Phase 1B and Phase 2 are applied and verified
  - [ ] Confirm the hub is RPC-only
    - [v] GET /rest/v1/lists answering 401 permission denied is CORRECT
    - [ ] Test with POST /rest/v1/rpc/get_list and the Content-Profile header
  - [x] Grant table privileges to anon on the hub
  - [x] Recreate the lists_anon_all policy on the hub
  - [ ] Remember client-owned projects are the opposite, they need the table grant
  - [ ] Only publishable keys go into index.html and the keepalive targets file
  - [x] Put a secret key in the page - normalizeCloudTarget rejects it on purpose

# ==========================================
# 7. TRAPS ALREADY HIT
# ==========================================
section: "7. Traps already hit"
tasks:
  - [ ] REST 404 on lists
    - [ ] Add list_puncher to Exposed schemas and send Accept-Profile and Content-Profile
  - [ ] 401 on REST with a publishable key
    - [ ] Publishable keys go on apikey only, never on Authorization Bearer
  - [ ] PGRST202 could not find the function on an RPC
    - [ ] A POST picks its schema from Content-Profile, Accept-Profile leaves it in public
  - [ ] Direct insert fails with null value in column tenant_hash
    - [v] Expected on the hub, hub rows are only written by upsert_list
  - [ ] One browser stuck on Offline while the others sync
    - [ ] That profile cached list_puncher_cloud_mode as table, clear the key
  - [ ] The list came back as the starter blueprint
    - [ ] Recover the text from list_puncher.lists_backup_pre1b
  - [ ] MCP says no connection found for server supabase
    - [ ] Tools bind at task start, start a new task
  - [ ] OAuth failed with state mismatch
    - [ ] Never inject your own state into the Cline flow, drive it with your own listener

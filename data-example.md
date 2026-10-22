# ==========================================
# CLOUDFLARE INFRASTRUCTUREEE
# ==========================================
section: "Cloudflare Infrastructureee"
description: "Master DNS and edge routing"
tasks:
  - [x] Create account with admin@ email
    notes: "Isolates domain security from public sales"
  - [x] Invite automybiz@gmail.com as Administrator
    notes: "Enables agency management under single login"
  - [x] Deploy Sveltia CMS OAuth Authenticator Worker
    notes: "Handles secure GitHub OAuth proxying"

# ==========================================
# GITHUB REPOSITORY & SVELTIA CMS
# ==========================================
section: "GitHub Repository & Sveltia CMS"
description: "Codebase and CMS backend"
tasks:
  - [x] Client creates GitHub account (EPWAdmin)
    notes: "Gives client ownership credentials"
  - [x] Add client as repository collaborator
    notes: "Allows client to commit changes via Sveltia"
  - [x] Test 1-click 'Sign In with GitHub' at /admin/
    notes: "Verify login opens Sveltia dashboard"

# ==========================================
# STRIPE PAYMENT GATEWAY
# ==========================================
section: "Stripe Payment Gateway"
description: "Direct on-site payments"
tasks:
  - [ ] Client creates & verifies Stripe merchant account
    notes: "Connects bank for direct payouts"
    - [x] Generate Stripe Payment Links / Buy Buttons
      notes: |
        Tesla...
        https://www.youtube.com/watch?v=eqOfmtTJD1A&t=44s
      - [ ] Task Title
        notes: "Helpful instructions or links"
        - [ ] Subtask Title
          notes: "Helpful instructions or links"
          - [ ] Subtask Title
            notes: "Helpful instructions or links"
            - [ ] Subtask Title
              notes: "Helpful instructions or links"
              - [ ] Subtask Title
                notes: "Helpful instructions or links"
            - [ ] Subtask Title
              notes: "Helpful instructions or links"
            - [ ] Subtask Title
              notes: "Helpful instructions or links"

# ==========================================
# SUPABASE MEMBER PORTAL & GOOGLE AUTH
# ==========================================
section: "Supabase Member Portal & Google Auth"
description: "Customer authentication engine"
tasks:
  - [ ] Client signs up at supabase.com (via GitHub)
    notes: "Creates client-owned 2-project free org"
  - [ ] Invite automybiz@gmail.com to Organization
    notes: "Enables agency collaboration"
  - [ ] Configure Google OAuth Provider
    notes: "Enables 1-click customer login"

# ==========================================
# AUTOMYBIZ & GOHIGHLEVEL INTEGRATION
# ==========================================
section: "AutoMyBiz & GoHighLevel Integration"
description: "CRM and workflow automations"
tasks:
  - [x] Add Custom Menu Link: Products & Variants
    notes: "Embeds Sveltia CMS iframe in sidebar"
  - [ ] Generate Private Integration Token (PIT)
    notes: "Required for live contact custom fields"
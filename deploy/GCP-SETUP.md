# GCP setup — one OAuth client for every tenant

Done once, in the **Watchman IT** Google Cloud organization. The result is a
single External OAuth client that every Workspace tenant (your own orgs and
clients) trusts from their Admin console — see `TENANT-ONBOARDING.md`.

Google has no API for creating OAuth clients or consent screens, so steps 3–5
are console clicks. Everything else is `gcloud`.

Time: ~20 minutes.

---

## 1. Create the project

Signed in as a Watchman IT admin with Project Creator on the org:

```bash
gcloud projects create watchmanit-workspace-mcp --name="Watchman IT Workspace MCP" \
  --organization=<WATCHMANIT_ORG_ID>
gcloud config set project watchmanit-workspace-mcp
gcloud billing projects link watchmanit-workspace-mcp --billing-account=<BILLING_ACCOUNT_ID>
```

Billing is required to enable APIs, but the Workspace APIs themselves are free.
Nothing in this project runs compute.

## 2. Enable the Workspace APIs

All twelve, so widening the tool tier later doesn't need another trip here:

```bash
gcloud services enable \
  gmail.googleapis.com \
  drive.googleapis.com \
  calendar-json.googleapis.com \
  docs.googleapis.com \
  sheets.googleapis.com \
  slides.googleapis.com \
  forms.googleapis.com \
  tasks.googleapis.com \
  people.googleapis.com \
  chat.googleapis.com \
  customsearch.googleapis.com \
  script.googleapis.com \
  --project=watchmanit-workspace-mcp
```

(Google Chat additionally needs a Chat app configured on the Chat API's
Configuration tab before Chat tools work. Skip until a tenant asks for Chat.)

## 3. OAuth consent screen ("Google Auth Platform → Branding / Audience")

Console: APIs & Services → OAuth consent screen (now "Google Auth Platform").

| Setting | Value | Why |
|---|---|---|
| **User type / Audience** | **External** | Internal would restrict sign-in to the Watchman IT org only. External lets any Workspace tenant whose admin trusts the client ID sign in. |
| App name | `Watchman IT – Google Workspace` | Shown on the Google consent screen. Match `WORKSPACE_MCP_BRAND_NAME`. |
| User support email | a watchmanit.com mailbox | Required. |
| App logo | optional — **leave blank** | Uploading a logo triggers brand verification review. |
| App domain → home page | `https://watchmanit.com` | |
| Authorized domains | `watchmanit.com`, `wmtech.app` | `wmtech.app` is required because the redirect URI lives there. |
| Developer contact | your email | |

## 4. Data access (scopes)

Add scopes for the services you will enable. Starting read-only on the core
tier, add these (paste into the "Manually add scopes" box):

```
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/userinfo.profile
openid
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/calendar.readonly
https://www.googleapis.com/auth/documents.readonly
https://www.googleapis.com/auth/spreadsheets.readonly
https://www.googleapis.com/auth/presentations.readonly
https://www.googleapis.com/auth/forms.body.readonly
https://www.googleapis.com/auth/forms.responses.readonly
https://www.googleapis.com/auth/tasks.readonly
https://www.googleapis.com/auth/contacts.readonly
```

When you later lift read-only or widen the tier, add the matching write
scopes here too (`gmail.modify`, `gmail.send`, `gmail.compose`,
`gmail.labels`, `gmail.settings.basic`, `drive`, `calendar`, `documents`,
`spreadsheets`, `presentations`, `forms.body`, `tasks`, `contacts`). The
server only *requests* the scopes its enabled tools need, but Google rejects
any scope not listed on the consent screen.

The console will flag `gmail.*` and `drive` scopes as **restricted** and
others as **sensitive** and say the app "needs verification". That is
expected — see step 6.

## 5. OAuth client

APIs & Services → Credentials → Create credentials → OAuth client ID:

| Setting | Value |
|---|---|
| Application type | **Web application** |
| Name | `workspace-mcp (mcp.wmtech.app)` |
| Authorized JavaScript origins | `https://mcp.wmtech.app` |
| Authorized redirect URIs | `https://mcp.wmtech.app/wit/google/oauth2callback` — exactly, no trailing slash |

Do **not** tick "Use this client for an AI-powered agent" — the server only
calls Google's REST APIs and that flag can't be changed later.

Copy the client ID and secret into `deploy/cloudflare/.env` (never into git).

## 6. Publishing status → In production, **without** verification

Audience page → Publishing status → **Publish app**. The console warns that
the app requests sensitive/restricted scopes and will need verification; you
can confirm publishing anyway. Do not submit for verification.

What that means in practice:

- Users in a Workspace org whose admin has **trusted** this client ID sign in
  normally. Google treats the app as internal for that org: no unverified-app
  warning, no 100-user cap, no 7-day token expiry.
- Users whose org has **not** trusted it see the "Google hasn't verified this
  app" interstitial and new Gmail-scope installs are blocked. That is the
  tenant-onboarding step, not a server problem.
- Consumer @gmail.com accounts have no admin to trust it, so they are stuck
  behind the unverified screen (clicking through "Advanced → Go to app" works
  for sensitive scopes but restricted Gmail/Drive scopes are blocked).
  Personal Gmail is out of scope for this deployment.

Google's docs say the admin "Trusted" status also lifts the 100-test-user cap
and 7-day refresh-token expiry for an app left in **Testing**. Publishing to
production anyway removes the test-user allowlist as a second thing to
maintain and is the state Google's own guidance assumes for trusted apps; if
you'd rather keep the app in Testing as a belt-and-braces guard against
untrusted orgs, add each tenant's users as test users and verify token
lifetime on the first tenant before relying on it.

## 7. Record what you made

Put these in the Watchman IT documentation (Claude Docs for now):

- GCP project ID and number
- OAuth client ID (not the secret) — this is the value tenants need to trust
- Date published to production

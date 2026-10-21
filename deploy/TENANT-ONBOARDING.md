# Tenant onboarding — adding a Google Workspace org

One page per tenant. ~15 minutes, no code changes, no redeploy.

**You need:** super-admin (or delegated admin with *Security → API controls*)
in the tenant's Workspace Admin console, and the OAuth client ID from
`GCP-SETUP.md`.

| | |
|---|---|
| Connector URL | `https://mcp.wmtech.app/wit/google/mcp` |
| OAuth client ID | `<from GCP-SETUP.md step 5>` |
| Tenant | `__________________` |
| Date | `__________________` |

---

## 1. Trust the client ID in the tenant's Admin console

Admin console → **Security → Access and data control → API controls →
Manage Third-Party App Access** → **Add app → OAuth App Name Or Client ID**.

1. Paste the OAuth client ID, search, select the app.
2. Scope: **all users in the org** (or a specific OU/group if the client wants
   to limit who can connect).
3. Access: **Trusted** — "Can access all Google services".
4. Save.

Why this matters: the app is unverified. Without Trusted, users in this org
hit "Google hasn't verified this app" and Gmail/Drive scopes are blocked.
With Trusted, Google treats it as the org's own internal app — no warning, no
user cap, no 7-day token expiry.

While you're there, check **App access control → Settings** isn't set to
"Block all third-party API access" without an exception for this app.

## 2. Access policy on mcp.wmtech.app

Cloudflare Access (Duo SSO) gates the login pages
(`/wit/google/authorize` and `/consent`); nobody can start a Google sign-in
without passing it. Default is TSTAdmins only. If anyone outside TSTAdmins in
this tenant should use the connector:

- Zero Trust → Access → Applications → the `google-workspace-mcp login` app →
  add an Allow policy (or Duo group) for the tenant's users; keep it as narrow
  as the client agreed to.
- They also need a Duo enrolment under the Duo app used by that Access policy.

Tenants that only *you* will act for (you sign in with your own Google
identity in their org, e.g. a delegated-admin account) need no Access change.

## 3. Add the connector in Claude (per user)

Settings → Connectors → **Add custom connector**:

- Name: `Google Workspace (<tenant>)`
- URL: `https://mcp.wmtech.app/wit/google/mcp`
- Leave client ID/secret blank (dynamic registration + PKCE).

Click **Connect** → Duo prompt → server consent page → Google sign-in **with
the account in this tenant** → Google consent → back to Claude.

Because this is one server for many tenants, the Google account you choose at
sign-in is what scopes the connection. A user with accounts in two tenants
adds the connector twice and picks a different account each time.

## 4. Verify (first user in the tenant)

In Claude, with the connector enabled:

1. `search_gmail_messages` for `newer_than:1d` — proves the restricted
   `gmail.readonly` scope was granted under the trust override.
2. `search_drive_files` for anything — proves `drive.readonly`.
3. Note the date. **Check again in 8+ days** that the connector still works
   without re-authenticating; if it forced a new login, the trust override did
   not take and the token hit the 7-day unverified-app expiry. Re-check step 1
   (the app may have been added as *Limited* rather than *Trusted*).

Record the tenant, the Google account(s) connected, and the verification date
in the tenant's documentation.

## 5. Widening access later

Everything starts **read-only, core tier**. When a tenant wants writes:

1. Make sure the write scopes are on the consent screen (`GCP-SETUP.md` step 4).
2. Change `WORKSPACE_MCP_READ_ONLY` / `TOOL_TIER` / `WORKSPACE_MCP_DISABLED_TOOLS`
   in `deploy/cloudflare/wrangler.toml` and redeploy. These are **global** —
   the server has one tool surface for all tenants. Use
   `WORKSPACE_MCP_DISABLED_TOOLS` to keep `send_gmail_message` and
   `share_drive_file` off until there's a specific reason to allow them.
3. Users re-authenticate once so Google grants the new scopes.

If tenants ever need *different* tool surfaces, that's a second Worker +
container with its own prefix (e.g. `/acme/google`) and the same image.

---

## Offboarding / rollback

**Remove a tenant**

1. Admin console → API controls → Manage Third-Party App Access → the app →
   change to **Blocked** (or remove). Existing tokens stop working on the next
   refresh (≤ 1 hour).
2. Remove the tenant's users from the Access policy.
3. Users delete the connector in Claude.

**Remove one user**

- User's Google account → Security → Third-party apps with account access →
  remove `Watchman IT – Google Workspace`. Or, as admin: Users → the user →
  Security → Connected applications → remove.

**Revoke everyone at once (incident)**

- Rotate `FASTMCP_SERVER_AUTH_GOOGLE_JWT_SIGNING_KEY` (`.env` →
  `set-secrets.sh` → `wrangler deploy`). Every stored proxy session becomes
  unreadable; all users must sign in again. Rotate the Google client secret as
  well if it may have leaked.
- Google Cloud Console → Credentials → the client → **Reset secret**.

**Disable the whole connector**

- `npx wrangler delete` from `deploy/cloudflare` removes the Worker and
  routes; the container stops with it. Or, less destructively, remove the
  `routes` and redeploy.

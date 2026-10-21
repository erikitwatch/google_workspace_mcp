# deploy/ — Watchman IT hosting of this fork

**Architecture in five lines**

1. One container (this repo's Dockerfile, pinned by tag) runs the server in
   OAuth 2.1 multi-user mode on Cloudflare Containers in The Solution Tailor
   account.
2. A thin Worker publishes it at `https://mcp.wmtech.app/wit/google` beside the
   other connectors, strips the prefix, and passes the RFC 8414 discovery
   routes through.
3. The Worker IP-gates the machine paths (`/mcp`, `/token`, `/register`,
   discovery) to claude.ai's egress range like the other connectors;
   Cloudflare Access + Duo gate the browser paths (`/authorize`, `/consent`)
   so only admitted people can start a login; Google sign-in then gives each
   user their own tokens.
4. One External Google OAuth client serves every Workspace tenant; each
   tenant's admin marks the client ID *Trusted*, which Google treats as
   internal (no verification, no user cap, no 7-day expiry).
5. OAuth proxy state lives in Valkey (Upstash) so logins survive container
   restarts; the server runs stateless otherwise. Tool surface starts
   read-only / core and is widened globally in `wrangler.toml`.

**Files**

| Path | What |
|---|---|
| `GCP-SETUP.md` | One-time: project, APIs, consent screen, OAuth client |
| `TENANT-ONBOARDING.md` | Per tenant: trust the client, Access policy, connect, verify, offboard |
| `cloudflare/wrangler.toml` | Worker, container, routes, all non-secret config |
| `cloudflare/src/index.ts` | The Worker |
| `cloudflare/.env.example` | The four secrets and how to set them |
| `cloudflare/set-secrets.sh` | Pushes `.env` into `wrangler secret` |
| `../.github/workflows/cloudflare-image.yml` | Builds the image on tag push, pushes to the Cloudflare registry |

**First deploy, in order**

1. `GCP-SETUP.md` end to end → client ID + secret.
2. Create an Upstash Redis database (TLS, US-East) → host + password.
3. In Cloudflare: Workers & Pages must have Containers enabled on the account
   (Workers Paid plan). Create an API token with *Workers Scripts: Edit* and
   *Containers: Edit*; add it and the account ID as repo secrets
   `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`.
4. Tag the fork (`git tag cf-$(date +%F) && git push --tags`) → the workflow
   pushes `workspace-mcp:<tag>` to `registry.cloudflare.com/<account>/`.
5. `cd deploy/cloudflare && npm install` → edit `wrangler.toml`: image tag,
   Valkey host → `cp .env.example .env`, fill in → `sh ./set-secrets.sh` →
   `npx wrangler deploy`.
6. Cloudflare Access (Zero Trust → Access → Applications → Self-hosted):
   one application with **two** public hostnames/paths,
   `mcp.wmtech.app/wit/google/authorize` and `mcp.wmtech.app/wit/google/consent`,
   Duo SSO as the identity provider, Allow policy = TSTAdmins. Nothing else
   under `/wit/google` goes behind Access: `/mcp`, `/token`, `/register` and
   the discovery documents are called by claude.ai's backend with a bearer
   token and no cookies (the Worker's IP gate protects them instead), and
   `/oauth2callback` is Google's redirect, protected by the OAuth `state`.
7. `curl https://mcp.wmtech.app/wit/google/health` → `{"status":"ok"...}`;
   `curl https://mcp.wmtech.app/.well-known/oauth-authorization-server/wit/google`
   → JSON with `"issuer": "https://mcp.wmtech.app/wit/google"`.
8. Onboard the Watchman IT tenant first with `TENANT-ONBOARDING.md`, verify
   the 8-day token check, then clients.

**Upgrading**

`git fetch upstream && git merge upstream/main` on `main`, run tests, tag,
let the workflow build, bump the tag in `wrangler.toml`, `wrangler deploy`.
Read the upstream release notes for env-var changes before bumping.

#!/bin/sh
# Push the secrets from ./.env into the Worker. Run from deploy/cloudflare.
# Usage: sh ./set-secrets.sh
set -eu

ENV_FILE="${1:-.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE - copy .env.example to .env and fill it in." >&2
  exit 1
fi

for NAME in \
  GOOGLE_OAUTH_CLIENT_ID \
  GOOGLE_OAUTH_CLIENT_SECRET \
  FASTMCP_SERVER_AUTH_GOOGLE_JWT_SIGNING_KEY \
  WORKSPACE_MCP_OAUTH_PROXY_VALKEY_PASSWORD
do
  VALUE="$(grep -E "^${NAME}=" "$ENV_FILE" | head -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')"
  if [ -z "$VALUE" ]; then
    echo "Skipping $NAME (empty in $ENV_FILE)"
    continue
  fi
  printf '%s' "$VALUE" | npx wrangler secret put "$NAME"
done

echo "Done. Redeploy with: npx wrangler deploy"

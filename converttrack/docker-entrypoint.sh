#!/bin/sh
set -e

TOKEN_PATH="${CHATWOOT_API_TOKEN_PATH:-/shared/chatwoot_api_token}"
MAX_WAIT="${CONVERTTRACK_TOKEN_WAIT_SECONDS:-120}"
WAITED=0

while [ ! -s "$TOKEN_PATH" ] && [ "$WAITED" -lt "$MAX_WAIT" ]; do
  echo "[converttrack] Attente token Chatwoot ($WAITED/${MAX_WAIT}s)..."
  sleep 2
  WAITED=$((WAITED + 2))
done

if [ -s "$TOKEN_PATH" ]; then
  export CHATWOOT_API_TOKEN="$(cat "$TOKEN_PATH")"
fi

exec "$@"

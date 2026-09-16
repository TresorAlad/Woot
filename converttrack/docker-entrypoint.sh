#!/bin/sh
set -e

if [ -f /shared/chatwoot_api_token ]; then
  export CHATWOOT_API_TOKEN="$(cat /shared/chatwoot_api_token)"
fi

exec "$@"

#!/bin/sh

set -e

rm -rf /app/tmp/pids/server.pid

echo "Using external PostgreSQL (Neon)..."

warm_global_config_cache() {
  echo "Warming GlobalConfig cache..."
  bundle exec rails runner "
    InstallationConfig.find_each do |config|
      cache_key = \"V1:GLOBAL_CONFIG:#{config.name}\"
      cached_value = { value: config.value }.to_json
      \$alfred.with { |conn| conn.set(cache_key, cached_value, { ex: 86400 }) }
    end
  " || echo "GlobalConfig cache warmup failed, continuing..."
}

case "$*" in
  *rails*s*|*puma*|*sidekiq*)
    warm_global_config_cache
    ;;
esac

exec "$@"

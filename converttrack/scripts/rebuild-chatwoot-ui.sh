#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BUILDER_IMAGE="chatwoot-frontend-builder:latest"
RAILS_CONTAINER="$(docker compose -f docker-compose.production.yaml ps -q rails 2>/dev/null || true)"

echo "[woot] Build frontend via Dockerfile.frontend-builder..."
if ! DOCKER_BUILDKIT=1 docker build \
  -f docker/Dockerfile.frontend-builder \
  -t "$BUILDER_IMAGE" \
  . 2>/dev/null; then
  echo "[woot] BuildKit indisponible, fallback legacy builder..."
  DOCKER_BUILDKIT=0 docker build \
    -f docker/Dockerfile.frontend-builder \
    -t "$BUILDER_IMAGE" \
    .
fi

BUILDER_CONTAINER="$(docker create "$BUILDER_IMAGE")"
trap 'docker rm -f "$BUILDER_CONTAINER" >/dev/null 2>&1 || true' EXIT

echo "[woot] Extraction des assets Vite..."
rm -rf public/vite
mkdir -p public/vite
docker cp "$BUILDER_CONTAINER:/app/public/vite/." public/vite/

if [ -n "$RAILS_CONTAINER" ]; then
  echo "[woot] Copie des assets dans le conteneur rails ($RAILS_CONTAINER)..."
  docker cp public/vite/. "$RAILS_CONTAINER:/app/public/vite/"
else
  echo "[woot] Conteneur rails absent, assets disponibles dans public/vite/"
fi

echo "[woot] Redemarrage rails et sidekiq..."
docker compose -f docker-compose.production.yaml up -d rails sidekiq

echo "[woot] Termine. Rechargez Woot (Ctrl+F5)."

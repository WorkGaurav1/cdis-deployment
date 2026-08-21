#!/usr/bin/env bash
# Deploys a specific frontend/backend version pair to this server.
#
# Usage: ./scripts/deploy.sh <frontend-version> <backend-version>
# Example: ./scripts/deploy.sh f144a57... fc9c6e5...
#
# Requires compose/.env.production to already exist (secrets, DB
# password, PUBLIC_ORIGIN) — copy env/production.env.example and fill
# it in once; this script only ever changes which image versions run.

set -euo pipefail
cd "$(dirname "$0")/../compose"

FRONTEND_VERSION="${1:?Usage: deploy.sh <frontend-version> <backend-version>}"
BACKEND_VERSION="${2:?Usage: deploy.sh <frontend-version> <backend-version>}"

if [ ! -f .env.production ]; then
  echo "compose/.env.production not found. Copy env/production.env.example and fill in real values first." >&2
  exit 1
fi

# Records what's currently live BEFORE touching anything, so rollback.sh
# has something to go back to. First deploy on a fresh server: no
# current-versions.env yet, nothing to preserve — that's expected.
if [ -f current-versions.env ]; then
  cp current-versions.env previous-versions.env
  echo "==> Preserved previous versions for rollback: $(cat previous-versions.env | tr '\n' ' ')"
fi

cat > current-versions.env <<EOF
FRONTEND_VERSION=$FRONTEND_VERSION
BACKEND_VERSION=$BACKEND_VERSION
EOF

echo "==> Deploying frontend=$FRONTEND_VERSION backend=$BACKEND_VERSION"
docker compose -f compose.production.yaml --env-file .env.production --env-file current-versions.env \
  pull frontend backend
docker compose -f compose.production.yaml --env-file .env.production --env-file current-versions.env \
  up -d

HEALTH_URL="${HEALTH_CHECK_URL:-http://localhost}/health"
echo "==> Waiting for health at $HEALTH_URL..."
HEALTHY=0
for _ in $(seq 1 30); do
  if curl -sf -m 2 "$HEALTH_URL" > /dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [ "$HEALTHY" -ne 1 ]; then
  echo "==> Health check failed after deploy." >&2
  if [ -f previous-versions.env ]; then
    echo "==> Run ./scripts/rollback.sh to return to the last known-good version." >&2
  fi
  exit 1
fi

echo "==> Deploy succeeded: frontend=$FRONTEND_VERSION backend=$BACKEND_VERSION, health check passed."

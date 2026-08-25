#!/usr/bin/env bash
# Brings up the local compose stack (building from sibling repo
# checkouts — ../cdis-backend, ../cdis-frontend) and prepares the
# database, so the E2E suite has something real to run against.
#
# Usage: ./scripts/e2e-up.sh
# Requires compose/.env to exist first (copy env/production.env.example).

set -euo pipefail
cd "$(dirname "$0")/../compose"

echo "==> Building and starting the stack..."
docker compose -f compose.yaml up -d --build

echo "==> Waiting for the backend to answer /health..."
HEALTHY=0
for _ in $(seq 1 30); do
  if curl -sf -m 2 "http://localhost:8080/health" > /dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [ "$HEALTHY" -ne 1 ]; then
  echo "==> Backend never became healthy — check: docker compose -f compose.yaml logs" >&2
  exit 1
fi

echo "==> Applying migrations and seed data..."
# Runs as root: the runtime image's /app is intentionally not
# writable by the non-root app user, and the seed command needs to
# write a throwaway .env file (see cdis-backend's known prisma.config.ts
# --env-file requirement) from the container's already-set environment.
docker compose -f compose.yaml exec -u root backend sh -c \
  'env > .env && npx prisma migrate deploy && npx prisma db seed'

echo "==> Stack is up: http://localhost:8080"

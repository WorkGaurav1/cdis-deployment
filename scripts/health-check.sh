#!/usr/bin/env bash
# Checks that the deployed stack is actually healthy — not just "the
# containers are running," but that the full chain (reverse proxy ->
# backend -> Prisma -> MySQL) answers correctly. Exits non-zero on any
# failure, so this is safe to use as a monitoring/alerting probe.
#
# Usage: ./scripts/health-check.sh [base-url]
# Defaults to http://localhost — pass a real URL to check remotely,
# e.g. ./scripts/health-check.sh https://cdis.example.com

set -uo pipefail

BASE_URL="${1:-http://localhost}"
FAILED=0

check() {
  local name="$1" url="$2" expect_code="$3"
  local code
  code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "$url")
  if [ "$code" = "$expect_code" ]; then
    echo "OK   $name ($code)"
  else
    echo "FAIL $name — expected $expect_code, got $code"
    FAILED=1
  fi
}

check "backend health (through proxy)" "$BASE_URL/health" "200"
check "frontend root"                   "$BASE_URL/"        "200"
# An unauthenticated /me must be 401, not 200 (would mean auth is
# broken open) and not 5xx (would mean the backend/DB chain is down).
check "auth is actually enforced"       "$BASE_URL/api/v1/auth/me" "401"

if [ "$FAILED" -eq 0 ]; then
  echo "==> All checks passed."
else
  echo "==> One or more checks failed." >&2
fi

exit "$FAILED"

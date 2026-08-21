#!/usr/bin/env bash
# Redeploys the previous known-good frontend/backend version pair —
# whatever was live immediately before the last ./scripts/deploy.sh run.
#
# Usage: ./scripts/rollback.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../compose"

if [ ! -f previous-versions.env ]; then
  echo "No previous-versions.env found — there's nothing recorded to roll back to yet" \
       "(this is expected before a second deploy has ever run)." >&2
  exit 1
fi

# shellcheck disable=SC1091
source previous-versions.env
echo "==> Rolling back to frontend=$FRONTEND_VERSION backend=$BACKEND_VERSION"

exec "$SCRIPT_DIR/deploy.sh" "$FRONTEND_VERSION" "$BACKEND_VERSION"

#!/usr/bin/env bash
# One-time HTTPS bootstrap: obtains the first Let's Encrypt certificate and
# switches the reverse proxy from HTTP-only to TLS.
#
# Usage: ./scripts/setup-https.sh <domain> <email>
# Example: ./scripts/setup-https.sh cdis.example.com you@example.com
#
# Requires:
#  - compose/.env.production already filled in (see deploy.sh)
#  - a first deploy already run (current-versions.env exists)
#  - <domain> already resolving, publicly, to this server on port 80
#    (Let's Encrypt validates ownership by fetching
#    http://<domain>/.well-known/acme-challenge/... from the internet)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$SCRIPT_DIR/.."
cd "$DEPLOY_ROOT/compose"

DOMAIN="${1:?Usage: setup-https.sh <domain> <email>}"
EMAIL="${2:?Usage: setup-https.sh <domain> <email>}"

if [ ! -f .env.production ]; then
  echo "compose/.env.production not found. Run a plain HTTP deploy first (see deploy.sh)." >&2
  exit 1
fi

if [ ! -f current-versions.env ]; then
  echo "No current-versions.env — run ./scripts/deploy.sh once over plain HTTP first." >&2
  exit 1
fi

if ! command -v envsubst > /dev/null 2>&1; then
  echo "envsubst not found (part of the gettext package) — install it first," \
       "e.g. 'sudo apt-get install -y gettext-base'." >&2
  exit 1
fi

echo "==> Bringing up bootstrap stack (HTTP-only, ACME challenge webroot)..."
docker compose -f compose.production.yaml -f compose.https-init.yaml \
  --env-file .env.production --env-file current-versions.env up -d reverse-proxy

echo "==> Requesting certificate for $DOMAIN..."
docker compose -f compose.production.yaml -f compose.https-init.yaml \
  --env-file .env.production --env-file current-versions.env run --rm certbot \
  "certbot certonly --webroot -w /var/www/certbot -d $DOMAIN --email $EMAIL --agree-tos --non-interactive"

echo "==> Certificate obtained. Rendering TLS Apache config for $DOMAIN..."
DOMAIN="$DOMAIN" envsubst '${DOMAIN}' \
  < "$DEPLOY_ROOT/reverse-proxy/apache/httpd.tls.conf.template" \
  > "$DEPLOY_ROOT/reverse-proxy/apache/httpd.conf"

echo "==> Switching to steady-state HTTPS stack..."
DOMAIN="$DOMAIN" docker compose -f compose.production.yaml -f compose.https.yaml \
  --env-file .env.production --env-file current-versions.env up -d

echo "==> Verifying https://$DOMAIN/health ..."
HEALTHY=0
for _ in $(seq 1 15); do
  if curl -sf -m 3 "https://$DOMAIN/health" > /dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [ "$HEALTHY" -ne 1 ]; then
  echo "==> HTTPS health check failed. Check: docker compose -f compose.production.yaml" \
       "-f compose.https.yaml --env-file .env.production logs reverse-proxy" >&2
  exit 1
fi

cat <<EOF
==> HTTPS is live at https://$DOMAIN

NOTE: reverse-proxy/apache/httpd.conf on this server now holds the
rendered TLS config (overwritten from httpd.tls.conf.template). That's
expected — don't 'git pull' over it without re-running this
substitution, and don't commit the overwritten file back (it's
server-local, DOMAIN-specific).

Renewal (certificates expire after 90 days — run this periodically, e.g.
monthly via cron):
  cd $DEPLOY_ROOT/compose
  docker compose -f compose.production.yaml -f compose.https.yaml \\
    --env-file .env.production --env-file current-versions.env \\
    run --rm certbot certbot renew
  docker compose -f compose.production.yaml -f compose.https.yaml \\
    --env-file .env.production --env-file current-versions.env \\
    restart reverse-proxy
EOF

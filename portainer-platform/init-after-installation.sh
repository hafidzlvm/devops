#!/bin/bash
# Re-open the Portainer initial-admin window after a security timeout.
# A fresh Portainer locks its setup a few minutes after first start;
# restarting re-arms it. Run this, then IMMEDIATELY create the admin
# account in the browser. Safe to re-run anytime.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env (copy .env.example to .env and fill values first)." >&2; exit 1; }

set -a
. ./.env
set +a

docker compose restart portainer

echo "Waiting for Portainer API ..."
ok=0
for _ in $(seq 1 30); do
    if curl -sf --max-time 3 "http://localhost:${PORTAINER_PORT:-9000}/api/status" >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 2
done
[ "$ok" = "1" ] || { echo "Portainer is not responding on :${PORTAINER_PORT:-9000}." >&2; exit 1; }

domain="$(grep -E '^PORTAINER_DOMAIN=' ../nginx-platform/.env 2>/dev/null | cut -d= -f2 || true)"
echo
echo "Portainer is up. Create the admin account NOW (setup locks after a few minutes):"
echo "  https://${domain:-<portainer-domain>}  (via nginx)"
echo "  http://<server-ip>:${PORTAINER_PORT:-9000}  (direct)"
echo
token=""
for _ in $(seq 1 15); do
    token="$(docker logs portainer 2>&1 | grep -i 'setup_token=' | tail -1 | sed 's/.*setup_token=//;s/[^a-f0-9]//g')"
    [ -n "$token" ] && break
    sleep 2
done
if [ -n "$token" ]; then
    echo "Setup token (Portainer >= 2.43, one-time use, paste into the setup page):"
    echo "  $token"
    echo
fi
echo "Timed out again? Just re-run this script."

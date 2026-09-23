#!/bin/bash
# Point this server's nginx at Portainer: set PORTAINER_DOMAIN in .env,
# issue its cert, recreate nginx so the template renders.
#
# Usage: ./enable-portainer.sh portainer.example.com
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env (copy .env.example first)." >&2; exit 1; }
domain="${1:?Usage: $0 portainer.example.com}"

if grep -qE '^PORTAINER_DOMAIN=' .env; then
    sed -i "s|^PORTAINER_DOMAIN=.*|PORTAINER_DOMAIN=$domain|" .env
else
    echo "PORTAINER_DOMAIN=$domain" >> .env
fi
echo "PORTAINER_DOMAIN=$domain"

./init-letsencrypt.sh
docker compose up -d
sleep 8
echo "### Verify:"
curl -s -o /dev/null -w "https://$domain/ -> %{http_code} (200/307 dari Portainer = ok)\n" --max-time 15 "https://$domain/"

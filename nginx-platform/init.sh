#!/bin/bash
# Start the nginx-platform service (nginx + certbot renew loop).
# Certificates are NOT handled here — see ./init-letsencrypt.sh (first run)
# or rely on the existing certs in the certbot volume.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env (copy .env.example to .env and fill values first)." >&2; exit 1; }

set -a
. ./.env
set +a

network_name="${NETWORK_NAME:-your-domain}"
docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name"

docker compose up -d
docker compose ps

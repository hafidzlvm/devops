#!/bin/bash
# Start the portainer-platform service.
# Prerequisite: nginx-platform already issued the TLS certs (or Portainer
# runs plain HTTP behind nginx — see PORTAINER_COMMAND in .env).
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env (copy .env.example to .env and fill values first)." >&2; exit 1; }

set -a
. ./.env
set +a

network_name="${NETWORK_NAME:-your-domain}"
docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name"

# Host path backing the data volume must exist (dir bind and NFS export alike).
[ -n "${PORTAINER_VOLUME_PATH:-}" ] && mkdir -p "$PORTAINER_VOLUME_PATH"

docker compose up -d
docker compose ps

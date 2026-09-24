#!/bin/bash
# One-time migration: shared bridge network -> overlay+attachable (swarm-ready).
#
# Safe to run AFTER nginx+portainer are already up: `docker swarm init` does
# not touch running standalone containers. Only the shared network is
# recreated, so the front restarts once (seconds of downtime — run off-peak).
# App stacks on the old network must be stopped first (script aborts if any
# remain attached) and re-attached (`up -d --force-recreate`) afterwards.
#
# Portainer itself stays standalone — only the shared network changes.
# Optional: SWARM_ADVERTISE_ADDR=<ip> ./init-swarm.sh  (multi-NIC hosts)
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env (copy .env.example to .env first)." >&2; exit 1; }

set -a
# shellcheck disable=SC1091
. ./.env
set +a

network_name="${NETWORK_NAME:-your-domain}"

# Portainer must share the same network name.
if [ -f ../portainer-platform/.env ]; then
    pnet=$(grep -E '^NETWORK_NAME=' ../portainer-platform/.env | cut -d= -f2 | tr -d "\"'" | head -1 || true)
    if [ -n "$pnet" ] && [ "$pnet" != "$network_name" ]; then
        echo "Error: NETWORK_NAME mismatch (nginx-platform=$network_name, portainer-platform=$pnet)." >&2
        exit 1
    fi
fi

# Join swarm (no-op if already in one).
state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)
if [ "$state" != "active" ]; then
    if [ -n "${SWARM_ADVERTISE_ADDR:-}" ]; then
        docker swarm init --advertise-addr "$SWARM_ADVERTISE_ADDR"
    else
        docker swarm init 2>/dev/null || {
            echo "Error: 'docker swarm init' failed (multi-NIC host? retry with SWARM_ADVERTISE_ADDR=<ip>)." >&2
            exit 1
        }
    fi
fi

# Abort BEFORE touching anything if foreign containers use the network.
# (Own platform containers are stopped below, so exclude them from the check.)
own_ids=$( (docker compose ps -q 2>/dev/null || true; (cd ../portainer-platform 2>/dev/null && docker compose ps -q 2>/dev/null || true)) | sort -u)
attached_ids=$(docker network inspect "$network_name" --format '{{range $k,$v := .Containers}}{{$k}} {{end}}' 2>/dev/null || true)
foreign=""
for id in $attached_ids; do
    case "$id" in lb-*) continue;; esac  # swarm LB endpoint, bukan container
    echo "$own_ids" | grep -q "^${id}$" || foreign="$foreign $id"
done
if [ -n "$foreign" ]; then
    # shellcheck disable=SC2086
    names=$(docker inspect --format '{{.Name}}' $foreign 2>/dev/null | sed 's|^/||' | tr '\n' ' ' || true)
    [ -n "$names" ] || names="$foreign"
    echo "Error: network $network_name still in use by: $names" >&2
    echo "Stop those app stacks first, then re-run this script. Nothing was changed." >&2
    exit 1
fi

# Stop both platforms, then the network must be free of containers.
docker compose down
if [ -f ../portainer-platform/docker-compose.yml ]; then
    (cd ../portainer-platform && docker compose down)
fi

attached=$(docker network inspect "$network_name" --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null || true)
if [ -n "$attached" ]; then
    echo "Error: network $network_name still in use by: $attached" >&2
    echo "Stop those app stacks first, then re-run this script." >&2
    exit 1
fi

# Already overlay (re-run)? Keep it, skip recreate.
driver=$(docker network inspect "$network_name" --format '{{.Driver}}' 2>/dev/null || true)
if [ "$driver" != "overlay" ]; then
    docker network rm "$network_name" 2>/dev/null || true
    docker network create --driver overlay --attachable "$network_name"
else
    echo "Network $network_name is already overlay, keeping it."
fi

docker compose up -d
if [ -f ../portainer-platform/docker-compose.yml ]; then
    (cd ../portainer-platform && docker compose up -d)
fi

echo "Swarm-ready: $network_name (overlay+attachable). Re-attach app stacks now."
docker compose ps

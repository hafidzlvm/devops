#!/bin/bash
# Remove a front endpoint created by add-site.sh: delete its
# nginx/servers/<name>.conf (backed up first) and reload nginx.
# The certificate is KEPT by default (harmless, LE auto-expires, and it may
# be shared via SAN with other domains). Pass --delete-cert to remove it too.
#
# Usage:
#   ./remove-site.sh -n <name> [--delete-cert] [-y]
#
# Example:
#   ./remove-site.sh -n myapp.example.com
#   ./remove-site.sh -n myapp.example.com --delete-cert
set -euo pipefail
cd "$(dirname "$0")"

name=""
delete_cert=0
yes=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n) name="${2:?missing value for -n}"; shift 2 ;;
        --delete-cert) delete_cert=1; shift ;;
        -y|--yes) yes=1; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1 (see --help)." >&2; exit 1 ;;
    esac
done

[ -n "$name" ] || { echo "-n <name> is required (see nginx/servers/ for names)." >&2; exit 1; }
conf="nginx/servers/${name}.conf"
[ -f "$conf" ] || { echo "Not found: $conf (nothing to remove)." >&2; exit 1; }

if [ "$yes" != "1" ]; then
    echo "Will remove $conf $([ "$delete_cert" = "1" ] && echo "+ its certificate" || echo "(certificate kept)")."
    read -r -p "Continue? (y/N) " decision
    [ "$decision" = "Y" ] || [ "$decision" = "y" ] || { echo "Aborted."; exit 0; }
fi

cp "$conf" "$conf.bak-$(date +%Y%m%d%H%M%S)" && rm "$conf"
echo "Removed $conf (backup kept alongside it)."

if [ "$delete_cert" = "1" ]; then
    # Primary domain = live dir derived from the first server_name in the backup.
    primary=$(grep -m1 "ssl_certificate .*/live/" "$conf.bak-"* 2>/dev/null | sed 's|.*/live/||;s|/.*||')
    if [ -n "$primary" ]; then
        echo "### Deleting certificate for $primary ..."
        docker compose run --rm --entrypoint "\
          rm -rf /etc/letsencrypt/live/$primary \
                  /etc/letsencrypt/archive/$primary \
                  /etc/letsencrypt/renewal/$primary.conf" certbot >/dev/null
    else
        echo "No certificate path found in backup — skipping cert deletion."
    fi
fi

echo "### Reloading nginx ..."
docker compose exec nginx nginx -s reload
echo "Done. The domain now falls through to the default server block."

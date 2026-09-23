#!/bin/bash
# Register a new front endpoint: write nginx/servers/<name>.conf, issue its
# Let's Encrypt cert, reload nginx. Covers: new app service, api- subdomain,
# or a new apex+www domain on this server.
#
# Usage:
#   ./add-site.sh -d example.com [-d www.example.com] -b backend-host:port [-n name] [-m max-body]
#
# Example:
#   ./add-site.sh -d api.example.com -b myapi:8000
#   ./add-site.sh -d example.com -d www.example.com -b web:3000 -m 100M
set -euo pipefail
cd "$(dirname "$0")"

domains=()
backend=""
name=""
max_body="50M"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -d) domains+=("${2:?missing value for -d}"); shift 2 ;;
        -b) backend="${2:?missing value for -b}"; shift 2 ;;
        -n) name="${2:?missing value for -n}"; shift 2 ;;
        -m) max_body="${2:?missing value for -m}"; shift 2 ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1 (see --help)." >&2; exit 1 ;;
    esac
done

[ "${#domains[@]}" -gt 0 ] || { echo "At least one -d domain is required." >&2; exit 1; }
[ -n "$backend" ] || { echo "-b backend-host:port is required." >&2; exit 1; }
[[ "$backend" =~ ^[A-Za-z0-9_.-]+:[0-9]+$ ]] || { echo "Bad backend '$backend' (want host:port)." >&2; exit 1; }

primary="${domains[0]}"
[ -n "$name" ] || name="$primary"
backend_host="${backend%%:*}"
backend_port="${backend##*:}"
server_names="${domains[*]}"
email="$(grep -E '^SSL_EMAIL=' .env 2>/dev/null | cut -d= -f2 || true)"
if [ -n "$email" ]; then
    email_arg="--email $email"
else
    email_arg="--register-unsafely-without-email"
fi

mkdir -p nginx/servers
conf="nginx/servers/${name}.conf"
[ -f "$conf" ] && { echo "Refusing: $conf already exists (edit it by hand)." >&2; exit 1; }

cat > "$conf" <<EOF
server {
    listen 80;
    server_name ${server_names};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${server_names};

    server_tokens off;
    client_max_body_size ${max_body};

    ssl_certificate /etc/letsencrypt/live/${primary}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${primary}/privkey.pem;

    location / {
        resolver 127.0.0.11 valid=30s; # docker embedded DNS, resolve backend lazily
        set \$site_backend ${backend_host};
        proxy_pass http://\$site_backend:${backend_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;

        # CORS langsung dari map front:
        add_header 'Access-Control-Allow-Origin' \$CORS_ALL_ALLOWED_DOMAIN always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
    }
}
EOF
echo "Wrote $conf"

echo "### Requesting certificate for: ${server_names} ..."
domain_args=""
for d in "${domains[@]}"; do domain_args="$domain_args -d $d"; done
# shellcheck disable=SC2086
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    ${email_arg} \
    $domain_args \
    --rsa-key-size 4096 \
    --agree-tos \
    --no-eff-email \
    --force-renewal" certbot
echo

if docker inspect nginx --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null | grep -qx "/etc/nginx/servers"; then
    echo "### Reloading nginx ..."
    docker compose exec nginx nginx -s reload
else
    echo "### servers/ not mounted yet — recreating nginx once ..."
    docker compose up -d
    sleep 8
fi
echo
echo "### Verify:"
for d in "${domains[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$d/" || echo "FAIL")
    echo "  https://$d/ -> $code"
done

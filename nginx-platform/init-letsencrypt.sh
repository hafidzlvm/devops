#!/bin/bash
# Bootstrap / renew Let's Encrypt certificates.
# Scope: certificates only — it does NOT manage the nginx service itself.
# Use ./init.sh to start the service.
#
# Covers ${APP_DOMAIN} always, plus ${PORTAINER_DOMAIN} when set in .env.
# Idempotent: domains with a real (non-dummy) cert are skipped.
set -euo pipefail
cd "$(dirname "$0")"

set -a
[ -f .env ] && . ./.env
set +a

domain="${APP_DOMAIN:?APP_DOMAIN is not set (copy .env.example to .env first)}"
email="${SSL_EMAIL:-}"
staging="${STAGING:-0}"
network_name="${NETWORK_NAME:-your-domain}"

volume_type="${CERTBOT_VOLUME_TYPE:-dir}"
conf_path="${CERTBOT_CONF_VOLUME_PATH:-/var/lib/nginx-platform/certbot-conf}"
www_path="${CERTBOT_WWW_VOLUME_PATH:-/var/lib/nginx-platform/certbot-www}"

docker compose version >/dev/null 2>&1 || { echo "Error: 'docker compose' is not installed." >&2; exit 1; }

docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name"

if [ "$volume_type" = "dir" ]; then
    mkdir -p "$conf_path" "$www_path"
fi

domains=("$domain")
[ -n "${PORTAINER_DOMAIN:-}" ] && domains+=("$PORTAINER_DOMAIN")

cert_has_real_cert() {
    local d="$1" live="/etc/letsencrypt/live/$1"
    docker compose run --rm --entrypoint "sh -c 'test -f $live/fullchain.pem'" certbot >/dev/null 2>&1 || return 1
    local issuer
    issuer=$(docker compose run --rm --entrypoint "sh -c 'openssl x509 -in $live/fullchain.pem -noout -issuer 2>/dev/null'" certbot 2>/dev/null | tail -1)
    ! echo "$issuer" | grep -qi "localhost"
}

needs=()
for d in "${domains[@]}"; do
    if cert_has_real_cert "$d"; then
        echo "Real certificate already exists for $d — skipping."
    else
        needs+=("$d")
    fi
done

if [ "${#needs[@]}" -eq 0 ]; then
    echo "Nothing to do."
    exit 0
fi

for d in "${needs[@]}"; do
    echo "### Creating dummy certificate for $d ..."
    docker compose run --rm --entrypoint "\
      mkdir -p '/etc/letsencrypt/live/$d' && \
      openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout '/etc/letsencrypt/live/$d/privkey.pem' \
        -out '/etc/letsencrypt/live/$d/fullchain.pem' \
        -subj '/CN=localhost'" certbot >/dev/null
done
echo

echo "### (Re)starting nginx with dummy certificate(s) ..."
docker compose up --force-recreate -d nginx
sleep 10
echo

for d in "${needs[@]}"; do
    echo "### Deleting dummy certificate for $d ..."
    docker compose run --rm --entrypoint "\
      rm -rf /etc/letsencrypt/live/$d \
              /etc/letsencrypt/archive/$d \
              /etc/letsencrypt/renewal/$d.conf" certbot >/dev/null
done
echo

email_arg="--register-unsafely-without-email"
[ -n "$email" ] && email_arg="--email $email"
staging_arg=""
[ "$staging" != "0" ] && staging_arg="--staging"

for d in "${needs[@]}"; do
    echo "### Requesting Let's Encrypt certificate for $d ..."
    docker compose run --rm --entrypoint "\
      certbot certonly --webroot -w /var/www/certbot \
        $staging_arg \
        $email_arg \
        -d $d \
        --rsa-key-size 4096 \
        --agree-tos \
        --no-eff-email \
        --force-renewal" certbot
    echo
done

echo "### Reloading nginx ..."
docker compose exec nginx nginx -s reload
echo
echo "Done."

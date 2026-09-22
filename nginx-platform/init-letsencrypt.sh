#!/bin/bash

# Source the .env file (supports quoted values with spaces)
set -a
if [ -f .env ]; then
  # shellcheck disable=SC1091
  . ./.env
fi
set +a

if ! [ -x "$(command -v docker compose)" ]; then
    echo 'Error: docker compose is not installed.' >&2
    exit 1
fi

domains=(${APP_DOMAIN:-your-domain.com})
rsa_key_size=4096
email="${SSL_EMAIL:-your@gmail.com}" # Adding a valid address is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

volume_type="${CERTBOT_VOLUME_TYPE:-dir}"
conf_path="${CERTBOT_CONF_VOLUME_PATH:-/var/lib/nginx-platform/certbot-conf}"
www_path="${CERTBOT_WWW_VOLUME_PATH:-/var/lib/nginx-platform/certbot-www}"
cors_path="${CORS_VOLUME_PATH:-/var/lib/nginx-platform/cors}"
network_name="${NETWORK_NAME:-your-domain}"

# Shared network must exist before any `docker compose run` call.
docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name"

# Bind (dir) volumes need an existing host path — the local driver won't create it.
if [ "$volume_type" = "dir" ]; then
    mkdir -p "$conf_path" "$www_path" "$cors_path"
fi

# File checks below run inside the certbot container, so they work for
# both dir (bind) and nfs (docker-managed) volumes.
if docker compose -f "docker-compose.yml" run --rm --entrypoint "sh -c 'test -d /etc/letsencrypt/live/$domains'" certbot >/dev/null 2>&1; then
    read -p "Existing certificate found for $domains. Continue and replace existing certificate? (y/N) " decision
    if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
        exit
    fi
fi

echo "### Creating dummy certificate for $domains ..."
path="/etc/letsencrypt/live/$domains"
docker compose -f "docker-compose.yml" run --rm --entrypoint "\
  mkdir -p '$path' && \
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo

echo "### Starting nginx ..."
docker compose  -f "docker-compose.yml" up --force-recreate -d nginx

echo

echo "### Deleting dummy certificate for $domains ..."
docker compose  -f "docker-compose.yml" run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot

echo

echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
"") email_arg="--register-unsafely-without-email" ;;
*) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker compose -f "docker-compose.yml" run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot

echo

#echo "### Reloading nginx ..."
docker compose -f "docker-compose.yml" exec nginx nginx -s reload


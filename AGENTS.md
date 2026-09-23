# AGENTS.md — devops (nginx-platform + portainer-platform)

Docker Compose infra repo. No app code, no package manager, no lint/test/build, no CI. Verification = `docker compose config` + `logs`.

## Structure

- `nginx-platform/` — nginx (reverse proxy, SSL termination) + certbot (Let's Encrypt). Entrypoints: `docker-compose.yml`, `init-letsencrypt.sh`, `nginx/secure/*.conf.template`.
- `portainer-platform/` — `portainer/portainer-ce:lts` only. Entrypoint: `docker-compose.yml`.
- Full docs live in each platform's `README.md` — read the relevant one before changing anything.

## Setup order (matters)

1. `cp .env.example .env` in each platform used, fill values (never commit `.env` — gitignored).
2. `docker network create "$NETWORK_NAME"` (both composes attach via key `shared` with `name: ${NETWORK_NAME}`; must match across platforms. `init-letsencrypt.sh` auto-creates it for nginx; portainer needs it manual).
3. nginx first run only: `chmod +x init.sh init-letsencrypt.sh && ./init-letsencrypt.sh` (issues certs AND starts nginx), afterwards `./init.sh` for start/restart.
4. Portainer: `docker compose up -d` in `portainer-platform/`.

## Conventions & gotchas

- Nginx templating: `nginx/secure/*.conf.template` mounts to `/etc/nginx/templates/`, envsubst renders `${APP_DOMAIN}` from `.env` into `/etc/nginx/conf.d/*.conf`. New domain/subdomain = new `*.conf.template` file + `certbot certonly --webroot` for that `-d` name + `docker compose restart nginx`. Keep `/.well-known/acme-challenge/` → `/var/www/certbot` block in every port-80 server or issuance fails.
- Template reusability rule: this repo is a generic template — NEVER commit real domains here. Per-server statics go in `nginx/servers/*.conf` (gitignored overlay, mounted at `/etc/nginx/servers/`, included by `nginx/nginx.conf`; empty dir is valid). Back up `servers/` per server outside git.
- Cert lifecycle: certbot `renew` every 12h; nginx reload every 6h via `nginx/99-autoreload.sh`. LE certs valid 90 days, rate limit ~50/week — set `staging=1` in `init-letsencrypt.sh` when testing.
- `init-letsencrypt.sh` bootstrap needs dummy cert because nginx won't start without one; requires DNS already pointing at server and ports 80+443 open. It reads `.env` (`APP_DOMAIN`, `SSL_EMAIL`, optional `PORTAINER_DOMAIN`); idempotent (skips domains with a real cert). Further extra domains use the manual `certonly` flow in `nginx-platform/README.md`.
- `portainer-platform/docker-compose.yml` mounts certs from `${CERTBOT_BASE_DIR}/live|archive/portainer.${APP_DOMAIN}` and defaults `PORTAINER_COMMAND` to `-H unix:///var/run/docker.sock --tlscert/--tlskey ...` (LE layout). Custom layout (e.g. `/certs/<domain>/cert.pem`) or plain HTTP = set `PORTAINER_COMMAND` in `.env`, no compose edit. Has `portainer_stack:/stack` named volume.
- Portainer READMEs show `docker-compose` (v1); use `docker compose` (v2) — prereq is Compose ≥2.0, Docker ≥20.10.
- Gitignored, never commit: `.env`, `volumes/`, `**/certbot` (live certs/keys).
- Volumes follow the active `_nfs`/`_dir` pair pattern: both are always declared, `${*_VOLUME_TYPE:-dir}` in the service mount switches which one is used (e.g. `portainer_data_${PORTAINER_VOLUME_TYPE:-dir}:/data`). All `*_VOLUME_IP`/`*_PATH` vars must be set in `.env` (see `.env.example`). `dir` = `type: none` + `o: bind` → `device` MUST be absolute and exist (`mkdir -p` first — the local driver won't create it; `init-letsencrypt.sh` does this for certbot paths). `nfs` = `type: nfs` + `o: "addr=${IP},nolock,soft,rw"` + `device: ":${PATH}"`. Unused pair member is ignored by compose (verified: `up` only creates the mounted one).
- Portainer TLS mounts (`${CERTBOT_BASE_DIR}/live|archive/portainer.${APP_DOMAIN}`) must equal nginx `CERTBOT_CONF_VOLUME_PATH` on the same host — dir mode only. NFS-mode certbot + portainer TLS = unsupported without copying certs; use plain HTTP (`PORTAINER_COMMAND=-H unix:///var/run/docker.sock`) instead.
- CORS is generated, never hand-edited: `nginx/90-generate-cors.sh` (entrypoint.d, runs before `99-autoreload.sh`) builds `cors-map.conf` (`$CORS_ALL_ALLOWED_DOMAIN`) from `CORS_BASE_DOMAINS` (apex + all subdomains via regex, space-separated, quoted) and `CORS_EXTRA_ORIGINS` (one-offs). The map lives in the `cors_map_${CORS_VOLUME_TYPE:-dir}` volume mounted at `/etc/nginx/cors.d/` (custom `nginx/nginx.conf` includes it) — mid-run addition = edit the file + `exec nginx -s reload`, no recreate. Recreate regenerates from `.env`, so manual edits are ephemeral until moved there. New subdomain under a listed base = zero config.
- TLS policy is centralized (Mozilla intermediate) in `nginx/nginx.conf` http block — inherited by all server blocks. No per-server `include`/`ssl_dhparam`, no vendored files, no downloads. DHE ciphers are not offered.
- Network name `your-domain` is only the default of `${NETWORK_NAME}` — compose keys are NOT interpolated, so the key stays `shared` and the real name comes from `name:`. Renaming = set `NETWORK_NAME` in both `.env` files, nothing else.

## Verify

```bash
docker compose config    # per platform dir, catches env/network/volume errors
docker compose logs nginx certbot
docker compose logs portainer
```

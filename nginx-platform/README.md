# SSL Setup with Certbot + Nginx in Docker

This setup allows you to configure SSL with Let's Encrypt using Certbot and Nginx as reverse proxy in a Docker environment.

## Prerequisites

- Docker and Docker Compose installed
- Domain name that points to your server
- Port 80 and 443 open in firewall

## Directory Structure

```
.
├── docker-compose.yml
├── .env (create from .env.example)
├── .env.example
├── init-letsencrypt.sh
├── nginx/
│   ├── secure/
│   │   ├── default.conf.template          # Main domain
│   │   ├── domain-b.conf.template          # Additional domain (optional)
│   │   └── domain-c.conf.template          # Additional domain (optional)
│   ├── certbot/
│   │   ├── conf/
│   │   │   ├── live/                       # Active certificates
│   │   │   │   ├── domain-a.com/
│   │   │   │   └── domain-b.com/
│   │   │   └── archive/                    # Archived certificates
│   │   └── www/                            # Webroot for validation
│   └── 99-autoreload.sh
└── README.md
```

## Configuration

### 1. Setup Environment Variables

Copy `.env.example` file to `.env` and adjust with your domain and email:

```bash
cp .env.example .env
```

Edit `.env` file:

```env
APP_DOMAIN=your-domain.com
SSL_EMAIL=contact@your-domain.com
# Optional: second domain for the Portainer dashboard (see Usage below).
#PORTAINER_DOMAIN=portainer.example.com
```

### 1b. Volumes & Network (env-driven)

All data volumes follow the `_nfs`/`_dir` pair pattern — both are declared in
`docker-compose.yml`, `CERTBOT_VOLUME_TYPE` (`dir` | `nfs`) switches which one
is mounted. All `CERTBOT_VOLUME_*` vars must be set (see `.env.example`).
`dir` mode binds an absolute host path — create it first (`mkdir -p`); the
`init-letsencrypt.sh` script does this automatically. `NETWORK_NAME` sets the
shared Docker network (also auto-created by the init script). CORS origins
come from `CORS_BASE_DOMAINS` / `CORS_EXTRA_ORIGINS` — generated at container
start by `nginx/90-generate-cors.sh`, never hand-edit the map.

### 2. Update Docker Compose

Edit `docker-compose.yml` and adjust:
- Network name (`your-app-network`) with your application network
  - If network doesn't exist, change `external: true` to `external: false` in networks section
- Service name (`your-app`) with your application service name in `depends_on` section
- Application port (`3000`) with the port used by your application

### 3. Update Nginx Configuration

Edit `nginx/secure/default.conf.template` and adjust:
- `proxy_pass http://my-app:3000;` with your service name and application port

## Usage

Script responsibilities — jangan tertukar:

- `./init.sh` — menyalakan service (network + `docker compose up -d`). Ini yang dipakai sehari-hari dan untuk pertama kali menyalakan nginx.
- `./init-letsencrypt.sh` — hanya urus sertifikat (dummy → request → reload). Idempoten: domain yang sudah punya cert asli di-skip.

### Initial Setup (First Time)

1. Make sure domain points to your server
2. Copy env dan isi nilai:

```bash
cp .env.example .env
```

`APP_DOMAIN` wajib. `PORTAINER_DOMAIN` opsional — isi jika server ini juga reverse-proxy Portainer (template `nginx/secure/portainer.conf.template` memakainya); jika tidak dipakai, hapus file template tersebut (lihat catatan templating di bawah).

3. Run initialization script:

```bash
chmod +x init.sh init-letsencrypt.sh
./init-letsencrypt.sh
```

This script will (for `APP_DOMAIN`, plus `PORTAINER_DOMAIN` when set):
- Skip domains that already have a real certificate
- Create dummy certificate(s) to start Nginx
- Delete dummy certificate(s)
- Request real Let's Encrypt certificate(s)
- Reload Nginx with new certificate(s)

4. Start the service (juga untuk restart rutin / sehabis reboot):

```bash
./init.sh
```

### Running Application

After initial setup, untuk menyalakan service:

```bash
./init.sh
```

(ekuivalen `docker compose up -d` + pastikan network ada). Untuk log: `docker compose logs nginx certbot`.

### Template authoring rules (`nginx/secure/*.conf.template`)

- Image nginx me-render hanya variabel yang ADA di environment container (`env_file: .env`) — `${VAR}` yang tidak ada di `.env` lolos mentah ke config dan bikin nginx `emerg`. Jadi: setiap `${VAR}` di template wajib ada di `.env` (walau kosong terdokumentasi), dan file template yang var-nya tidak diisi harus dihapus.
- Variabel bawaan nginx (`$host`, `$request_uri`, `$http_upgrade`, …) AMAN dibiarkan apa adanya — jangan di-escape jadi `$$` (itu justru merusak config).
- Proxy ke container yang belum tentu jalan saat nginx start (contoh: `portainer`) wajib pakai pola lazy-DNS agar nginx tidak crash-loop `host not found in upstream`:

```nginx
resolver 127.0.0.11 valid=30s;
set $backend_nama service-name;
proxy_pass http://$backend_nama:9000;
```

### Reload vs restart vs up -d (kapan pakai apa)

| Perubahan | Perintah | Kenapa |
|---|---|---|
| File baru/ubah di `nginx/servers/` (mount sudah ada) | `docker compose exec nginx nginx -s reload` | include wildcard dibaca ulang, tanpa downtime |
| Ubah isi `nginx/secure/*.template` | `docker compose restart nginx` | template di-render ulang oleh entrypoint |
| Ubah `.env`, tambah mount/volume, `docker-compose.yml` | `docker compose up -d` | container harus recreate agar env/mount baru kepakai (`restart`/`reload` tak mempan) |
| Cert baru terbit | otomatis oleh `init-letsencrypt.sh` (reload di akhir) | — |

## Cookbook (step-by-step per kebutuhan)

Aturan umum semua resep: DNS dulu → file config → cert → reload/up → verify.
Semua contoh memakai pola lazy-DNS (backend boleh belum jalan saat nginx start).

### 0. Pasang nginx di server baru (fresh install)

```bash
git clone <repo> stacks/devops && cd stacks/devops/nginx-platform
cp .env.example .env && nano .env   # APP_DOMAIN, SSL_EMAIL, NETWORK_NAME, volume *_TYPE=dir untuk data lokal
# DNS: pastikan APP_DOMAIN (+ www kalau dipakai) A-record ke IP server ini
# Firewall: buka 80 + 443 (ufw + panel VPS)
chmod +x init.sh init-letsencrypt.sh
./init-letsencrypt.sh   # dummy → request LE → reload (cover APP_DOMAIN + PORTAINER_DOMAIN bila diisi)
./init.sh               # start rutin (dipakai juga sehabis reboot)
curl -sI http://$APP_DOMAIN/.well-known/acme-challenge/x  # 404 = port 80 terbuka & nginx jawab
curl -sI https://$APP_DOMAIN/                             # 404/200 = TLS jalan
```

### 1. Config nginx untuk Portainer

Template generiknya sudah ikut repo (`nginx/secure/portainer.conf.template`,
pakai `${PORTAINER_DOMAIN}` — tanpa hardcode domain):

```bash
# 1. nginx-platform/.env:
PORTAINER_DOMAIN=portainer.example.com
# 2. DNS portainer.example.com → IP server
# 3. Terbitkan cert + render template:
./init-letsencrypt.sh
docker compose up -d   # sekali saja, agar env baru ke-mount dan template ke-render
# 4. Verify:
curl -sI https://portainer.example.com/   # 200/307 dari Portainer = ok
```

Backend Portainer jalan plain HTTP (`PORTAINER_COMMAND="-H unix:///var/run/docker.sock"`
di `portainer-platform/.env`), TLS berhenti di nginx. Kalau server ini tidak
pakai Portainer: kosongkan `PORTAINER_DOMAIN` DAN hapus `portainer.conf.template`
(atau server tidak akan start — lihat template rules di atas).

### 2. Config nginx untuk service aplikasi baru

Contoh: aplikasi `myapp:8000` di network yang sama (`NETWORK_NAME`).
JANGAN taruh di `secure/*.template` (itu untuk blok generik env-driven) —
pakai overlay gitignored `nginx/servers/myapp.conf`:

```nginx
server {
    listen 80;
    server_name myapp.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name myapp.example.com;

    server_tokens off;
    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/myapp.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myapp.example.com/privkey.pem;

    location / {
        resolver 127.0.0.11 valid=30s;
        set $myapp_backend myapp;
        proxy_pass http://$myapp_backend:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # CORS langsung dari map front:
        add_header 'Access-Control-Allow-Origin' $CORS_ALL_ALLOWED_DOMAIN always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
    }
}
```

```bash
# 1. DNS myapp.example.com → IP server
# 2. Tulis file di atas sebagai nginx/servers/myapp.conf
# 3. Cert (manual, sekali per nama baru):
docker compose run --rm --entrypoint "certbot certonly --webroot -w /var/www/certbot \
  --email you@example.com -d myapp.example.com \
  --rsa-key-size 4096 --agree-tos --no-eff-email --force-renewal" certbot
# 4. Reload saja (tanpa recreate) — kecuali folder servers/ belum pernah ada saat
#    container dibuat, maka mkdir + `docker compose up -d` sekali:
docker compose exec nginx nginx -s reload
# 5. Verify:
curl -sI https://myapp.example.com/
```

### 3. URL baru dengan prefix `api-` (mis. `api.example.com`)

Sama persis seperti resep 2 dengan `server_name api.example.com`.
Dua catatan:

- Subdomain dari base yang sudah terdaftar di `CORS_BASE_DOMAINS` otomatis
  lolos CORS — tanpa config tambahan. Base baru → tambah ke `.env` +
  `docker compose up -d` (render ulang map).
- Cert: boleh lineage terpisah (`-d api.example.com` saja) atau digabung SAN
  dengan domain lain dalam satu `certonly`. Kalau digabung, nama `-d` PERTAMA
  menentukan folder `live/` — jangan ubah urutannya di renewal berikutnya
  (path cert di config mengacu ke folder itu).

### 4. Domain baru di satu server (mis. apex + www)

Sama seperti resep 2, dengan `server_name domainbaru.com www.domainbaru.com`
dan satu cert SAN mencakup keduanya:

```bash
docker compose run --rm --entrypoint "certbot certonly --webroot -w /var/www/certbot \
  --email you@example.com -d domainbaru.com -d www.domainbaru.com \
  --rsa-key-size 4096 --agree-tos --no-eff-email --force-renewal" certbot
docker compose exec nginx nginx -s reload
```

Batasan Let's Encrypt: ~50 cert/minggu per domain — untuk latihan pakai
`STAGING=1` di `.env` lalu `./init-letsencrypt.sh` (staging hanya untuk
APP_DOMAIN/PORTAINER_DOMAIN).

## Multiple Domain Setup

This setup supports **multiple domains/subdomains** on the same server. Each domain can have its own configuration and SSL certificate.

### How to Add New Domain

#### 1. Create Template File for New Domain

Create a new file in `nginx/secure/` with format `domain-name.conf.template`:

```bash
cd /home/hafdiz/sdk/devops/nginx-platform
nano nginx/secure/domain-b.conf.template
```

Example content for Domain B:

```nginx
server {
    listen 80;
    server_name domain-b.com www.domain-b.com;

    location / {
        return 301 https://$host$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}

server {
    listen 443 ssl;
    server_name domain-b.com www.domain-b.com;

    server_tokens off;
    client_max_body_size 20M;

    ssl_certificate /etc/letsencrypt/live/domain-b.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/domain-b.com/privkey.pem;

    location / {
        proxy_pass http://app-domain-b:3000;  # Domain B application service name
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Important Notes:**
- Replace `domain-b.com` with your domain
- Replace `app-domain-b` with application service name in docker-compose
- Replace port `3000` with your application port

#### 2. Generate SSL Certificate for New Domain

```bash
cd /home/hafdiz/sdk/devops/nginx-platform
export SSL_EMAIL=your@gmail.com
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email ${SSL_EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d domain-b.com \
    -d www.domain-b.com" certbot
```

**For subdomain:**
```bash
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email ${SSL_EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d subdomain.domain-b.com" certbot
```

#### 3. Restart Nginx

```bash
docker compose restart nginx
```

### Where to put per-server domains (template stays generic)

This repo is a reusable template — never commit real domains here.
Drop server-specific statics in `nginx/servers/*.conf` (gitignored overlay,
reloaded with `docker compose exec nginx nginx -s reload`, no recreate).
Use `nginx/secure/*.conf.template` only for env-driven generic blocks.

### File Structure for Multiple Domains

```
nginx-platform/nginx/secure/
├── default.conf.template              # Main domain (your-domain.com)
├── domain-b.conf.template             # Domain B (domain-b.com)
├── domain-c.conf.template             # Domain C (domain-c.com)
└── api.domain-b.conf.template         # Subdomain (api.domain-b.com)
```

### Benefits of Multiple Domain Setup

1. **Flexible**: Add new domain just by creating a new template file
2. **Auto-generate**: Nginx automatically processes all `.template` files in `secure/` folder
3. **SSL per Domain**: Each domain has its own SSL certificate
4. **Auto-renewal**: Certbot automatically renews all certificates
5. **Isolation**: Each domain configuration is separate, easy to manage

### Removing Domain

To remove domain from Nginx:

1. **Delete template file:**
```bash
rm nginx/secure/domain-b.conf.template
```

2. **Restart Nginx:**
```bash
docker compose restart nginx
```

3. **(Optional) Delete certificate:**
```bash
rm -rf nginx/certbot/conf/live/domain-b.com
rm -rf nginx/certbot/conf/archive/domain-b.com
```

### Important Notes for Multiple Domains

- **DNS Configuration**: Make sure each domain's DNS points to the same server IP
- **Port Management**: All domains use the same port 80 and 443
- **Service Name**: Make sure service name in `proxy_pass` matches the service name in docker-compose
- **Network**: All applications must be on the same Docker network (`your-domain`)
- **Certificate Limit**: Let's Encrypt has rate limit (50 certificates per domain per week)

## Features

- **Auto-renewal**: Certbot automatically renews certificate every 12 hours
- **Auto-reload**: Nginx automatically reloads every 6 hours to apply new certificates
- **HTTP to HTTPS redirect**: All HTTP traffic is automatically redirected to HTTPS
- **SSL termination**: Nginx handles SSL and proxies requests to backend application
- **Multiple Domain Support**: Supports multiple domains/subdomains with separate configurations

## Troubleshooting

1. **Certificate not generated**: Make sure domain points to server and port 80 is open
2. **Nginx cannot start**: Check logs with `docker compose logs nginx`
3. **Certificate renewal failed**: Check certbot logs with `docker compose logs certbot`

## Important Notes

- Make sure your application service is running before running init script
- For testing, set `staging=1` in `init-letsencrypt.sh` to avoid rate limit
- Let's Encrypt certificate is valid for 90 days and will auto-renew before expiration

## SSL Setup Flow Explanation

### Overview Flow

This setup uses **Let's Encrypt** (via Certbot) to get free SSL certificate, and **Nginx** as reverse proxy that handles SSL termination.

### Flow Detail (Step-by-Step)

#### **Phase 1: Initial Setup (init-letsencrypt.sh)**

1. **Create Dummy Certificate**
   - TLS policy (Mozilla intermediate) already lives in `nginx/nginx.conf`, so no per-server TLS files are needed.
   - Create dummy (self-signed) certificate with OpenSSL
   - **Why?** Nginx cannot start without certificate. So we create dummy first so Nginx can run
   - This certificate is only valid for 1 day and only for localhost

3. **Start Nginx with Dummy Certificate** (Lines 45-46)
   - Nginx starts with dummy certificate
   - Now Nginx can receive requests on port 80 and 443

4. **Delete Dummy Certificate** (Lines 50-54)
   - Delete dummy certificate because we will request the real one from Let's Encrypt

5. **Request Real Certificate from Let's Encrypt** (Lines 58-81)
   - Certbot uses **webroot method** (`--webroot -w /var/www/certbot`)
   - Let's Encrypt will validate domain by accessing `http://your-domain.com/.well-known/acme-challenge/`
   - Nginx is already configured to serve this path from `/var/www/certbot` (see `default.conf.template` lines 9-11)
   - After validation succeeds, certificate will be saved at `/etc/letsencrypt/live/your-domain/`

6. **Reload Nginx** (Line 86)
   - Reload Nginx to use the new certificate

#### **Phase 2: Runtime Operations**

1. **Nginx Container** (docker-compose.yml lines 2-22)
   - Mount `nginx/secure/` folder to `/etc/nginx/templates/`
   - Nginx will automatically convert `.template` files to actual configuration
   - Environment variable `${APP_DOMAIN}` will be substituted from `.env` file
   - Auto-reload every 6 hours via `99-autoreload.sh` to apply new certificates

2. **Certbot Container** (docker-compose.yml lines 23-31)
   - Running in background with infinite loop
   - Every 12 hours, runs `certbot renew` to check and renew certificate if needed
   - Let's Encrypt certificate is valid for 90 days, but will auto-renew before expiration

3. **Auto-reload Script** (99-autoreload.sh)
   - Script mounted to `/docker-entrypoint.d/99-autoreload.sh`
   - Nginx will automatically execute this script when container starts
   - This script will reload Nginx every 6 hours to apply new certificates that have been renewed

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    INITIAL SETUP FLOW                        │
└─────────────────────────────────────────────────────────────┘

1. Create Dummy Certificate (self-signed)
   └─> Nginx can start

3. Start Nginx Container
   └─> Nginx running with dummy cert

4. Delete Dummy Certificate
   └─> Ready for real certificate

5. Request Certificate from Let's Encrypt
   └─> Let's Encrypt validate via /.well-known/acme-challenge/
   └─> Certificate saved at /etc/letsencrypt/live/domain/

6. Reload Nginx
   └─> Nginx uses real certificate

┌─────────────────────────────────────────────────────────────┐
│                    RUNTIME FLOW                              │
└─────────────────────────────────────────────────────────────┘

User Request
   │
   ├─> HTTP (port 80)
   │   └─> Nginx redirect to HTTPS (301 redirect)
   │
   └─> HTTPS (port 443)
       └─> Nginx validate SSL certificate
       └─> Proxy to backend application (if configured)

Certbot Container (Background)
   │
   └─> Every 12 hours: certbot renew
       └─> Check certificate expiry
       └─> Renew if needed (< 30 days before expiration)

Nginx Auto-reload (Background)
   │
   └─> Every 6 hours: nginx -s reload
       └─> Apply new certificates that have been renewed
```

## "secure" Folder Explanation

### What is `nginx/secure/` Folder?

The `secure` folder is **a folder containing Nginx configuration for secure HTTPS/SSL connections**. The name "secure" refers to:

1. **Secure Connection (HTTPS)**
   - Configuration to handle HTTPS connections (port 443)
   - SSL/TLS termination (Nginx handles SSL, then forwards requests to backend via HTTP)

2. **Security Best Practices**
   - SSL configuration following best practices (TLS protocols, cipher suites)
   - HTTP to HTTPS redirect to force all traffic to use HTTPS
   - Security headers (if added)

### Configuration Structure in `default.conf.template`

```nginx
# Server Block 1: HTTP (port 80)
server {
    listen 80;
    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
    # Specifically for Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}

# Server Block 2: HTTPS (port 443) - SECURE CONNECTION
server {
    listen 443 ssl;
    # SSL Certificate configuration
    ssl_certificate /etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem;
    # Proxy to backend application (if configured)
}
```

### Why Use `.template`?

Files use `.template` extension because:

1. **Environment Variable Substitution**
   - Nginx container will automatically substitute `${APP_DOMAIN}` with value from `.env`
   - Uses `envsubst` which is built-in in Nginx Docker image

2. **Dynamic Configuration & Multiple Domain Support**
   - Can be used for multiple domains without manually editing files
   - Each `.template` file will automatically be generated into a separate `.conf` file
   - Just add a new template file for a new domain, Nginx will automatically process it
   - Environment variable `${APP_DOMAIN}` will be substituted from `.env` file (for default.conf.template)

### Volume Mounting

In `docker-compose.yml` line 13:
```yaml
volumes:
  - ./nginx/secure/:/etc/nginx/templates/
```

This means:
- All `.template` files in `nginx/secure/` will be copied to `/etc/nginx/templates/` in container
- Nginx will automatically process **all** `.template` files and generate `.conf` files in `/etc/nginx/conf.d/`
- Each template file will become a separate configuration file:
  - `default.conf.template` → `/etc/nginx/conf.d/default.conf`
  - `domain-b.conf.template` → `/etc/nginx/conf.d/domain-b.conf`
  - `domain-c.conf.template` → `/etc/nginx/conf.d/domain-c.conf`
- All configurations will be active simultaneously

### Alternative Folder Names

If you want to be more explicit, this folder can also be named:
- `nginx/https/` - clearer that this is for HTTPS
- `nginx/ssl/` - focus on SSL
- `nginx/tls/` - using TLS terminology (more modern)

But `secure` is descriptive enough and commonly used.


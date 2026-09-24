# DOCKER-PATTERN.md — pola baku service di bawah nginx-platform

Dokumen ini hasil analisa `portofolio` vs pola `devops` (nginx-platform +
portainer-platform). Semua service baru (movie-explorer, pokedex, dsb.)
mengikuti pola ini supaya seragam: env-driven, TLS terpusat, CORS terpusat.

## Prinsip

1. **Front nginx (`devops`) terminasi TLS + whitelist + emit CORS.** Service
   tidak pernah pegang cert, tidak pernah listen 443, tidak emit CORS sendiri.
2. **Dua opsi service, pilih satu dan konsisten per service:**
   - **Opsi B — tanpa sidecar (default).** App container polos, front proxy
     langsung ke `http://<app>:3000` dan emit CORS. Untuk app HTTP biasa.
   - **Opsi A — sidecar nginx sendiri.** Service bawa `nginx/` + sidecar
     (lihat "Opsi A" di bawah). Untuk rewrite path, caching rule khusus,
     protokol non-HTTP, header logic yang tidak boleh front tahu, atau
     service yang harus bisa jalan standalone tanpa front.
3. **Semua yang beda antar server/mesin = env var.** Tidak ada domain, IP,
   atau path absolut yang di-hardcode di compose.

## Struktur baku

```
<service>/
├── docker-compose.yml
├── .env.example          # template; `.env` hasil copy TIDAK di-commit
├── .env                  # gitignored, per server
├── Dockerfile            # multi-stage, non-root user untuk production
├── nginx/                  # HANYA Opsi A: nginx.conf + default.conf sidecar
└── DOCKER-PATTERN.md     # file ini (boleh symlink kalau mau 1 sumber)
```

Sidecar nginx hanya untuk kasus khusus (rewrite path, caching rule khusus,
protokol non-HTTP) — bukan default.

## docker-compose.yml referensi

```yaml
services:
  <name>-app:
    # Image SELALU disebut eksplisit (lihat "Kontrak versi image").
    # Dev lokal / Portainer Repository: blok build jalan, hasilnya di-tag nama ini.
    # Swarm/stack: blok build diabaikan, image di-pull dari registry.
    image: ghcr.io/<owner>/<repo>:${<APP>_VERSION:-latest}
    build:
      context: .
      dockerfile: ./Dockerfile
    pull_policy: build
    container_name: <name>-app
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - NEXT_TELEMETRY_DISABLED=1
    healthcheck:
      test:
        ["CMD", "wget", "--no-proxy", "-q", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 512M
    networks:
      - shared
    labels:
      - "com.docker.compose.project=<name>"
      - "com.docker.compose.service=<name>"

networks:
  shared:
    name: ${NETWORK_NAME:-your-domain}
    external: true
```

`.env.example` referensi:

```env
# Domain publik service ini (dokumentasi + acuan template front di devops).
<NAME>_DOMAIN=<service>.example.com
# WAJIB sama dengan NETWORK_NAME nginx-platform di server yang sama.
NETWORK_NAME=your-domain
# Versi image yang jalan (lihat "Kontrak versi image"). Selalu pin eksplisit
# di server produksi — jangan biarkan fallback latest.
<APP>_VERSION=0.0.0
```

## Kontrak versi image (wajib)

Satu variabel `<APP>_VERSION` mengikat seluruh lifecycle rilis:

```
deploy.sh bump → git tag → workflow publish → <APP>_VERSION di server → redeploy
```

1. **Sumber versi:** `package.json` (Node) atau file `VERSION` (Go/Rust/
   lainnya). `deploy.sh` membaca + bump keduanya otomatis (override:
   `VERSION_FILE=`, deteksi stack otomatis).
2. **Publish (workflow `docker-publish.yml`):** tiap tag git menerbitkan 3
   tag image ke GHCR — `:latest`, `:<versi-tanpa-v>`, `:<sha>`. Nama image
   diambil dari repo (`ghcr.io/<owner>/<repo>`), bukan hardcode.
3. **Konsumsi (compose):** `image: ghcr.io/<owner>/<repo>:${<APP>_VERSION}`.
   Deploy versi X = isi `<APP>_VERSION=X` di `.env` server lalu redeploy.
   Rollback = isi versi lama + redeploy. Tidak ada tebak-tebakan.
4. **Aturan:**
   - Produksi/stack: `<APP>_VERSION` WAJIB pin eksplisit. Bare `:latest`
     tidak deterministik (arti latest berubah tiap publish) — hanya boleh
     sebagai fallback lokal (`:-latest`).
   - Tag `:sha` untuk debug insiden ("yang jalan sha berapa?"), bukan untuk
     deploy rutin.
   - `deploy.sh` + tag git adalah satu-satunya jalan versi baru masuk.
     Jangan `docker tag`/`push` manual ke GHCR — riwayat versi jadi lubang.

## Kontrak app Opsi B (wajib)

- **Dilarang** `listen 443`, `ssl_certificate`, atau publish `ports:`.
  Yang boleh buka port ke luar hanya front nginx (`devops`).
- App listen HTTP di port internal (3000). Healthcheck wajib ada.
- **CORS diurus 100% oleh front** (map `$CORS_ALL_ALLOWED_DOMAIN` + header
  di server block front). App tidak perlu header CORS / preflight handler.
  Kalau framework memaksa (misal API perlu header sendiri), koordinasikan
  supaya tidak dobel dengan front.

## Blok front per service (di `devops/nginx/servers/<domain>.conf`)

```nginx
server {
    listen 80;
    server_name <domain> www.<domain>;
    location / { return 301 https://$host$request_uri; }
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
}

server {
    listen 443 ssl;
    server_name <domain> www.<domain>;

    server_tokens off;
    client_max_body_size 2048m;

    ssl_certificate /etc/letsencrypt/live/<domain>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;

    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;
    proxy_read_timeout 900s;
    send_timeout 900s;
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        proxy_pass http://<name>-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        add_header 'Access-Control-Allow-Origin' $CORS_ALL_ALLOWED_DOMAIN always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;

        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' $CORS_ALL_ALLOWED_DOMAIN always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
}
```

(Tanpa `include`/`ssl_dhparam` — kebijakan TLS sentral di `nginx.conf` front.)

## Opsi A — sidecar nginx sendiri

Gunakan Opsi B kecuali service-mu butuh salah satu ini: rewrite path,
caching/static rule khusus, protokol non-HTTP, header logic milik service,
atau jalan standalone tanpa front. Kalau tidak butuh semuanya → Opsi B.

Compose tambah satu service (app tetap sama seperti referensi):

```yaml
services:
  <name>-nginx:
    image: nginx:alpine
    container_name: <name>-nginx
    restart: unless-stopped
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - <name>-app
    networks:
      - shared
```

Kontrak sidecar (wajib):

- `listen 80` saja, tanpa `ports:`, tanpa TLS. Satu-satunya yang buka port
  ke luar adalah front.
- `proxy_pass http://<name>-app:<port>;` + header standar + WebSocket.
- **CORS: emit dari header front, jangan whitelist sendiri.** Front kirim
  `proxy_set_header X-CORS-Allowed-Domain $CORS_ALL_ALLOWED_DOMAIN;`,
  sidecar cetak apa adanya:

```nginx
add_header 'Access-Control-Allow-Origin' $http_x_cors_allowed_domain always;
add_header 'Access-Control-Allow-Credentials' 'true' always;
add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;

if ($request_method = 'OPTIONS') {
    add_header 'Access-Control-Allow-Origin' $http_x_cors_allowed_domain always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    add_header 'Access-Control-Max-Age' 1728000;
    add_header 'Content-Type' 'text/plain; charset=utf-8';
    add_header 'Content-Length' 0;
    return 204;
}
```

> Header itu datang dari client — sidecar WAJIB tanpa published ports.
> Selama hanya reachable via network internal, nilainya dijamin front proxy.
> Kalau sidecar terekspos langsung, client bisa spoof
> `X-CORS-Allowed-Domain` dan lolos CORS. (Opsional: sederhanakan tanpa
> `map` pass-through — pakai variabel header langsung.)

## Service stateful (butuh volume)

Ikuti pola `devops` persis — pasangan `_nfs`/`_dir`, switch satu var:

```yaml
volumes:
  - <name>_data_${<NAME>_VOLUME_TYPE:-dir}:/data
volumes:
  <name>_data_nfs:
    driver: local
    driver_opts:
      type: nfs
      o: "addr=${<NAME>_VOLUME_IP},nolock,soft,rw"
      device: ":${<NAME>_VOLUME_PATH}"
  <name>_data_dir:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${<NAME>_VOLUME_PATH}
```

Aturan: `dir` wajib path absolut + sudah `mkdir -p` (driver tidak buatkan);
`nfs` wajib server NFS beneran (localhost bukan NFS server — pakai `dir`).

## Mendaftarkan service baru ke front (runbook)

Detail nya bisa baca README.md di nginx-platform, untuk mempersimple kita 
menyediakan add-site.sh

1. DNS domain → IP server.
2. Deploy stack service dulu (Repository mode di Portainer — JANGAN web
   editor: web editor tidak bawa file repo sehingga mount/build gagal).
3. `devops/nginx/servers/<domain>.conf` (gitignored, per server) ikut blok
   di atas; `proxy_pass` ke `<nama-container-app>:<port>`.
4. Cert: `certbot certonly --webroot ... -d <domain>` dari `nginx-platform`.
5. CORS: tambah base ke `CORS_BASE_DOMAINS` kalau base baru (subdomain dari
   base terdaftar = otomatis, tanpa apa-apa).
6. `docker compose up -d` di `nginx-platform` (recreate sekali), atau
   `exec nginx nginx -s reload` untuk edit file `servers/` yang sudah ada.

## Yang dilarang (temuan di portofolio)

- ❌ `version: 'x.y'` di compose — obsolete, compose v2 abaikan + warning.
  Hapus.
- ❌ Env mati (tidak dikonsumsi apa pun): `VIRTUAL_HOST`, `VIRTUAL_PORT`,
  `LETSENCRYPT_HOST`, `LETSENCRYPT_EMAIL`, `CORS_ALLOWED_DOMAIN`. Hapus.
- ❌ Nama network hardcode — pakai pola `shared` + `name: ${NETWORK_NAME}`.
- ❌ Sidecar tanpa alasan (lihat panduan pilih opsi di Prinsip #2) — app HTTP
  polos = Opsi B. Sidecar yang emit CORS dari header wajib tanpa published
  ports (risiko spoof, lihat Opsi A).
- ❌ `bun.lock` di `.dockerignore` + glob `bun.lockb*` di Dockerfile yang
  tidak match `bun.lock` — kombinasi ini bikin build gagal total. Lockfile
  wajib masuk build context.

## Deploy via Portainer

- Selalu mode **Repository** (URL + branch + path compose). Web editor hanya
  bawa YAML: semua `volumes: ./...`, `build:`, dan file lain hilang → error
  mount `not a directory` / build gagal.
- Isi env stack (`NETWORK_NAME`, dsb.) di kolom environment variables —
  Portainer tidak baca file `.env` repo otomatis.

## Deploy swarm (zero downtime)

`docker compose up` me-recreate container (stop dulu, baru start) sehingga
ada jeda mati tiap deploy. Untuk zero downtime pakai swarm rolling update
dengan `order: start-first`: task baru wajib healthy dulu, baru task lama
di-stop.

Syarat di compose service app:

```yaml
deploy:
  replicas: 1
  update_config:
    parallelism: 1
    order: start-first
    failure_action: rollback
    monitor: 30s
  rollback_config:
    parallelism: 1
    order: stop-first
  restart_policy:
    condition: on-failure
```

Plus aturan keras: **tanpa `container_name`** (swarm melarang), **tanpa blok
`build`** (swarm tidak bisa build — image wajib dari registry via CI),
healthcheck wajib cepat dan akurat (ini penentu "healthy" untuk start-first).

Runbook sekali saja di server:

```bash
docker swarm init --advertise-addr <ip-server>
# network shared WAJIB overlay + attachable agar service swarm dan
# container front (standalone) bisa satu network:
docker network create --driver overlay --attachable <nama-network>
# kalau network bridge lama bernama sama sudah ada: pindahkan semua container
# front ke network baru (atau disconnect, rm network lama, create ulang).
docker stack deploy -c docker-compose.yml <stack>
```

Deploy/update rutin: `docker stack deploy -c docker-compose.yml <stack>`
ulang (atau webhook Portainer ke swarm stack) → rolling update otomatis.
**Jangan** `docker compose up` ke file yang sama — plain compose abaikan
`update_config` sehingga zero-downtime hilang.

### Syarat sekali per server

```bash
docker swarm init
# Network BERSAMA wajib overlay + attachable (standalone container nginx/
# portainer ikut nempel di sini). Migrasi dari bridge = recreate network:
docker compose -f nginx-platform/docker-compose.yml down
docker compose -f portainer-platform/docker-compose.yml down
docker network rm devops
docker network create --driver overlay --attachable devops
./nginx-platform/init.sh && ./portainer-platform/init.sh
```

### Deploy app sebagai stack (BUKAN compose up)

`docker compose up` mengabaikan blok `deploy.update_config` — rolling
zero-downtime hanya terjadi via `docker stack deploy`:

```bash
NETWORK_NAME=devops docker stack deploy -c portfolio-stack.yml portfolio
docker service ls   # 2/2 = sehat
```

Aturan stack file: tanpa `build` (swarm tidak bisa build — image dari
registry via CI), tanpa `container_name` (dilarang swarm), `update_config`
dengan `order: start-first` + healthcheck yang benar (cek port app, bukan
`exit 0` buta). Contoh lengkap: pola di bawah "docker-compose.yml referensi"
tetap berlaku, tinggal bungkus service app-nya dengan blok `deploy`.

### Registry auth (wajib untuk update image)

Bisa di lakukan langsung di portainer agar lebih dynamic ataupun lewat cli

Scheduler swarm me-resolve image dari registry. GHCR privat tanpa login =
`denied`. Sebelum deploy dari image baru:

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <user> --password-stdin
```

Darurat tanpa akses registry (single-node saja): retag image lokal ke nama
yang dipakai stack lalu deploy dengan `--resolve-image never`. Cara ini
tidak mendeteksi image baru — jangan untuk produksi rutin.

### Migrasi dari stack Portainer standalone

Stop + hapus container lama DULU (nama bentrok tidak ada, tapi dua sumber
deploy = bingung), baru `stack deploy`. Stack lama di UI Portainer akan
terlihat Stopped — hapus manual di UI agar tidak diklik `Start` tidak sengaja.
Proxy nginx tidak perlu diubah: hostname service swarm di-resolve ke VIP
oleh pola lazy-DNS yang sudah ada.


## Verify per service

```bash
docker compose config                    # render bersih, tanpa warning
docker compose up -d && docker compose ps
curl -H "Origin: https://<domain>" -sI http://localhost/   # dari dalam network
```

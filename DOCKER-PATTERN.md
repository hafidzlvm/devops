# DOCKER-PATTERN.md — pola baku service di bawah nginx-platform

Dokumen ini hasil analisa `portofolio` vs pola `devops` (nginx-platform +
portainer-platform). Semua service baru (movie-explorer, pokedex, dsb.)
mengikuti pola ini supaya seragam: env-driven, TLS terpusat, CORS terpusat.

## Prinsip

1. **Front nginx (`devops`) terminasi TLS + whitelist CORS.** Service tidak
   pernah pegang cert, tidak pernah listen 443.
2. **Tiap service = app + sidecar nginx.** Sidecar satu-satunya yang ngomong
   ke front proxy (port 80, HTTP internal). App tidak publish port apa pun.
3. **Semua yang beda antar server/mesin = env var.** Tidak ada domain, IP,
   atau path absolut yang di-hardcode di compose.

## Struktur baku

```
<service>/
├── docker-compose.yml
├── .env.example          # template; `.env` hasil copy TIDAK di-commit
├── .env                  # gitignored, per server
├── Dockerfile            # multi-stage, non-root user untuk production
├── nginx/
│   ├── nginx.conf        # custom conf (lihat kontrak di bawah)
│   └── default.conf      # server_name _ ; proxy ke app; blok CORS
└── DOCKER-PATTERN.md     # file ini (boleh symlink kalau mau 1 sumber)
```

## docker-compose.yml referensi

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

  <name>-app:
    build:
      context: .
      dockerfile: ./Dockerfile
    container_name: <name>-app
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "wget", "--no-proxy", "-q", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
    networks:
      - shared

networks:
  shared:
    name: ${NETWORK_NAME:-your-domain}
    external: true
```

`.env.example` referensi:

```env
APP_DOMAIN=<service>.example.com
NETWORK_NAME=your-domain
```

## Kontrak sidecar nginx (wajib)

- `listen 80` saja. **Dilarang** `listen 443`, `ssl_certificate`, atau
  publish `ports:` di service nginx maupun app. Yang boleh buka port ke luar
  hanya front nginx (`devops`).
- `proxy_pass http://<name>-app:3000;` + header standar (`Host`, `X-Real-IP`,
  `X-Forwarded-For`, `X-Forwarded-Proto`) + blok WebSocket.
- **CORS: emit saja, jangan whitelist.** Whitelist hidup di front map.
  Sidecar baca hasil front dari header dan cetak apa adanya:

```nginx
# $http_x_cors_allowed_domain diisi front proxy HANYA jika Origin lolos map.
# Kosong = header tidak dikirim = browser blokir. Jangan tambah map sendiri.
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

> Kenapa sidecar tidak boleh publish port: header `X-CORS-Allowed-Domain`
> datang dari client. Selama sidecar hanya reachable via network internal,
> nilainya dijamin front proxy. Kalau sidecar terekspos langsung, client bisa
> spoof header itu dan lolos CORS.

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

1. DNS domain → IP server.
2. `devops/nginx-platform/nginx/secure/<service>.conf.template` (server 80 +
   443, `proxy_pass http://<sidecar>:80`, blok acme-challenge).
3. Cert: `certbot certonly --webroot ... -d <domain>` dari `nginx-platform`.
4. CORS: tambah base ke `CORS_BASE_DOMAINS` kalau base baru (subdomain dari
   base terdaftar = otomatis, tanpa apa-apa).
5. `docker compose up -d` di `nginx-platform`, lalu `up -d` di service.

## Yang dilarang (temuan di portofolio)

- ❌ `version: '3.8'` di compose — obsolete, compose v2 abaikan + warning.
  Hapus.
- ❌ Env mati di service nginx: `VIRTUAL_HOST`, `VIRTUAL_PORT`,
  `LETSENCRYPT_HOST`, `LETSENCRYPT_EMAIL` (itu var companion yang tidak ada
  containernya), `CORS_ALLOWED_DOMAIN` (image nginx tidak bisa baca env ke
  conf statis — tanpa mekanisme `.template` var ini tidak dipakai). Hapus
  berlima; CORS ikut kontrak di atas.
- ❌ Nama network hardcode (`solusi-digital-khatulistiwa`) — pakai pola
  `shared` + `name: ${NETWORK_NAME}` supaya compose jalan di server mana pun.
- ❌ `map` pass-through (`default $var-itu-juga`) — tidak ngapa-ngapain,
  pakai variabelnya langsung.

## Verify per service

```bash
docker compose config                    # render bersih, tanpa warning
docker compose up -d && docker compose ps
curl -H "Origin: https://<domain>" -sI http://localhost/   # dari dalam network
```
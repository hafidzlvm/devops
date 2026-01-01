# Portainer Platform

Docker container management platform using Portainer Community Edition.

## Prerequisites

- Docker and Docker Compose installed
- Network `your-domain` already created (or change to `external: false` in docker-compose.yml)

## Setup

1. Copy environment template file:
```bash
cp env.template .env
```

2. Edit `.env` file according to your needs:
```bash
nano .env
```

3. Make sure Docker network is created (if using external network):
```bash
docker network create your-domain
```

4. Run Portainer:
```bash
docker compose up -d
```

## Access Portainer

- Web UI: http://localhost:9000 (or port configured in `.env`)
- Edge Agent (HTTPS): https://localhost:9443

## Nginx Reverse Proxy Configuration

To access Portainer through a domain with SSL/HTTPS, use Nginx as reverse proxy.

### Setup with nginx-platform

1. Make sure `nginx-platform` is running and connected to the same network.

2. Create Nginx configuration file for Portainer at `nginx-platform/nginx/secure/portainer.conf.template`:

```nginx
server {
    listen 80;
    server_name portainer.${APP_DOMAIN};

    location / {
        return 301 https://$host$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}

server {
    listen 443 ssl;
    server_name portainer.${APP_DOMAIN};

    server_tokens off;
    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/portainer.${APP_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/portainer.${APP_DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        return 301 https://$host$request_uri;
    }

    # Edge Agent endpoint (optional)
    location /api/endpoints/ {
        proxy_pass http://portainer:9443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

3. Add subdomain in `.env` file in `nginx-platform`:
```bash
# Add this if not already present
APP_DOMAIN=yourdomain.com
```

4. Generate SSL certificate for Portainer subdomain:
```bash
cd ../nginx-platform
export SSL_EMAIL=your@gmail.com
export APP_DOMAIN=your-domain.com
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email ${SSL_EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d portainer.${APP_DOMAIN}" certbot
```

5. Restart Nginx to apply configuration:
```bash
docker compose restart nginx
```

6. Access Portainer via: `https://portainer.yourdomain.com`

### Standalone Nginx Configuration (without nginx-platform)

If you want to setup Nginx separately, create `nginx/portainer.conf` file:

```nginx
upstream portainer {
    server portainer:9000;
}

server {
    listen 80;
    server_name portainer.${APP_DOMAIN};

    location / {
        return 301 https://$host$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}

server {
    listen 443 ssl;
    server_name portainer.${APP_DOMAIN};

    server_tokens off;
    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/portainer.${APP_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/portainer.${APP_DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        return 301 https://$host$request_uri;
    }
    
    # Edge Agent endpoint (optional)
    location /api/endpoints/ {
        proxy_pass http://portainer:9443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### Important Notes for Nginx Configuration

- **WebSocket Support**: Portainer uses WebSocket for real-time updates, make sure `Upgrade` and `Connection` headers are configured correctly
- **Client Max Body Size**: Set to minimum 50M for file/stack upload
- **Timeouts**: Extend timeout for time-consuming operations
- **SSL**: Use Let's Encrypt for production or valid SSL certificate

## First Time Setup

When accessing Portainer for the first time, you will be asked to:
1. Create admin account
2. Select environment (choose "Docker" for local Docker)

## Configuration

### Environment Variables

- `PORTAINER_PORT`: Port for web UI (default: 9000)
- `PORTAINER_EDGE_PORT`: Port for Edge Agent HTTPS (default: 9443)
- `PORTAINER_EDGE_INSECURE_POLL`: Enable insecure polling for Edge Agent (default: false)

### Volumes

- `portainer_data`: Volume to store Portainer data (users, endpoints, settings, etc.)
- Docker socket: Mounted as read-only for security

## Management Commands

### Start Portainer
```bash
docker-compose up -d
```

### Stop Portainer
```bash
docker-compose down
```

### View Logs
```bash
docker-compose logs -f portainer
```

### Restart Portainer
```bash
docker-compose restart portainer
```

### Update Portainer
```bash
docker-compose pull
docker-compose up -d
```

## Backup & Restore

### Backup Data
```bash
docker run --rm -v portainer-platform_portainer_data:/data -v $(pwd):/backup alpine tar czf /backup/portainer-backup-$(date +%Y%m%d).tar.gz /data
```

### Restore Data
```bash
docker run --rm -v portainer-platform_portainer_data:/data -v $(pwd):/backup alpine sh -c "cd /data && tar xzf /backup/portainer-backup-YYYYMMDD.tar.gz --strip 1"
```

## Security Notes

- Docker socket is mounted as read-only (`:ro`) for security
- Use HTTPS for production (setup reverse proxy with SSL)
- Make sure firewall is configured correctly
- Use strong password for admin account

## Troubleshooting

### Port already in use
Change port in `.env` file:
```bash
PORTAINER_PORT=9001
```

### Permission denied on Docker socket
Make sure user has access to Docker socket or run with sudo:
```bash
sudo docker-compose up -d
```

### Network not found
If network `your-domain` doesn't exist, change in `docker-compose.yml`:
```yaml
networks:
  your-domain:
    external: false
```

## References

- [Portainer Documentation](https://docs.portainer.io/)
- [Portainer GitHub](https://github.com/portainer/portainer)


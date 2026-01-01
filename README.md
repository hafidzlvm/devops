# DevOps Open Source Platform

Open source DevOps platform that provides a complete solution for container management, reverse proxy with SSL, and ready-to-use Docker infrastructure.

## 📋 Description

This project is a collection of DevOps platforms that can be used to easily manage Docker infrastructure. Each platform can be used standalone or combined to build more complex infrastructure.

## 🚀 Available Platforms

### 1. [Nginx Platform](./nginx-platform/README.md)
Platform for SSL setup with Let's Encrypt using Certbot and Nginx as reverse proxy. Supports multiple domains/subdomains with separate configurations.

**Main Features:**
- ✅ Auto-renewal SSL certificate
- ✅ Automatic HTTP to HTTPS redirect
- ✅ Multiple domain/subdomain support
- ✅ Auto-reload Nginx to apply new certificates
- ✅ SSL termination with best security configuration

**📖 Full Documentation:** [nginx-platform/README.md](./nginx-platform/README.md)

### 2. [Portainer Platform](./portainer-platform/README.md)
Docker container management platform using Portainer Community Edition with a user-friendly web interface.

**Main Features:**
- ✅ Web UI for Docker management
- ✅ Edge Agent support for remote management
- ✅ Stack deployment management
- ✅ Container monitoring and logs
- ✅ User management and access control

**📖 Full Documentation:** [portainer-platform/README.md](./portainer-platform/README.md)

## 🛠️ Prerequisites

Before using these platforms, make sure you have installed:

- **Docker** (version 20.10 or newer)
- **Docker Compose** (version 2.0 or newer)

For Docker and Docker Compose installation, visit:
- [Docker Installation Guide](https://docs.docker.com/get-docker/)
- [Docker Compose Installation Guide](https://docs.docker.com/compose/install/)

## 📦 Project Structure

```
devops-open/
├── nginx-platform/          # Nginx Platform with SSL
│   ├── docker-compose.yml
│   ├── env.template
│   ├── init-letsencrypt.sh
│   ├── nginx/
│   │   ├── secure/          # Nginx configuration for HTTPS
│   │   ├── certbot/         # SSL certificates
│   │   └── 99-autoreload.sh
│   └── README.md
├── portainer-platform/      # Portainer Platform
│   ├── docker-compose.yml
│   ├── env.template
│   └── README.md
└── README.md                # This file
```

## 🎯 Quick Start

### Setup Nginx Platform

1. Navigate to nginx-platform directory:
```bash
cd nginx-platform
```

2. Copy and edit environment file:
```bash
cp env.template .env
nano .env
```

3. Run initial setup:
```bash
chmod +x init-letsencrypt.sh
./init-letsencrypt.sh
```

4. Start services:
```bash
docker compose up -d
```

**📖 Full Guide:** [nginx-platform/README.md](./nginx-platform/README.md)

### Setup Portainer Platform

1. Navigate to portainer-platform directory:
```bash
cd portainer-platform
```

2. Copy and edit environment file:
```bash
cp env.template .env
nano .env
```

3. Create Docker network (if not exists):
```bash
docker network create your-domain
```

4. Start services:
```bash
docker compose up -d
```

5. Access Portainer at: `http://localhost:9000`

**📖 Full Guide:** [portainer-platform/README.md](./portainer-platform/README.md)

## 🔗 Platform Integration

These platforms can be integrated to build more complete infrastructure:

### Nginx + Portainer

Use Nginx as reverse proxy for Portainer with SSL:

1. Setup Nginx Platform first
2. Setup Portainer Platform
3. Create Nginx configuration for Portainer (see documentation at [portainer-platform/README.md](./portainer-platform/README.md))
4. Generate SSL certificate for Portainer subdomain
5. Access Portainer via `https://portainer.yourdomain.com`

## 🌐 Network Configuration

All platforms use the same Docker network (`your-domain`) to enable communication between containers. 

**Creating Network:**
```bash
docker network create your-domain
```

**Using Existing Network:**
Edit `docker-compose.yml` in each platform and make sure the network name matches.

## 🔒 Security Best Practices

1. **Use HTTPS**: Always use SSL/TLS for production
2. **Environment Variables**: Do not commit `.env` file to repository
3. **Firewall**: Configure firewall to limit port access
4. **Regular Updates**: Update Docker images regularly
5. **Backup**: Perform data backups regularly

## 📝 Environment Variables

Each platform has an `env.template` file containing templates for environment variables. Copy that file to `.env` and adjust according to your needs.

**⚠️ Important:** Do not commit `.env` file to repository as it may contain sensitive information.

## 🐛 Troubleshooting

### Network Issues
If experiencing network issues, make sure:
- Docker network is created: `docker network ls`
- All services use the same network
- Network is not deleted while containers are running

### SSL Certificate Issues
- Make sure domain points to server IP
- Port 80 and 443 must be open in firewall
- Check certbot logs: `docker compose logs certbot`

### Port Conflicts
If port is already in use, change port in `.env` or `docker-compose.yml` file.

## 📚 Full Documentation

- [Nginx Platform Documentation](./nginx-platform/README.md) - SSL setup with Let's Encrypt and Nginx reverse proxy
- [Portainer Platform Documentation](./portainer-platform/README.md) - Docker container management with Portainer

## 🤝 Contributing

This project is open source and contributions are very welcome! If you want to contribute:

1. Fork this repository
2. Create a branch for new feature (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## 📄 License

This project is open source and available under the appropriate license. Please see LICENSE file for more details.

## 🙏 Acknowledgments

- [Nginx](https://www.nginx.com/) - Web server and reverse proxy
- [Certbot](https://certbot.eff.org/) - Let's Encrypt client
- [Portainer](https://www.portainer.io/) - Container management platform
- [Docker](https://www.docker.com/) - Containerization platform

## 📞 Support

If you experience issues or have questions:

1. Check documentation in each platform
2. Check Troubleshooting section
3. Open an issue in the repository

## 🔄 Update & Maintenance

### Update Docker Images
```bash
# In each platform directory
docker compose pull
docker compose up -d
```

### Backup Data
Perform Docker volume backups regularly to prevent data loss.

### Monitoring
Use Portainer for container monitoring or setup other monitoring tools.

---

**⭐ If this project helps you, don't forget to give it a star!**

**🌐 Open Source - Made with ❤️ for the DevOps community**

---

## 🏷️ Tags

**#nginx** **#nginx-docker** **#nginx-certbot** **#nginx-reverse-proxy** **#nginx-ssl** **#nginx-https** **#nginx-letsencrypt** **#nginx-multiple-domain** **#nginx-subdomain**
**#docker** **#docker-compose** **#docker-certbot** **#docker-portainer** **#docker-ssl** **#docker-nginx** **#docker-reverse-proxy** **#docker-vps** **#docker-setup**
**#certbot** **#certbot-docker** **#certbot-nginx** **#certbot-automation** **#certbot-auto-renewal**
**#letsencrypt** **#letsencrypt-docker** **#letsencrypt-nginx** **#letsencrypt-certbot** **#letsencrypt-ssl** **#letsencrypt-automation**
**#portainer** **#portainer-docker** **#portainer-ce** **#portainer-management** **#portainer-ui** **#portainer-container-management**
**#ssl** **#ssl-certificate** **#ssl-automation** **#ssl-docker** **#ssl-nginx** **#ssl-letsencrypt** **#ssl-termination**
**#reverse-proxy** **#reverse-proxy-nginx** **#reverse-proxy-docker** **#reverse-proxy-ssl**
**#devops** **#devops-tools** **#devops-platform** **#devops-automation** **#devops-docker** **#devops-nginx**
**#vps** **#vps-setup** **#vps-docker** **#vps-nginx** **#vps-certbot** **#vps-portainer** **#vps-ssl** **#vps-deployment** **#vps-infrastructure**
**#container-management** **#container-orchestration** **#container-platform** **#container-deployment**
**#web-server** **#web-server-nginx** **#web-server-ssl** **#web-server-docker**
**#infrastructure-as-code** **#iac** **#docker-compose-setup** **#docker-stack**
**#open-source** **#opensource** **#open-source-devops** **#open-source-platform**
**#self-hosted** **#self-hosted-docker** **#self-hosted-nginx** **#self-hosted-portainer**
**#automation** **#ssl-automation** **#certificate-automation** **#docker-automation**
**#production-ready** **#production-setup** **#production-ssl** **#production-docker**
**#tutorial** **#how-to** **#setup-guide** **#deployment-guide** **#vps-tutorial** **#docker-tutorial** **#nginx-tutorial**


# Server Configuration & Automation System

A comprehensive, YAML-based server configuration and automation system for deploying containerized services across multiple servers with zero-touch setup.

## 🚀 Features

- **Zero-Touch Deployment**: Services start ready-to-use with complete configurations
- **Creative Stack Organization**: 8 thematic service stacks with port numbering (10X00 scheme)
- **Dual Domain Support**: Internal (.local) and external (Cloudflare tunnel) access
- **Encrypted Secrets Management**: Age-encrypted secrets with easy rotation
- **Service-First Hostnames**: `service-server.domain.com` convention
- **Automated Configuration**: Templates generate all service configs
- **Security by Design**: Authelia authentication, CrowdSec protection, VPN access

## 📋 Stack Overview

| Stack | Name | Port Range | Services |
|-------|------|------------|----------|
| 00 | **Bifrost** (Network Gateway) | 10000-10099 | Traefik, Cloudflare Tunnel |
| 01 | **Watchtower** (System Guardians) | 10100-10199 | Watchtower, Uptime Kuma, Homarr |
| 02 | **Observatory** (Monitoring) | 10200-10299 | Grafana, Prometheus, Loki |
| 03 | **Workshop** (Development) | 10300-10399 | VS Code, Portainer, Jenkins, ArgoCD |
| 04 | **Automation** (Productivity) | 10400-10499 | n8n, CasaOS, Vaultwarden |
| 05 | **Fortress** (Security) | 10500-10599 | Pi-hole, Authelia, CrowdSec, Tailscale |
| 06 | **Media Nexus** (Media Services) | 10600-10699 | Plex, Jellyfin, Overseerr |
| 07 | **Media Pirates** (Content Management) | 10700-10799 | Sonarr, Radarr, qBittorrent |
| 08 | **Intelligence** (AI/LLM) | 10800-10899 | Ollama, Open WebUI, LocalAI |

## 🗂️ Project Structure

```
server-configs/
├── configs/servers/          # Server configurations
│   ├── lugia.yml            # OCI server config
│   ├── snorlax.yml          # NAS server config
│   └── template.yml         # New server template
├── docker/stacks/           # Service stacks
│   ├── 00-bifrost/         # Network gateway
│   ├── 01-watchtower/      # System monitoring
│   └── ...
├── scripts/                 # Automation scripts
│   ├── deploy.sh           # Main deployment script
│   ├── secrets.sh          # Secrets management
│   └── validate.sh         # Configuration validation
├── templates/              # Configuration templates
│   └── cloudflare/         # Tunnel configurations
└── secrets/                # Encrypted secrets (git-ignored)
```

## 🚀 Quick Start

### 1. Prerequisites

Install required tools:
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install docker.io docker-compose python3-pip age yq

# macOS
brew install docker python3 age yq
```

### 2. Configure Your Server

Copy and customize a server configuration:
```bash
cp configs/servers/template.yml configs/servers/myserver.yml
# Edit with your server details
```

### 3. Generate Secrets

```bash
# Generate encrypted secrets
./scripts/secrets.sh generate myserver

# Edit secrets (add your API keys)
./scripts/secrets.sh edit myserver
```

### 4. Deploy Services

```bash
# Validate configuration
./scripts/validate.sh myserver

# Deploy all enabled stacks
./scripts/deploy.sh myserver

# Deploy specific stack
./scripts/deploy.sh myserver --stack=03-workshop
```

## 🔐 Security & Access

### SSH Security Setup

⚠️ **IMPORTANT**: Set up alternative access methods BEFORE applying security configurations to prevent lockouts.

1. **Create Emergency Access**:
   ```bash
   # Add backup SSH user
   sudo adduser emergency-admin
   sudo usermod -aG sudo emergency-admin
   
   # Set up SSH key for emergency user
   sudo mkdir /home/emergency-admin/.ssh
   sudo cp ~/.ssh/authorized_keys /home/emergency-admin/.ssh/
   sudo chown -R emergency-admin:emergency-admin /home/emergency-admin/.ssh
   ```

2. **Set up VPN Access**:
   Deploy Tailscale/WireGuard FIRST for alternative access:
   ```bash
   ./scripts/deploy.sh myserver --stack=05-fortress
   ```

3. **Apply Security Gradually**:
   - Test each security measure
   - Verify alternative access works
   - Apply SSH restrictions last

### Access Methods

- **Internal**: `http://service.server.local` (via Pi-hole DNS)
- **External**: `https://service-server.domain.com` (via Cloudflare tunnel)
- **VPN**: Access internal services via Tailscale/WireGuard

## 🔑 Secrets Management

### Generate Secrets
```bash
./scripts/secrets.sh generate <server>
```

### Edit Secrets
```bash
./scripts/secrets.sh edit <server>
```

### View Secrets
```bash
./scripts/secrets.sh view <server>
```

## 🌐 Domain Configuration

### Cloudflare Setup

1. **Create Tunnel**:
   ```bash
   cloudflared tunnel create server-tunnel
   # Copy token to secrets file
   ```

2. **DNS Records**:
   Add wildcard CNAME: `*.server.domain.com` → `tunnel-id.cfargotunnel.com`

3. **SSL Settings**:
   - Set SSL/TLS mode to "Full (strict)"
   - Enable "Always Use HTTPS"

### Internal DNS (Pi-hole)

Pi-hole automatically configures local DNS entries for all services using the pattern:
- `service.server.local` → server IP

## 📊 Service Access URLs

After deployment, access your services at:

### External (via Cloudflare)
- Dashboard: `https://home-server.domain.com`
- Grafana: `https://grafana-server.domain.com`
- VS Code: `https://code-server.domain.com`
- Chat (AI): `https://chat-server.domain.com`

### Internal (direct access)
- Dashboard: `http://home.server.local`
- Grafana: `http://grafana.server.local`
- Traefik: `http://traefik.server.local`
- Pi-hole: `http://dns.server.local`

## 🔧 Configuration Management

### Server Types

- **ubuntu-server**: Standard Ubuntu deployment (OCI, VPS, laptop)
- **nas**: Synology/QNAP with media capabilities
- **raspberry-pi**: ARM-based lightweight deployment

### Volume Mapping

Consistent volume structure across all servers:
- **Config**: Service configurations
- **Data**: Service data and databases  
- **Downloads**: Download directory
- **Media**: Media files (NAS only)

### Environment Variables

Auto-generated from server config:
- `SERVER_NAME`, `DOMAIN`, `INTERNAL_DOMAIN`
- `CONFIG_BASE`, `DATA_BASE`, `DOWNLOADS_BASE`, `MEDIA_BASE`
- `TZ`, `PUID`, `PGID`
- Cloudflare and service-specific secrets

## 🤖 AI/LLM Services

The Intelligence stack (08) provides local AI capabilities:

- **Ollama**: Local LLM server with model management
- **Open WebUI**: ChatGPT-like interface for Ollama
- **LocalAI**: OpenAI-compatible API
- **Jupyter Lab**: AI/ML development environment
- **Whisper ASR**: Speech-to-text service
- **Stable Diffusion**: Image generation (GPU required)

### GPU Support

For NVIDIA GPU support, ensure docker supports GPU access:
```bash
# Install NVIDIA container runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

## 🆘 Troubleshooting

### Common Issues

1. **Can't access services externally**:
   - Check Cloudflare tunnel status
   - Verify DNS records
   - Confirm tunnel token in secrets

2. **Services not starting**:
   - Check Docker logs: `docker compose logs <service>`
   - Verify volume permissions
   - Check available disk space

3. **SSH lockout**:
   - Use cloud console/serial access
   - Connect via Tailscale/VPN
   - Use emergency SSH user

### Validation

Always validate before deployment:
```bash
./scripts/validate.sh <server>
```

### Log Locations

- **Traefik**: `/var/log/traefik/`
- **Service logs**: `docker compose logs -f <service>`
- **System logs**: `/var/log/syslog`

## 📚 Additional Documentation

- [Deployment Guide](docs/deployment.md)
- [Security Setup](docs/security.md) 
- [Domain Configuration](docs/domains.md)
- [Secrets Management](docs/secrets.md)
- [LLM Setup Guide](docs/llm-setup.md)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request

## ⚖️ License

MIT License - see LICENSE file for details.

---

## 🎯 Server Examples

### OCI Lightweight Server (Lugia)
- Development tools (VS Code, Jenkins)
- Monitoring (Grafana, Prometheus)
- AI services (Ollama, Chat)
- Security (Authelia, Pi-hole)

### NAS Media Server (Snorlax)  
- Media streaming (Plex, Jellyfin)
- Content management (Sonarr, Radarr)
- Media requests (Overseerr)
- File management

Start with the Quick Start guide above, then refer to specific documentation for advanced configuration!
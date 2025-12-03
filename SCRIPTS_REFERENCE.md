# Scripts Reference Guide

Complete reference for all scripts in this project.

## Table of Contents

1. [Setup Scripts](#setup-scripts)
2. [Maintenance Scripts](#maintenance-scripts)
3. [Quick Reference](#quick-reference)

---

## Setup Scripts

### `scripts/setup/install.sh`
**Purpose:** Main installation script - sets up the entire DoH + Smart DNS system

**Usage:**
```bash
sudo ./scripts/setup/install.sh
```

**What it does:**
- Checks and installs prerequisites (Docker, Docker Compose, etc.)
- Creates docker-compose.yml with CoreDNS, DoH backend, and Nginx
- Generates CoreDNS configuration and hosts file
- Sets up Nginx for DoH endpoint
- Creates SSL certificates (self-signed or Let's Encrypt)
- Installs and configures SNIProxy
- Configures firewall (UFW)
- Starts all services

**Requirements:**
- Root access
- Domain name (prompted during installation)
- VPS IP (auto-detected or prompted)

**Output:**
- Fully configured DoH + Smart DNS system
- All services running and ready

---

### `scripts/setup/setup-letsencrypt.sh`
**Purpose:** Obtains Let's Encrypt SSL certificate for your domain

**Usage:**
```bash
sudo ./scripts/setup/setup-letsencrypt.sh
```

**What it does:**
- Installs Certbot if needed
- Prompts for email address
- Obtains Let's Encrypt certificate
- Updates Nginx configuration
- Restarts services

**Requirements:**
- Domain DNS A record must point to VPS IP
- Port 80 must be open
- Root access

---

### `scripts/setup/setup-cloudflare-tunnel.sh`
**Purpose:** Sets up Cloudflare Tunnel to bypass IP blocking

**Usage:**
```bash
sudo ./scripts/setup/setup-cloudflare-tunnel.sh
```

**What it does:**
- Installs cloudflared
- Guides through tunnel creation
- Creates systemd service
- Configures tunnel

**Use case:** When Xbox Live blocks your VPS IP

---

### `scripts/setup/setup-discord-udp-proxy.sh`
**Purpose:** Sets up 3proxy SOCKS5 proxy for Discord voice chat

**Usage:**
```bash
sudo ./scripts/setup/setup-discord-udp-proxy.sh
```

**What it does:**
- Installs 3proxy from source
- Creates SOCKS5 proxy on port 1080 (TCP + UDP)
- Sets up systemd service
- Configures firewall

**Note:** Requires Discord client configuration (PC/Phone only, not Xbox)

---

## Maintenance Scripts

### `scripts/maintenance/fix-discord.sh`
**Purpose:** Comprehensive Discord connectivity fix and diagnosis

**Usage:**
```bash
sudo ./scripts/maintenance/fix-discord.sh
```

**What it does:**
- Diagnoses DNS resolution
- Checks SNIProxy status
- Fixes systemd tracking
- Adds missing Discord domains to hosts file
- Adds Discord voice subdomains
- Restarts CoreDNS
- Verifies fix

**Use when:**
- Discord text chat not working
- Discord DNS not resolving correctly
- Missing Discord subdomains

---

### `scripts/maintenance/fix-coredns.sh`
**Purpose:** Comprehensive CoreDNS fix (ports, conflicts, connection)

**Usage:**
```bash
sudo ./scripts/maintenance/fix-coredns.sh
```

**What it does:**
- Checks port 53 conflicts (systemd-resolved)
- Fixes docker-compose port mapping
- Restarts CoreDNS
- Verifies DNS resolution

**Use when:**
- "Connection refused" on port 53
- CoreDNS not responding
- Port 53 conflict with systemd-resolved

---

### `scripts/maintenance/fix-sniproxy.sh`
**Purpose:** Comprehensive SNIProxy fix (systemd, ports, timeouts)

**Usage:**
```bash
sudo ./scripts/maintenance/fix-sniproxy.sh
```

**What it does:**
- Fixes systemd tracking (forking issue)
- Checks port 443 conflicts
- Starts/restarts SNIProxy
- Verifies SNIProxy is running

**Use when:**
- SNIProxy shows "inactive (dead)" but process is running
- Port 443 conflicts
- SNIProxy not starting

---

### `scripts/maintenance/fix-xbox-connectivity.sh`
**Purpose:** Troubleshoot Xbox connectivity issues

**Usage:**
```bash
sudo ./scripts/maintenance/fix-xbox-connectivity.sh
```

**What it does:**
- Checks firewall rules
- Tests DNS resolution
- Tests connectivity to Xbox servers
- Checks SNIProxy status
- Provides diagnosis and solutions

**Use when:**
- Xbox shows connection errors
- NAT unavailable
- Can't connect to Xbox Live

---

### `scripts/maintenance/monitor-logs.sh`
**Purpose:** Real-time log monitoring for all services

**Usage:**
```bash
sudo ./scripts/maintenance/monitor-logs.sh
```

**Features:**
- SNIProxy access logs (real-time)
- SNIProxy error logs
- CoreDNS logs
- Nginx logs
- DoH backend logs
- All logs combined
- Connection statistics
- Recent Xbox/Discord connections
- System logs
- Port 443 live monitoring
- DNS query logs

**Interactive menu** - Select what to monitor

---

### `scripts/maintenance/regenerate-hosts.sh`
**Purpose:** Regenerates the xbox-hosts file with all domains

**Usage:**
```bash
sudo ./scripts/maintenance/regenerate-hosts.sh
```

**What it does:**
- Backs up existing hosts file
- Generates new hosts file with all domains:
  - Xbox domains
  - Discord domains
  - All game publisher domains
- Restarts CoreDNS
- Verifies DNS resolution

**Use when:**
- Hosts file is empty or corrupted
- Need to refresh all domain mappings

---

### `scripts/maintenance/add-game-domain.sh`
**Purpose:** Add individual game domains to hosts file and SNIProxy

**Usage:**
```bash
sudo ./scripts/maintenance/add-game-domain.sh domain1.com domain2.com
```

**What it does:**
- Adds domains to xbox-hosts file
- Adds SNIProxy rules
- Restarts services

**Use when:**
- Adding new game domains
- Specific game not working

---

### `scripts/maintenance/migrate-to-cloudflare-tunnel.sh`
**Purpose:** Migrates DNS configuration for Cloudflare Tunnel

**Usage:**
```bash
sudo ./scripts/maintenance/migrate-to-cloudflare-tunnel.sh
```

**What it does:**
- Removes Xbox domains from hosts file
- Updates CoreDNS configuration
- Keeps Discord and game publishers
- Restarts CoreDNS

**Use when:**
- Setting up Cloudflare Tunnel for Xbox

---

### `scripts/maintenance/diagnose-cloudflare-tunnel.sh`
**Purpose:** Diagnoses Cloudflare Tunnel issues

**Usage:**
```bash
sudo ./scripts/maintenance/diagnose-cloudflare-tunnel.sh
```

**What it does:**
- Checks DNS resolution
- Checks tunnel status
- Checks SNIProxy status
- Checks tunnel configuration
- Tests connectivity

---

### `scripts/maintenance/fix-cloudflare-tunnel-issues.sh`
**Purpose:** Fixes common Cloudflare Tunnel issues

**Usage:**
```bash
sudo ./scripts/maintenance/fix-cloudflare-tunnel-issues.sh
```

**What it does:**
- Starts CoreDNS if not running
- Guides through DNS record setup
- Checks tunnel configuration

---

### `scripts/maintenance/test-xbox-blocking.sh`
**Purpose:** Tests if Xbox Live is blocking your VPS IP

**Usage:**
```bash
sudo ./scripts/maintenance/test-xbox-blocking.sh
```

**What it does:**
- Tests DNS resolution
- Tests direct connectivity
- Tests SNIProxy forwarding
- Checks logs for errors
- Provides analysis

---

## Quick Reference

### Common Issues & Solutions

| Issue | Script to Run |
|-------|---------------|
| Discord not working | `fix-discord.sh` |
| CoreDNS connection refused | `fix-coredns.sh` |
| SNIProxy inactive (dead) | `fix-sniproxy.sh` |
| Xbox connection errors | `fix-xbox-connectivity.sh` |
| Monitor logs | `monitor-logs.sh` |
| Hosts file empty | `regenerate-hosts.sh` |
| Need Let's Encrypt cert | `setup-letsencrypt.sh` |
| Xbox blocking VPS IP | `setup-cloudflare-tunnel.sh` |

### Service Status Checks

```bash
# Check all services
docker ps
systemctl status sniproxy

# Check ports
ss -tlnp | grep -E "53|443|1080"

# Check DNS
dig @127.0.0.1 xboxlive.com +short
dig @127.0.0.1 discord.com +short

# Check logs
docker logs coredns-smartdns
tail -f /var/log/sniproxy/https_access.log
```

### Service Restarts

```bash
# Restart all Docker services
cd /root/doh
docker compose restart

# Restart individual services
docker compose restart coredns-smartdns
systemctl restart sniproxy
```

### File Locations

- **docker-compose.yml**: `/root/doh/docker-compose.yml`
- **CoreDNS config**: `/root/doh/coredns/Corefile`
- **Hosts file**: `/root/doh/coredns/xbox-hosts`
- **Nginx config**: `/root/doh/nginx/conf.d/doh.conf`
- **SNIProxy config**: `/etc/sniproxy.conf`
- **SSL certificates**: `/root/doh/ssl/`

---

## Script Dependencies

### Prerequisites (auto-installed by install.sh)
- Docker
- Docker Compose
- curl
- openssl
- ss (iproute2)
- ufw

### Optional (for specific features)
- certbot (for Let's Encrypt)
- cloudflared (for Cloudflare Tunnel)
- 3proxy (for Discord UDP proxy)

---

## Troubleshooting

### Script fails with "command not found"
- Run as root: `sudo ./script.sh`
- Check if prerequisites are installed

### Script fails with "permission denied"
- Ensure you're running as root
- Check file permissions: `chmod +x script.sh`

### Script can't find doh directory
- Run from the doh directory: `cd /root/doh`
- Or specify the path in the script

### Services not starting
- Check logs: `docker logs <container-name>`
- Check systemd: `journalctl -u <service> -n 50`
- Verify ports are not in use: `ss -tlnp | grep <port>`

---

## Best Practices

1. **Always backup before running fix scripts**
   - Scripts create backups automatically
   - Manual backup: `cp file file.backup`

2. **Check logs first**
   - Use `monitor-logs.sh` to see what's happening
   - Check specific service logs

3. **Test after fixes**
   - Verify DNS resolution
   - Test connectivity
   - Check service status

4. **Keep scripts updated**
   - Scripts are maintained and improved
   - Check for updates regularly

---

## Support

For issues or questions:
1. Check this documentation
2. Review script output and logs
3. Check service status
4. Review troubleshooting section

---

**Last Updated:** 2025-11-28





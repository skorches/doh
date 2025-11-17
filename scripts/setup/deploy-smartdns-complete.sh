#!/bin/bash

# Complete Smart DNS + HAProxy Setup for Xbox
# Run this on your VPS as root

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Smart DNS + HAProxy Setup for Xbox"
echo "================================================"
echo ""

# Get VPS public IP
VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

# Stop existing services
echo ""
echo -e "${YELLOW}[1/8] Stopping existing services...${NC}"
cd /root/doh
docker-compose down 2>/dev/null || true
systemctl stop haproxy 2>/dev/null || true

# Install HAProxy
echo ""
echo -e "${YELLOW}[2/8] Installing HAProxy...${NC}"
apt-get update -qq
apt-get install -y haproxy

# Configure HAProxy for SNI proxying + DoH
echo ""
echo -e "${YELLOW}[3/8] Configuring HAProxy...${NC}"

cat > /etc/haproxy/haproxy.cfg << 'EOFHA'
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon
    maxconn 50000
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

# Stats page
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE

# HTTPS frontend (port 443) - Handles both DoH and Xbox traffic
frontend https_front
    bind *:443
    mode tcp
    option tcplog
    
    # Inspect SNI to route traffic
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route DoH requests (bypass.440.info) to Nginx
    acl is_doh_domain req_ssl_sni -i bypass.440.info
    use_backend doh_local if is_doh_domain
    
    # Route Xbox/Discord domains through SNI proxy
    acl is_xbox_domain req_ssl_sni -m end .xboxlive.com
    acl is_xbox_domain req_ssl_sni -m end .xboxservices.com
    acl is_xbox_domain req_ssl_sni -m end .xbox.com
    acl is_xbox_domain req_ssl_sni -m end .live.com
    acl is_xbox_domain req_ssl_sni -m end .microsoft.com
    acl is_discord_domain req_ssl_sni -m end .discord.com
    acl is_discord_domain req_ssl_sni -m end .discordapp.com
    acl is_discord_domain req_ssl_sni -m end .discordapp.net
    acl is_discord_domain req_ssl_sni -m end .discord.gg
    
    use_backend sni_proxy if is_xbox_domain
    use_backend sni_proxy if is_discord_domain
    
    # Default: forward to SNI proxy
    default_backend sni_proxy

# Backend for DoH server (Nginx container)
backend doh_local
    mode tcp
    server doh 127.0.0.1:8443 check

# Backend for SNI proxy (forwards to real servers)
backend sni_proxy
    mode tcp
    balance leastconn
    
    # Use SNI to connect to real servers
    server-template sni 10 0.0.0.0:0 check-sni req.ssl_sni sni req.ssl_sni

# HTTP frontend (port 80) - For Xbox HTTP traffic
frontend http_front
    bind *:80
    mode tcp
    default_backend http_proxy

backend http_proxy
    mode tcp
    balance leastconn
    server http_fallback 0.0.0.0:0

# Xbox Live specific ports
frontend xbox_live_3074
    bind *:3074
    mode tcp
    default_backend xbox_live_backend

backend xbox_live_backend
    mode tcp
    server xbox_live 0.0.0.0:3074

frontend xbox_teredo
    bind *:3544 proto udp
    mode udp
    default_backend teredo_backend

backend teredo_backend
    mode udp
    server teredo 0.0.0.0:3544
EOFHA

echo -e "${GREEN}✅ HAProxy configured${NC}"

# Create CoreDNS Smart DNS configuration
echo ""
echo -e "${YELLOW}[4/8] Creating CoreDNS Smart DNS config...${NC}"

mkdir -p /root/doh/coredns

cat > /root/doh/coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to doh-upstream
    forward . doh-upstream:5053
    
    # Enable caching
    cache 300
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

# Create xbox-hosts file with VPS IP
cat > /root/doh/coredns/xbox-hosts << EOFHOSTS
# === XBOX AUTHENTICATION ===
$VPS_IP auth.xboxlive.com
$VPS_IP device.auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP sisu.xboxlive.com

# === XBOX SERVICES ===
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP xnotify.xboxlive.com
$VPS_IP settings.xboxlive.com
$VPS_IP profile.xboxlive.com

# === XBOX SERVICES (wildcard domains) ===
$VPS_IP activity.xboxservices.com
$VPS_IP contentaccess.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com

# === GAME PASS ===
$VPS_IP catalog.gamepass.com
$VPS_IP gamepass.com

# === MICROSOFT LOGIN ===
$VPS_IP login.live.com
$VPS_IP account.live.com

# === MICROSOFT NETWORK CHECKS ===
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftncsi.com
$VPS_IP ipv6.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com

# === OTHER MICROSOFT ===
$VPS_IP arc.msn.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com

# === TEREDO (IPv6 tunneling) ===
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# === DISCORD (for Xbox Discord app) ===
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP images-ext-1.discordapp.net
$VPS_IP images-ext-2.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP status.discord.com
$VPS_IP voice.discord.gg
$VPS_IP router.discordapp.net
EOFHOSTS

echo -e "${GREEN}✅ CoreDNS Smart DNS configured${NC}"

# Update docker-compose.yml to add CoreDNS
echo ""
echo -e "${YELLOW}[5/8] Updating docker-compose.yml...${NC}"

cat > /root/doh/docker-compose.yml << 'EOFDC'
services:
  doh-nginx:
    image: nginx:alpine
    container_name: doh-nginx
    ports:
      - "8443:443"  # Internal port, HAProxy listens on 443 externally
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - doh-backend
    restart: unless-stopped
    networks:
      - doh-network

  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    environment:
      - UPSTREAM_DNS_SERVER=udp:coredns-smartdns:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8053
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
    restart: unless-stopped
    networks:
      - doh-network

  coredns-smartdns:
    image: coredns/coredns:latest
    container_name: coredns-smartdns
    volumes:
      - ./coredns/Corefile:/etc/coredns/Corefile:ro
      - ./coredns/xbox-hosts:/etc/coredns/xbox-hosts:ro
    command: -conf /etc/coredns/Corefile
    restart: unless-stopped
    networks:
      - doh-network

  doh-upstream:
    image: cloudflare/cloudflared:latest
    container_name: doh-upstream
    command: proxy-dns --address 0.0.0.0 --port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query
    restart: unless-stopped
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOFDC

echo -e "${GREEN}✅ docker-compose.yml updated${NC}"

# Start HAProxy
echo ""
echo -e "${YELLOW}[6/8] Starting HAProxy...${NC}"
systemctl enable haproxy
systemctl restart haproxy
sleep 2

if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy started${NC}"
else
    echo -e "${RED}❌ HAProxy failed to start${NC}"
    journalctl -u haproxy -n 20 --no-pager
    exit 1
fi

# Start Docker containers
echo ""
echo -e "${YELLOW}[7/8] Starting Docker containers...${NC}"
cd /root/doh
docker-compose up -d

sleep 5

# Check container status
echo ""
docker-compose ps

# Open firewall ports
echo ""
echo -e "${YELLOW}[8/8] Configuring firewall...${NC}"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS/DoH/Xbox"
ufw allow 3074/tcp comment "Xbox Live"
ufw allow 3074/udp comment "Xbox Live UDP"
ufw allow 3544/udp comment "Xbox Teredo"
ufw allow 8404/tcp comment "HAProxy Stats"

echo ""
echo "================================================"
echo -e "${GREEN}✅ Smart DNS Setup Complete!${NC}"
echo "================================================"
echo ""
echo "VPS IP: $VPS_IP"
echo ""
echo "Services Running:"
echo "  ✅ HAProxy (SNI proxy + DoH router) - Port 443"
echo "  ✅ Nginx (DoH frontend) - Port 8443 (internal)"
echo "  ✅ DoH Backend (satishweb) - Port 8053 (internal)"
echo "  ✅ CoreDNS Smart DNS - Returns VPS IP for Xbox/Discord"
echo "  ✅ Cloudflared Upstream - DoH to Cloudflare"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo ""
echo "Test from your PC:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Expected: Should return VPS IP ($VPS_IP)"
echo ""
echo "================================================"


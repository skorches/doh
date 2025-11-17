#!/bin/bash

# Complete Smart DNS Setup - Restore working config and add Smart DNS

set -e

echo "================================================"
echo "Complete Smart DNS Setup"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh

VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

echo ""
echo -e "${YELLOW}[1/6] Stopping all services...${NC}"
docker-compose down --remove-orphans 2>/dev/null || true
systemctl stop haproxy 2>/dev/null || true

echo ""
echo -e "${YELLOW}[2/6] Creating working docker-compose.yml...${NC}"

# Backup current
cp docker-compose.yml docker-compose.yml.old-$(date +%s) 2>/dev/null || true

# Create complete working docker-compose with Smart DNS
cat > docker-compose.yml << 'EOFDOCKER'
version: '3.8'

services:
  # Nginx - HTTPS/SSL termination
  doh-nginx:
    image: nginx:alpine
    container_name: doh-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "8443:443"  # Internal only, HAProxy uses public 443
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./letsencrypt:/etc/letsencrypt:ro
    networks:
      - doh-network
    depends_on:
      - doh-backend

  # DoH Backend
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=coredns-smartdns:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8053
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
    expose:
      - "8053"
    networks:
      - doh-network
    depends_on:
      - coredns-smartdns
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8053/dns-query?name=google.com&type=A"]
      interval: 30s
      timeout: 10s
      retries: 3

  # CoreDNS Smart DNS - Returns VPS IP for Xbox/Discord
  coredns-smartdns:
    image: coredns/coredns:latest
    container_name: coredns-smartdns
    restart: unless-stopped
    command: -conf /etc/coredns/Corefile
    volumes:
      - ./coredns/Corefile:/etc/coredns/Corefile:ro
      - ./coredns/xbox-hosts:/etc/coredns/xbox-hosts:ro
    expose:
      - "53"
    networks:
      - doh-network
    depends_on:
      - doh-upstream

  # Cloudflared - Upstream DoH
  doh-upstream:
    image: cloudflare/cloudflared:latest
    container_name: doh-upstream
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://1.1.1.1/dns-query,https://1.0.0.1/dns-query
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5053
    expose:
      - "5053"
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOFDOCKER

echo -e "${GREEN}✅ docker-compose.yml created${NC}"

echo ""
echo -e "${YELLOW}[3/6] Creating CoreDNS Smart DNS configuration...${NC}"

mkdir -p coredns

# Create Corefile
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to upstream DoH
    forward . doh-upstream:5053
    
    # Cache DNS responses
    cache 300
    
    # Log errors only
    errors
}
EOFCORE

# Create xbox-hosts file
cat > coredns/xbox-hosts << EOFHOSTS
# Xbox Live domains - return VPS IP for Smart DNS proxying
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP catalog.gamepass.com
$VPS_IP login.live.com
$VPS_IP arc.msn.com
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# Discord domains
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP status.discord.com
$VPS_IP voice.discord.gg
EOFHOSTS

echo -e "${GREEN}✅ CoreDNS Smart DNS configured${NC}"

echo ""
echo -e "${YELLOW}[4/6] Installing and configuring HAProxy...${NC}"

apt-get update -qq
apt-get install -y haproxy

# Create HAProxy config
cat > /etc/haproxy/haproxy.cfg << 'EOFHAPROXY'
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon
    maxconn 50000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client  50s
    timeout server  50s

# Stats
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats

# HTTPS Frontend - Port 443
frontend https_front
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route DoH to local Nginx
    use_backend doh_local if { req_ssl_sni -i bypass.440.info }
    
    # Route Xbox/Discord to proxy backends
    use_backend xbox_proxy if { req_ssl_sni -m end xboxlive.com }
    use_backend xbox_proxy if { req_ssl_sni -m end xboxservices.com }
    use_backend xbox_proxy if { req_ssl_sni -m end live.com }
    use_backend xbox_proxy if { req_ssl_sni -m end microsoft.com }
    use_backend xbox_proxy if { req_ssl_sni -m end msftncsi.com }
    use_backend xbox_proxy if { req_ssl_sni -m end msftconnecttest.com }
    use_backend xbox_proxy if { req_ssl_sni -m end gamepass.com }
    
    use_backend discord_proxy if { req_ssl_sni -m end discord.com }
    use_backend discord_proxy if { req_ssl_sni -m end discord.gg }
    use_backend discord_proxy if { req_ssl_sni -m end discordapp.com }
    use_backend discord_proxy if { req_ssl_sni -m end discordapp.net }
    
    default_backend doh_local

# Backend: DoH (Nginx on 8443)
backend doh_local
    mode tcp
    server doh 127.0.0.1:8443

# Backend: Xbox (real servers)
backend xbox_proxy
    mode tcp
    balance roundrobin
    server-template xbox 5 xboxlive.com:443 check resolvers dns_resolvers

# Backend: Discord (real servers)
backend discord_proxy
    mode tcp
    balance roundrobin
    server-template discord 5 discord.com:443 check resolvers dns_resolvers

# DNS Resolver
resolvers dns_resolvers
    nameserver dns1 1.1.1.1:53
    nameserver dns2 8.8.8.8:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold valid 10s
EOFHAPROXY

echo -e "${GREEN}✅ HAProxy configured${NC}"

echo ""
echo -e "${YELLOW}[5/6] Starting services...${NC}"

# Start Docker
docker-compose up -d

echo "Waiting for containers..."
sleep 10

# Start HAProxy
systemctl enable haproxy
systemctl start haproxy

sleep 3

echo ""
echo -e "${YELLOW}[6/6] Verifying setup...${NC}"

# Check services
if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy running${NC}"
else
    echo -e "${RED}❌ HAProxy failed${NC}"
fi

if docker ps | grep -q doh-nginx; then
    echo -e "${GREEN}✅ doh-nginx running${NC}"
else
    echo -e "${RED}❌ doh-nginx not running${NC}"
fi

if docker ps | grep -q doh-backend; then
    echo -e "${GREEN}✅ doh-backend running${NC}"
else
    echo -e "${RED}❌ doh-backend not running${NC}"
fi

if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ coredns-smartdns running${NC}"
else
    echo -e "${RED}❌ coredns-smartdns not running${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Smart DNS Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Architecture:"
echo "  Port 443 → HAProxy (SNI routing)"
echo "    ↓ bypass.440.info → Nginx:8443 → doh-backend → CoreDNS"
echo "    ↓ xboxlive.com → Proxy → Real Xbox servers"
echo "    ↓ discord.com → Proxy → Real Discord servers"
echo ""
echo "CoreDNS Smart DNS:"
echo "  Xbox/Discord queries → Returns $VPS_IP"
echo "  Other queries → Cloudflare DoH"
echo ""
echo "Test it:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo "================================================"


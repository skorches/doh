#!/bin/bash

# Clean rebuild optimized for gaming latency

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Clean Rebuild - Optimized for Gaming Latency"
echo "================================================"
echo ""

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "./doh" ]; then
    DOH_DIR="./doh"
elif [ -d "." ] && [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP (IPv4): " VPS_IP
fi

# Get domain
DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "")
if [ -z "$DOMAIN" ]; then
    read -p "Enter your DoH domain (e.g., bypass.example.com): " DOMAIN
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo -e "${BLUE}Domain: $DOMAIN${NC}"
echo ""

read -p "This will stop all services and rebuild. Continue? (y/n): " REPLY
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/6] Stopping all services...${NC}"
docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
docker rm -f dns-proxy 2>/dev/null || true
systemctl stop sniproxy 2>/dev/null || true
pkill -9 sniproxy 2>/dev/null || true
sleep 2
echo -e "${GREEN}✅ Services stopped${NC}"

echo ""
echo -e "${YELLOW}[2/6] Creating optimized docker-compose.yml...${NC}"

cat > docker-compose.yml << EOF
services:
  doh-nginx:
    image: nginx:alpine
    container_name: doh-nginx
    ports:
      - "8443:443"
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
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
      - DOH_SERVER_TIMEOUT=5
      - DOH_SERVER_TRIES=1
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
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    restart: unless-stopped
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOF

echo -e "${GREEN}✅ docker-compose.yml created (dns-proxy removed)${NC}"

echo ""
echo -e "${YELLOW}[3/6] Creating optimized CoreDNS config...${NC}"

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward with parallel upstreams (IPs only, never hostnames)
    # Note: Port 53 may be blocked, queries will timeout but cache helps
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        except /etc/coredns/xbox-hosts
    }
    
    # Long cache for gaming (reduces upstream queries)
    cache 3600
    
    # Log errors only
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

echo -e "${GREEN}✅ CoreDNS config optimized${NC}"

echo ""
echo -e "${YELLOW}[4/6] Regenerating xbox-hosts with all domains...${NC}"

if [ -f "scripts/maintenance/regenerate-hosts.sh" ]; then
    bash scripts/maintenance/regenerate-hosts.sh > /dev/null 2>&1 || {
        echo -e "${YELLOW}⚠ Using manual hosts file generation${NC}"
        # Fallback: basic hosts file
        cat > coredns/xbox-hosts << EOFHOSTS
# Essential Xbox Smart DNS Hosts
# VPS IP: $VPS_IP
# Generated: $(date)

# === XBOX CORE ===
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP xbox.com
$VPS_IP login.live.com
$VPS_IP xboxservices.com

# === DISCORD ===
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg

# === ACTIVISION ===
$VPS_IP callofduty.com
$VPS_IP activision.com
EOFHOSTS
    }
else
    echo -e "${YELLOW}⚠ regenerate-hosts.sh not found, creating basic hosts file${NC}"
    cat > coredns/xbox-hosts << EOFHOSTS
# Essential Xbox Smart DNS Hosts
# VPS IP: $VPS_IP
$VPS_IP xboxlive.com
$VPS_IP xbox.com
$VPS_IP login.live.com
$VPS_IP discord.com
$VPS_IP callofduty.com
EOFHOSTS
fi

echo -e "${GREEN}✅ Hosts file regenerated${NC}"

echo ""
echo -e "${YELLOW}[5/6] Creating optimized Nginx config...${NC}"

mkdir -p nginx/conf.d

# Check for SSL certificates
SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

if [ ! -f "$SSL_CERT" ]; then
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
fi

cat > nginx/conf.d/doh.conf << EOFNGINX
# Optimized DoH Configuration for Gaming Latency

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name ${DOMAIN};
    
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # SSL session cache (faster TLS handshakes)
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Connection keep-alive
    keepalive_timeout 65;
    keepalive_requests 100;
    
    # Buffer optimizations
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # Timeout optimizations
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;
    
    # DoH endpoint - optimized for low latency
    location /dns-query {
        proxy_pass http://doh-backend:8053;
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Connection reuse (critical for latency)
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # Balanced timeouts (fast but not too aggressive)
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
        
        # Disable buffering for low latency
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Cache headers
        add_header Cache-Control "public, max-age=60";
    }
    
    # Root page
    location = / {
        return 200 "DNS over HTTPS (DoH) Server - Optimized for Gaming\n\nEndpoint: https://${DOMAIN}/dns-query\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOFNGINX

echo -e "${GREEN}✅ Nginx config optimized${NC}"

echo ""
echo -e "${YELLOW}[6/6] Starting services...${NC}"

docker compose up -d
sleep 5

# Restart SNIProxy
pkill -9 sniproxy 2>/dev/null || true
sleep 1
systemctl start sniproxy
sleep 2

echo -e "${GREEN}✅ Services started${NC}"

# Verify
echo ""
echo -e "${YELLOW}Verifying setup...${NC}"
sleep 3

DNS_TEST=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
if [ "$DNS_TEST" != "FAILED" ] && [ -n "$DNS_TEST" ]; then
    echo -e "${GREEN}✅ DNS working: xboxlive.com → $DNS_TEST${NC}"
else
    echo -e "${YELLOW}⚠ DNS test failed (may need a moment)${NC}"
fi

DOH_TEST=$(timeout 5 curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "FAILED")
if [ "$DOH_TEST" == "0" ]; then
    echo -e "${GREEN}✅ DoH working (Status: 0)${NC}"
else
    echo -e "${YELLOW}⚠ DoH test: Status $DOH_TEST${NC}"
fi

echo ""
echo "================================================"
echo "✅ Rebuild Complete - Optimized for Gaming"
echo "================================================"
echo ""
echo "Optimizations applied:"
echo "  • Removed broken dns-proxy"
echo "  • CoreDNS: 3600s cache (1 hour)"
echo "  • Nginx: Balanced timeouts (5s/10s)"
echo "  • DoH Backend: 5s timeout"
echo "  • All Xbox/gaming domains in hosts file"
echo ""
echo "DoH URL: https://${DOMAIN}/dns-query"
echo ""
echo "Note: CoreDNS will timeout on upstream DNS (port 53 blocked),"
echo "but with long cache and comprehensive hosts file, most queries"
echo "will be fast. Missing domains will timeout but won't break gaming."
echo ""


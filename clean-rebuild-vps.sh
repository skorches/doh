#!/bin/bash

# Clean rebuild of DoH + Smart DNS on VPS from scratch

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
echo "Clean Rebuild - DoH + Smart DNS"
echo "================================================"
echo ""
echo "This will:"
echo "  ✓ Stop all services"
echo "  ✓ Remove old containers and configs"
echo "  ✓ Rebuild everything from scratch"
echo ""
echo "Starting in 3 seconds... (Press Ctrl+C to cancel)"
sleep 3
echo ""

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Stop all services and clean up Docker
echo -e "${YELLOW}[1/8] Stopping all services and cleaning up...${NC}"
docker-compose down 2>/dev/null || true
docker-compose rm -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true
systemctl stop sniproxy 2>/dev/null || true
systemctl stop haproxy 2>/dev/null || true
pkill -9 sniproxy 2>/dev/null || true
pkill -9 haproxy 2>/dev/null || true
sleep 3
echo -e "${GREEN}✅ Services stopped and Docker cleaned${NC}"

# Step 2: Clean up old files
echo ""
echo -e "${YELLOW}[2/8] Cleaning up old files...${NC}"
rm -rf coredns/* nginx/* ssl/* 2>/dev/null || true
mkdir -p coredns nginx/conf.d ssl
echo -e "${GREEN}✅ Old files removed${NC}"

# Step 3: Create docker-compose.yml
echo ""
echo -e "${YELLOW}[3/8] Creating docker-compose.yml...${NC}"

cat > docker-compose.yml << 'EOF'
services:
  doh-nginx:
    image: nginx:alpine
    container_name: doh-nginx
    ports:
      - "8443:443"  # Internal port, SNIProxy listens on 443 externally
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
EOF

echo -e "${GREEN}✅ docker-compose.yml created${NC}"

# Step 4: Create CoreDNS config
echo ""
echo -e "${YELLOW}[4/8] Creating CoreDNS configuration...${NC}"

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to Cloudflare DNS
    forward . 1.1.1.1 1.0.0.1
    
    # Enable caching
    cache 300
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

# Create optimized xbox-hosts (essential domains only)
cat > coredns/xbox-hosts << EOFHOSTS
# Essential Xbox Smart DNS Hosts
# VPS IP: $VPS_IP
# Generated: $(date)

# === XBOX CORE ===
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP xnotify.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP settings.xboxlive.com
$VPS_IP profile.xboxlive.com

# === XBOX AUTHENTICATION ===
$VPS_IP auth.xboxlive.com
$VPS_IP device.auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP sisu.xboxlive.com

# === XBOX SERVICES ===
$VPS_IP xboxservices.com
$VPS_IP activity.xboxservices.com
$VPS_IP contentaccess.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP licensing.xboxservices.com
$VPS_IP catalog.xboxservices.com

# === GAME PASS ===
$VPS_IP gamepass.com
$VPS_IP catalog.gamepass.com

# === MICROSOFT LOGIN ===
$VPS_IP login.live.com
$VPS_IP account.live.com
$VPS_IP login.microsoftonline.com

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

# === TEREDO ===
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# === DISCORD ===
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
EOFHOSTS

echo -e "${GREEN}✅ CoreDNS configured${NC}"

# Step 5: Create Nginx config
echo ""
echo -e "${YELLOW}[5/8] Creating Nginx configuration...${NC}"

mkdir -p nginx/conf.d

cat > nginx/conf.d/doh.conf << 'EOFNGINX'
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    
    server_name bypass.440.info;
    
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location /dns-query {
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 10s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
}

server {
    listen 80;
    server_name bypass.440.info;
    return 301 https://$host$request_uri;
}
EOFNGINX

echo -e "${GREEN}✅ Nginx configured${NC}"

# Step 6: Setup SSL (Let's Encrypt if available, else self-signed)
echo ""
echo -e "${YELLOW}[6/8] Setting up SSL certificates...${NC}"

if [ -f /etc/letsencrypt/live/bypass.440.info/fullchain.pem ]; then
    echo "Using Let's Encrypt certificate"
    cp /etc/letsencrypt/live/bypass.440.info/fullchain.pem ssl/selfsigned.crt
    cp /etc/letsencrypt/live/bypass.440.info/privkey.pem ssl/selfsigned.key
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Let's Encrypt certificate copied${NC}"
else
    echo "Creating self-signed certificate"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/selfsigned.key \
        -out ssl/selfsigned.crt \
        -subj "/CN=bypass.440.info" 2>/dev/null
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Self-signed certificate created${NC}"
fi

# Step 7: Install and configure SNIProxy
echo ""
echo -e "${YELLOW}[7/8] Installing and configuring SNIProxy...${NC}"

apt-get update -qq
apt-get install -y sniproxy

cat > /etc/sniproxy.conf << 'EOFSNI'
user daemon

pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listen 443 {
    proto tls
    table https_hosts
    
    fallback 127.0.0.1:8443
    
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

table https_hosts {
    # DoH server - route to local nginx
    bypass\.440\.info$ 127.0.0.1:8443
    
    # Xbox domains - route to real servers
    .*\.xboxlive\.com$ *
    .*\.xboxservices\.com$ *
    .*\.xbox\.com$ *
    .*\.live\.com$ *
    .*\.microsoft\.com$ *
    .*\.microsoftonline\.com$ *
    .*\.msftncsi\.com$ *
    .*\.msftconnecttest\.com$ *
    .*\.windows\.com$ *
    .*\.msn\.com$ *
    .*\.gamepass\.com$ *
    
    # Discord domains
    .*\.discord\.com$ *
    .*\.discordapp\.com$ *
    .*\.discordapp\.net$ *
    .*\.discord\.gg$ *
    .*\.discord\.media$ *
}
EOFSNI

mkdir -p /var/log/sniproxy
chown nobody:nogroup /var/log/sniproxy

systemctl enable sniproxy
systemctl restart sniproxy
sleep 2

if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy running on port 443${NC}"
else
    echo -e "${RED}❌ SNIProxy failed to start${NC}"
    journalctl -u sniproxy -n 10 --no-pager
    exit 1
fi

# Step 8: Start Docker containers
echo ""
echo -e "${YELLOW}[8/8] Starting Docker containers...${NC}"

docker-compose up -d
sleep 5

# Verify
if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS running${NC}"
else
    echo -e "${RED}❌ CoreDNS failed${NC}"
    docker logs coredns-smartdns --tail 20
    exit 1
fi

if docker ps | grep -q "doh-backend.*Up"; then
    echo -e "${GREEN}✅ DoH backend running${NC}"
else
    echo -e "${RED}❌ DoH backend failed${NC}"
    exit 1
fi

# Open firewall ports
echo ""
echo -e "${YELLOW}Configuring firewall...${NC}"
ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
ufw allow 443/tcp comment "HTTPS/DoH/Xbox" 2>/dev/null || true
ufw allow 3074/tcp comment "Xbox Live" 2>/dev/null || true
ufw allow 3074/udp comment "Xbox Live UDP" 2>/dev/null || true

echo ""
echo "================================================"
echo -e "${GREEN}✅ Clean Rebuild Complete!${NC}"
echo "================================================"
echo ""
echo "Services Status:"
docker-compose ps
echo ""
echo "SNIProxy Status:"
systemctl status sniproxy --no-pager | head -5
echo ""
echo "Test DoH:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Expected: Should return VPS IP ($VPS_IP)"
echo ""
echo "================================================"


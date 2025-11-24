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
echo "Xbox Smart DNS + DoH Server Setup"
echo "================================================"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo "Install Docker: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Check for docker-compose (old) or docker compose (new)
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    echo "Install Docker Compose or use: apt-get install docker-compose"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl is not installed${NC}"
    echo "Install: apt-get update && apt-get install -y curl"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites OK${NC}"
echo ""

# Get configuration
INSTALL_DIR="/root/doh"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    read -p "Enter your VPS IP address manually: " VPS_IP
    if [ -z "$VPS_IP" ]; then
        echo -e "${RED}VPS IP is required!${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}Detected VPS IP: $VPS_IP${NC}"

# Ask for domain name
echo ""
read -p "Enter your domain name (e.g., bypass.440.info): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Domain name is required!${NC}"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  VPS IP: $VPS_IP"
echo "  Domain: $DOMAIN_NAME"
echo ""
read -p "Continue with installation? (y/n): " REPLY
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

# Step 1: Stop all services and clean up Docker
echo -e "${YELLOW}[1/8] Stopping all services and cleaning up...${NC}"
$DOCKER_COMPOSE_CMD down 2>/dev/null || true
$DOCKER_COMPOSE_CMD rm -f 2>/dev/null || true
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

# === GAME PUBLISHERS ===
# Activision (Call of Duty, Warzone)
$VPS_IP activision.com
$VPS_IP www.activision.com
$VPS_IP callofduty.com
$VPS_IP www.callofduty.com
$VPS_IP sledgehammergames.com
$VPS_IP infinityward.com
$VPS_IP treyarch.com
$VPS_IP activisionblizzard.com

# Electronic Arts (Battlefield, FIFA, etc.)
$VPS_IP ea.com
$VPS_IP www.ea.com
$VPS_IP easports.com
$VPS_IP www.easports.com
$VPS_IP eamobile.com
$VPS_IP swtor.com
$VPS_IP tnt-ea.com
$VPS_IP origin.com
$VPS_IP www.origin.com
$VPS_IP eaplay.com

# Ubisoft (Assassin's Creed, etc.)
$VPS_IP ubisoft.com
$VPS_IP www.ubisoft.com
$VPS_IP uplay.com
$VPS_IP ubisoftconnect.com
$VPS_IP ubisoftstore.com

# Epic Games (Fortnite)
$VPS_IP epicgames.com
$VPS_IP www.epicgames.com
$VPS_IP unrealengine.com
$VPS_IP fortnite.com

# Rockstar (GTA Online)
$VPS_IP rockstargames.com
$VPS_IP www.rockstargames.com
$VPS_IP socialclub.rockstargames.com

# 2K Games (NBA 2K, etc.)
$VPS_IP 2k.com
$VPS_IP www.2k.com
$VPS_IP 2ksports.com
$VPS_IP www.2ksports.com
$VPS_IP take2games.com

# Blizzard
$VPS_IP blizzard.com
$VPS_IP www.blizzard.com
$VPS_IP battle.net
$VPS_IP www.battle.net

# Riot Games
$VPS_IP riotgames.com
$VPS_IP www.riotgames.com
$VPS_IP leagueoflegends.com
$VPS_IP valorant.com

# Square Enix
$VPS_IP square-enix.com
$VPS_IP www.square-enix.com
$VPS_IP square-enix-games.com

# Bethesda
$VPS_IP bethesda.net
$VPS_IP www.bethesda.net
$VPS_IP bethesda.com
$VPS_IP www.bethesda.com

# CD Projekt
$VPS_IP cdprojekt.com
$VPS_IP www.cdprojekt.com
$VPS_IP gog.com
$VPS_IP www.gog.com
EOFHOSTS

echo -e "${GREEN}✅ CoreDNS configured${NC}"

# Step 5: Create Nginx config
echo ""
echo -e "${YELLOW}[5/8] Creating Nginx configuration...${NC}"

mkdir -p nginx/conf.d

cat > nginx/conf.d/doh.conf << EOFNGINX
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    
    server_name $DOMAIN_NAME;
    
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # DoH endpoint - proxy to backend
    location /dns-query {
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout 10s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
    
    # Root page - show info
    location = / {
        return 200 "DNS over HTTPS (DoH) Server\n\nEndpoint: https://$DOMAIN_NAME/dns-query\n\nThis is a DoH server for DNS queries.\n\nTo test:\n  curl -H 'accept: application/dns-json' 'https://$DOMAIN_NAME/dns-query?name=google.com&type=A'\n\nConfigure in your router's DoH settings:\n  https://$DOMAIN_NAME/dns-query\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen 80;
    server_name $DOMAIN_NAME;
    return 301 https://\$host\$request_uri;
}
EOFNGINX

echo -e "${GREEN}✅ Nginx configured${NC}"

# Step 6: Setup SSL (Let's Encrypt if available, else self-signed)
echo ""
echo -e "${YELLOW}[6/8] Setting up SSL certificates...${NC}"

if [ -f /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ]; then
    echo "Using Let's Encrypt certificate"
    cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ssl/selfsigned.crt
    cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem ssl/selfsigned.key
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Let's Encrypt certificate copied${NC}"
else
    echo "Creating self-signed certificate"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/selfsigned.key \
        -out ssl/selfsigned.crt \
        -subj "/CN=$DOMAIN_NAME" 2>/dev/null
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Self-signed certificate created${NC}"
    echo -e "${YELLOW}⚠ Note: For production, get Let's Encrypt certificate${NC}"
fi

# Step 7: Install and configure SNIProxy
echo ""
echo -e "${YELLOW}[7/8] Installing and configuring SNIProxy...${NC}"

apt-get update -qq
apt-get install -y sniproxy

# Escape domain for regex
DOMAIN_ESCAPED=$(echo "$DOMAIN_NAME" | sed 's/\./\\./g')

cat > /etc/sniproxy.conf << EOFSNI
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
    $DOMAIN_ESCAPED\$ 127.0.0.1:8443
    
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
    
    # Game Publisher domains
    # Activision
    .*\.activision\.com$ *
    .*\.callofduty\.com$ *
    .*\.sledgehammergames\.com$ *
    .*\.infinityward\.com$ *
    .*\.treyarch\.com$ *
    .*\.activisionblizzard\.com$ *
    
    # Electronic Arts
    .*\.ea\.com$ *
    .*\.easports\.com$ *
    .*\.eamobile\.com$ *
    .*\.swtor\.com$ *
    .*\.tnt-ea\.com$ *
    .*\.origin\.com$ *
    .*\.eaplay\.com$ *
    
    # Ubisoft
    .*\.ubisoft\.com$ *
    .*\.uplay\.com$ *
    .*\.ubisoftconnect\.com$ *
    .*\.ubisoftstore\.com$ *
    
    # Epic Games
    .*\.epicgames\.com$ *
    .*\.unrealengine\.com$ *
    .*\.fortnite\.com$ *
    
    # Rockstar
    .*\.rockstargames\.com$ *
    .*\.socialclub\.rockstargames\.com$ *
    
    # 2K Games
    .*\.2k\.com$ *
    .*\.2ksports\.com$ *
    .*\.take2games\.com$ *
    
    # Blizzard
    .*\.blizzard\.com$ *
    .*\.battle\.net$ *
    
    # Riot Games
    .*\.riotgames\.com$ *
    .*\.leagueoflegends\.com$ *
    .*\.valorant\.com$ *
    
    # Square Enix
    .*\.square-enix\.com$ *
    .*\.square-enix-games\.com$ *
    
    # Bethesda
    .*\.bethesda\.net$ *
    .*\.bethesda\.com$ *
    
    # CD Projekt
    .*\.cdprojekt\.com$ *
    .*\.gog\.com$ *
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

$DOCKER_COMPOSE_CMD up -d
sleep 8

# Verify containers are running
echo ""
echo -e "${YELLOW}Verifying containers...${NC}"

COREDNS_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "coredns-smartdns" || echo "0")
DOH_BACKEND_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "doh-backend" || echo "0")
DOH_NGINX_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "doh-nginx" || echo "0")

if [ "$COREDNS_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ CoreDNS running${NC}"
else
    echo -e "${YELLOW}⚠ CoreDNS status unclear, checking logs...${NC}"
    docker logs coredns-smartdns --tail 10 2>&1 | head -5
fi

if [ "$DOH_BACKEND_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ DoH backend running${NC}"
else
    echo -e "${RED}❌ DoH backend not running${NC}"
    docker logs doh-backend --tail 10 2>&1 | head -5
fi

if [ "$DOH_NGINX_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ DoH Nginx running${NC}"
else
    echo -e "${RED}❌ DoH Nginx not running${NC}"
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
$DOCKER_COMPOSE_CMD ps
echo ""
echo "SNIProxy Status:"
systemctl status sniproxy --no-pager | head -5
echo ""
echo "Test DoH:"
echo "  curl -H 'accept: application/dns-json' 'https://$DOMAIN_NAME/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Expected: Should return VPS IP ($VPS_IP)"
echo ""
echo "Configure your router DoH URL:"
echo "  https://$DOMAIN_NAME/dns-query"
echo ""
echo "To get Let's Encrypt certificate (recommended):"
echo "  ./scripts/setup/setup-letsencrypt.sh"
echo ""
echo "================================================"


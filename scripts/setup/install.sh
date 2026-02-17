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

# Check and install curl first (needed for Docker installation)
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}curl not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y curl
fi

# Check and install Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found, installing...${NC}"
    echo "This will install Docker using the official installer."
    read -p "Continue with Docker installation? (y/n): " REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Docker installation cancelled"
        exit 1
    fi
    
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    
    # Start Docker service
    systemctl start docker
    systemctl enable docker
    
    # Wait for Docker to be ready
    sleep 3
    
    echo -e "${GREEN}✅ Docker installed${NC}"
else
    echo -e "${GREEN}✅ Docker already installed${NC}"
fi

# Check for docker-compose (old) or docker compose (new)
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
    echo -e "${GREEN}✅ docker-compose found${NC}"
elif docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    echo -e "${GREEN}✅ docker compose found${NC}"
else
    echo -e "${YELLOW}Docker Compose not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y docker-compose-plugin || apt-get install -y docker-compose
    sleep 2
    
    # Check again
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}✅ docker-compose installed${NC}"
    elif docker compose version &> /dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        echo -e "${GREEN}✅ docker compose installed${NC}"
    else
        echo -e "${RED}❌ Failed to install Docker Compose${NC}"
        exit 1
    fi
fi

# Check for additional dependencies
echo -e "${YELLOW}Checking additional dependencies...${NC}"

# Check and install openssl (needed for SSL certificates)
if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}openssl not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y openssl
    echo -e "${GREEN}✅ openssl installed${NC}"
else
    echo -e "${GREEN}✅ openssl found${NC}"
fi

# Check and install ss (iproute2) - needed to check ports
if ! command -v ss &> /dev/null; then
    echo -e "${YELLOW}ss (iproute2) not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y iproute2
    echo -e "${GREEN}✅ iproute2 installed${NC}"
else
    echo -e "${GREEN}✅ ss (iproute2) found${NC}"
fi

# Check and install ufw (firewall) - optional but recommended
if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}ufw not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y ufw
    echo -e "${GREEN}✅ ufw installed${NC}"
else
    echo -e "${GREEN}✅ ufw found${NC}"
fi

echo -e "${GREEN}✅ All prerequisites OK${NC}"
echo ""

# Get configuration
INSTALL_DIR="/root/doh"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Get VPS IP (auto-detect with multiple fallbacks)
echo -e "${YELLOW}Auto-detecting VPS IP address...${NC}"
VPS_IP=""
# Try multiple services with timeout
for service in "ifconfig.me" "icanhazip.com" "ipinfo.io/ip" "api.ipify.org" "checkip.amazonaws.com"; do
    VPS_IP=$(curl -4 -s --max-time 5 "$service" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -n "$VPS_IP" ]; then
        break
    fi
done

# If still empty, try from network interface
if [ -z "$VPS_IP" ]; then
    # Try to get IP from default route interface
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
    fi
fi

# Validate IP format
if [ -n "$VPS_IP" ]; then
    if ! echo "$VPS_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        VPS_IP=""
    fi
fi

if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}⚠ Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP address (IPv4) manually: " VPS_IP
    if [ -z "$VPS_IP" ]; then
        echo -e "${RED}❌ VPS IP is required!${NC}"
        exit 1
    fi
    # Validate manual entry
    if ! echo "$VPS_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        echo -e "${RED}❌ Invalid IP address format!${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Auto-detected VPS IP: $VPS_IP${NC}"
fi

# Ask for domain name
echo ""
read -p "Enter your domain name (e.g., bypass.example.com): " DOMAIN_NAME
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

# Fix port 53 conflict (systemd-resolved)
echo ""
echo -e "${YELLOW}Checking port 53 availability...${NC}"
if ss -ulnp | grep -q ":53.*systemd-resolve" || ss -tlnp | grep -q ":53.*systemd-resolve"; then
    echo -e "${YELLOW}Port 53 is in use by systemd-resolved, fixing...${NC}"
    
    # Stop systemd-resolved
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    
    # Configure systemd-resolved to not use port 53
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/no-port-53.conf << 'EOFRESOLVED'
[Resolve]
DNSStubListener=no
EOFRESOLVED
    
    # Create static resolv.conf
    if [ -L /etc/resolv.conf ]; then
        rm -f /etc/resolv.conf
    fi
    cat > /etc/resolv.conf << 'EOFRESOLV'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
options use-vc
EOFRESOLV
    
    # Restart Docker to pick up changes
    systemctl restart docker 2>/dev/null || true
    sleep 2
    
    echo -e "${GREEN}✅ Port 53 conflict resolved${NC}"
else
    echo -e "${GREEN}✅ Port 53 is available${NC}"
fi

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

echo -e "${GREEN}✅ docker-compose.yml created${NC}"

# Step 4: Create CoreDNS config
echo ""
echo -e "${YELLOW}[4/8] Creating CoreDNS configuration...${NC}"

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    # CRITICAL: hosts plugin returns immediately, no cache/upstream needed
    # reload ensures hosts file is checked periodically (prevents stale entries)
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward with parallel upstreams and fast fail settings
    # max_fails and health_check prevent long timeouts when port 53 is blocked
    # except directive ensures hosts file domains NEVER go to upstream
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Enable caching (24-hour cache for maximum stability)
    # NOTE: Domains in hosts file bypass cache and upstream entirely
    # Cache only applies to domains NOT in hosts file
    # Long cache reduces upstream queries significantly (prevents timeouts)
    cache 86400 {
        success 86400
        denial 86400
    }
    
    # Log errors (helps diagnose issues)
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

# Generate xbox-hosts from template
if [ -f "coredns/xbox-hosts.template" ]; then
    sed -e "s/__VPS_IP__/$VPS_IP/g" -e "s/__DATE__/$(date)/g" coredns/xbox-hosts.template > coredns/xbox-hosts
    echo -e "${GREEN}✅ xbox-hosts generated from template${NC}"
else
    echo -e "${YELLOW}⚠ Template not found, generating xbox-hosts inline...${NC}"
cat > coredns/xbox-hosts << EOFHOSTS
# Smart DNS Hosts File
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
$VPS_IP xbox.com
$VPS_IP www.xbox.com
$VPS_IP xboxservices.com
$VPS_IP www.xboxservices.com
$VPS_IP activity.xboxservices.com
$VPS_IP contentaccess.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP licensing.xboxservices.com
$VPS_IP catalog.xboxservices.com
$VPS_IP live.com
$VPS_IP www.live.com
$VPS_IP microsoft.com
$VPS_IP www.microsoft.com
$VPS_IP microsoftonline.com
$VPS_IP msn.com
$VPS_IP windows.com
$VPS_IP msftncsi.com
$VPS_IP msftconnecttest.com

# === GAME PASS ===
$VPS_IP gamepass.com
$VPS_IP www.gamepass.com
$VPS_IP catalog.gamepass.com
$VPS_IP xboxgamepass.com

# === MICROSOFT LOGIN ===
$VPS_IP login.live.com
$VPS_IP account.live.com
$VPS_IP account.microsoft.com
$VPS_IP login.microsoftonline.com

# === MICROSOFT NETWORK CHECKS (NAT Detection) ===
# CRITICAL: These domains are required for Xbox NAT type detection
# Missing any of these will cause "NAT unavailable" errors
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftncsi.com
$VPS_IP ipv6.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv4.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com

# === OTHER MICROSOFT ===
$VPS_IP arc.msn.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com
$VPS_IP licensing.mp.microsoft.com

# === XBOX GAMING SUBDOMAINS (prevents disconnections) ===
$VPS_IP rta.xboxlive.com
$VPS_IP titlestorage.xboxlive.com
$VPS_IP titlestoragewus0505.blob.core.windows.net
$VPS_IP multiplayeractivity.xboxlive.com
$VPS_IP achievements.xboxlive.com
$VPS_IP userstats.xboxlive.com
$VPS_IP displaycatalog.mp.microsoft.com
$VPS_IP v10.events.data.microsoft.com
$VPS_IP v20.events.data.microsoft.com
# NOTE: a978.i6g1.akamai.net removed - Akamai CDN domains must resolve to real IPs for game assets (NBA 2K, etc.)
$VPS_IP ntp.servercore.com

# === NAT DETECTION ===
# CRITICAL: These domains are required for Xbox NAT type detection
# Missing any of these will cause "NAT unavailable" errors
$VPS_IP xbox.ipv6.microsoft.com
$VPS_IP xbox.ipv4.microsoft.com
$VPS_IP xbox.nat.microsoft.com
# NOTE: teredo.ipv6.microsoft.com must resolve to REAL Teredo servers (not VPS IP)
# Removing it from hosts file so it resolves correctly

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
$VPS_IP status.discord.com
$VPS_IP api.discord.com
$VPS_IP gateway.discord.com
$VPS_IP cdn.discord.com
$VPS_IP images-ext-1.discordapp.net
$VPS_IP images-ext-2.discordapp.net
$VPS_IP media.discordapp.com

# === GAME PUBLISHERS ===
# Activision / Call of Duty
# NOTE: ALL Call of Duty domains REMOVED - they cause disconnections/timeouts when routed through VPS
# CoD games (Warzone, Black Ops, etc.) need DIRECT, LOW-LATENCY connections to:
#   - Matchmaking servers (demonware)
#   - Game servers (actual gameplay)
#   - CDN servers (asset delivery)
# Routing through VPS causes: "Lost connection to host/server", timeouts, matchmaking failures
# Do NOT add: activision.com, callofduty.com, atvi.com, or ANY CoD/Activision subdomains

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
# NOTE: 2K Games domains removed - NBA 2K requires these to resolve to real IPs for matchmaking/CDN
# Do NOT add: 2k.com, 2ksports.com, take2games.com, or any CDN/matchmaking subdomains
# Adding these causes NBA 2K disconnections

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
fi

# Save VPS_IP to .env for future use
cat > .env << EOFENV
VPS_IP=$VPS_IP
DOMAIN=$DOMAIN_NAME
EOFENV
echo -e "${GREEN}✅ Configuration saved to .env${NC}"

echo -e "${GREEN}✅ CoreDNS configured${NC}"

# Step 5: Create Nginx config
echo ""
echo -e "${YELLOW}[5/8] Creating Nginx configuration...${NC}"

mkdir -p nginx/conf.d

# Determine SSL certificate paths
if [ -f /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ]; then
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
else
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
fi

cat > nginx/conf.d/doh.conf << EOFNGINX
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name $DOMAIN_NAME;
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Connection settings
    keepalive_timeout 65;
    client_max_body_size 10m;
    
    # Timeouts
    proxy_connect_timeout 10s;
    proxy_send_timeout 10s;
    proxy_read_timeout 10s;
    
    # DoH endpoint - support GET, POST, and OPTIONS (prevents HTTP 405 errors)
    location /dns-query {
        # Allow all DoH methods (GET, POST, OPTIONS)
        limit_except GET POST OPTIONS {
            deny all;
        }
        
        # Handle OPTIONS (CORS preflight)
        if (\$request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Content-Type";
            add_header Access-Control-Max-Age 3600;
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
        
        # Proxy to DoH backend
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # CORS headers for DoH
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
    }
    
    # Root page - show info
    location = / {
        return 200 "DNS over HTTPS (DoH) Server\n\nEndpoint: https://$DOMAIN_NAME/dns-query\n\nSupports: GET, POST, OPTIONS\n\nConfigure in your router's DoH settings:\n  https://$DOMAIN_NAME/dns-query\n";
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
    echo "Using existing Let's Encrypt certificate"
    cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ssl/selfsigned.crt
    cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem ssl/selfsigned.key
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Let's Encrypt certificate copied${NC}"
else
    echo ""
    echo "SSL Certificate Options:"
    echo "  1. Let's Encrypt (recommended - free, trusted)"
    echo "  2. Self-signed (quick setup, browser warnings)"
    echo ""
    read -p "Choose option (1 or 2, default: 2): " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-2}
    
    if [ "$SSL_CHOICE" == "1" ]; then
        echo ""
        echo "Let's Encrypt Requirements:"
        echo "  - Domain DNS A record must point to this VPS ($VPS_IP)"
        echo "  - Port 80 must be open"
        echo ""
        read -p "Enter your email for Let's Encrypt: " EMAIL
        if [ -z "$EMAIL" ]; then
            echo -e "${YELLOW}No email provided, using self-signed instead${NC}"
            SSL_CHOICE=2
        else
            # Install certbot if needed
            if ! command -v certbot &> /dev/null; then
                echo -e "${YELLOW}Installing certbot...${NC}"
                apt-get update -qq
                apt-get install -y certbot
            fi
            
            # Stop nginx temporarily
            $DOCKER_COMPOSE_CMD stop doh-nginx 2>/dev/null || true
            systemctl stop nginx 2>/dev/null || true
            
            # Get certificate
            echo -e "${YELLOW}Getting Let's Encrypt certificate...${NC}"
            if certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL" 2>/dev/null; then
                cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ssl/selfsigned.crt
                cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem ssl/selfsigned.key
                chmod 644 ssl/selfsigned.crt
                chmod 600 ssl/selfsigned.key
                echo -e "${GREEN}✅ Let's Encrypt certificate obtained!${NC}"
            else
                echo -e "${YELLOW}⚠ Failed to get Let's Encrypt certificate, using self-signed${NC}"
                SSL_CHOICE=2
            fi
        fi
    fi
    
    if [ "$SSL_CHOICE" == "2" ]; then
    echo "Creating self-signed certificate"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/selfsigned.key \
        -out ssl/selfsigned.crt \
            -subj "/CN=$DOMAIN_NAME" 2>/dev/null
    chmod 644 ssl/selfsigned.crt
    chmod 600 ssl/selfsigned.key
    echo -e "${GREEN}✅ Self-signed certificate created${NC}"
    fi
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
    # Activision / Call of Duty - REMOVED (causes disconnections when proxied)
    
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
    
    # 2K Games - REMOVED (NBA 2K requires direct connections for matchmaking/CDN)
    
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

# Fix systemd service to handle SNIProxy forking
SNIPROXY_SERVICE="/lib/systemd/system/sniproxy.service"
if [ ! -f "$SNIPROXY_SERVICE" ]; then
    SNIPROXY_SERVICE="/etc/systemd/system/sniproxy.service"
fi

if [ -f "$SNIPROXY_SERVICE" ]; then
    # Create override directory
    mkdir -p /etc/systemd/system/sniproxy.service.d/
    
    # Create override file for forking
    cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOFSERVICE'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOFSERVICE
    
    systemctl daemon-reload
    echo -e "${GREEN}✅ SNIProxy systemd service configured${NC}"
fi

# Kill any leftover sniproxy processes
pkill -9 sniproxy 2>/dev/null || true
sleep 1

# Enable and start SNIProxy
systemctl enable sniproxy 2>/dev/null || true
systemctl restart sniproxy
sleep 3

# Check if SNIProxy is actually listening (more reliable than systemd status)
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy running on port 443${NC}"
elif pgrep -f sniproxy > /dev/null; then
    echo -e "${GREEN}✅ SNIProxy process is running (listening on port 443)${NC}"
    # Verify it's listening
    if ss -tlnp | grep -q ":443"; then
        echo -e "${GREEN}✅ Port 443 is listening${NC}"
    fi
elif systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy service is active${NC}"
else
    echo -e "${YELLOW}⚠ SNIProxy may not be running, checking...${NC}"
    # Try to start manually
    if [ -f /etc/sniproxy.conf ]; then
        echo "Testing SNIProxy config..."
        if sniproxy -c /etc/sniproxy.conf -t 2>&1 | grep -q "valid"; then
            echo -e "${GREEN}✅ Config is valid, trying to start...${NC}"
            sniproxy -c /etc/sniproxy.conf -f &
            sleep 2
            if pgrep -f sniproxy > /dev/null; then
                echo -e "${GREEN}✅ SNIProxy started manually${NC}"
else
    echo -e "${RED}❌ SNIProxy failed to start${NC}"
                journalctl -u sniproxy -n 10 --no-pager 2>/dev/null || echo "No journal logs"
            fi
        else
            echo -e "${RED}❌ SNIProxy config has errors${NC}"
            sniproxy -c /etc/sniproxy.conf -t 2>&1 | head -10
        fi
    else
        echo -e "${RED}❌ SNIProxy config file not found${NC}"
    fi
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

# Verify critical NAT domains are present
echo ""
echo -e "${YELLOW}Verifying NAT detection domains...${NC}"
NAT_DOMAINS=("xbox.nat.microsoft.com" "xbox.ipv4.microsoft.com" "xbox.ipv6.microsoft.com" "dns.msftncsi.com" "ipv4.msftconnecttest.com")
MISSING_DOMAINS=()
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "$domain" "coredns/xbox-hosts"; then
        MISSING_DOMAINS+=("$domain")
    fi
done

if [ ${#MISSING_DOMAINS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All critical NAT domains present${NC}"
else
    echo -e "${RED}❌ Missing NAT domains: ${MISSING_DOMAINS[*]}${NC}"
    echo -e "${YELLOW}⚠ This may cause NAT detection issues!${NC}"
fi

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
echo -e "${YELLOW}⚠️  IMPORTANT for Xbox NAT Detection:${NC}"
echo "   - Ensure Xbox DNS is set to VPS IP: $VPS_IP"
echo "   - Settings → Network → Advanced → DNS Settings"
echo "   - Primary DNS: $VPS_IP"
echo "   - Restart Xbox after changing DNS to clear cache"
echo ""
echo -e "${YELLOW}⚠️  If NAT is still unavailable, check for Double NAT:${NC}"
echo "   - Double NAT occurs when router is behind ISP router/CGNAT"
echo "   - Can cause 'NAT unavailable' or 'Double NAT detected'"
echo "   - Solutions: Bridge mode, UPnP, Port forwarding (3074 TCP/UDP), or DMZ"
echo ""
echo "To get Let's Encrypt certificate (recommended):"
echo "  ./scripts/setup/setup-letsencrypt.sh"
echo ""
echo "================================================"


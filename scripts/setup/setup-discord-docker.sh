#!/bin/bash

# Setup Discord UDP proxy using Docker container with 3proxy

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
echo "Discord UDP Proxy Setup (Docker + 3proxy)"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP: " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found${NC}"
    exit 1
fi

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"

# Create 3proxy config
echo -e "${YELLOW}[1/4] Creating 3proxy configuration...${NC}"
mkdir -p 3proxy

cat > 3proxy/3proxy.cfg << 'EOF3PROXY'
# 3proxy configuration for Discord UDP proxy
log
logformat "- %U %C:%c %R:%r %O %I %h %T"
rotate 30

# Allow all connections
allow * * * 80-88,8080-8088 HTTP
allow * * * 443,8443 HTTPS
allow * * * 50000-65535 UDP

# SOCKS5 proxy with UDP support
socks -p1080
EOF3PROXY

echo -e "${GREEN}✅ Config created${NC}"

# Add 3proxy service to docker-compose.yml
echo ""
echo -e "${YELLOW}[2/4] Adding 3proxy to docker-compose.yml...${NC}"

if grep -q "3proxy-discord" docker-compose.yml; then
    echo -e "${GREEN}✅ 3proxy already in docker-compose.yml${NC}"
else
    # Backup
    cp docker-compose.yml docker-compose.yml.backup.$(date +%s)
    
    # Add 3proxy service before the networks section
    sed -i '/^networks:/i\
  # 3proxy SOCKS5 proxy for Discord voice (UDP)\
  3proxy-discord:\
    image: ubuntu:22.04\
    container_name: 3proxy-discord\
    command: sh -c "apt-get update && apt-get install -y wget make gcc build-essential && cd /tmp && wget -q https://github.com/z3APA3A/3proxy/archive/refs/heads/master.zip && unzip -q master.zip && cd 3proxy-master && make -f Makefile.Linux && /tmp/3proxy-master/bin/3proxy /etc/3proxy/3proxy.cfg"\
    volumes:\
      - ./3proxy/3proxy.cfg:/etc/3proxy/3proxy.cfg:ro\
    ports:\
      - "1080:1080/tcp"\
      - "1080:1080/udp"\
    restart: unless-stopped\
    networks:\
      - doh-network\
' docker-compose.yml
    
    echo -e "${GREEN}✅ Added 3proxy to docker-compose.yml${NC}"
fi

# Start 3proxy container
echo ""
echo -e "${YELLOW}[3/4] Starting 3proxy container...${NC}"
docker compose up -d 3proxy-discord 2>/dev/null || docker-compose up -d 3proxy-discord 2>/dev/null

sleep 5

if docker ps | grep -q 3proxy-discord; then
    echo -e "${GREEN}✅ 3proxy container started${NC}"
else
    echo -e "${YELLOW}⚠ Container might still be building (takes a few minutes)${NC}"
    echo "Check status: docker logs 3proxy-discord"
fi

# Configure firewall
echo ""
echo -e "${YELLOW}[4/4] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 1080/tcp comment "3proxy SOCKS5 TCP" 2>/dev/null || true
    ufw allow 1080/udp comment "3proxy SOCKS5 UDP" 2>/dev/null || true
    echo -e "${GREEN}✅ Firewall rules added${NC}"
fi

echo ""
echo "================================================"
echo "✅ 3proxy Docker Setup Complete!"
echo "================================================"
echo ""
echo "NOTE: First build takes 5-10 minutes (compiling 3proxy)"
echo "Check build progress: docker logs -f 3proxy-discord"
echo ""
echo "Once running, configure Discord:"
echo "  Settings → Connections → Proxy"
echo "  Proxy: $VPS_IP:1080"
echo "  Type: SOCKS5"
echo ""


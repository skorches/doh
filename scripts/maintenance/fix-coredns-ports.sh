#!/bin/bash

# Fix CoreDNS port mapping in docker-compose.yml

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
echo "Fixing CoreDNS Port Mapping"
echo "================================================"
echo ""

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"
echo -e "${BLUE}Using directory: $DOH_DIR${NC}"
echo ""

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found${NC}"
    exit 1
fi

# Backup
cp docker-compose.yml docker-compose.yml.backup.$(date +%s)
echo -e "${GREEN}✅ Backed up docker-compose.yml${NC}"

# Check if ports are already mapped
if grep -q "53:53" docker-compose.yml | grep -q "coredns-smartdns"; then
    echo -e "${GREEN}✅ Port 53 already mapped in docker-compose.yml${NC}"
else
    echo -e "${YELLOW}Adding port mapping for CoreDNS...${NC}"
    
    # Add ports section after command line
    if grep -q "coredns-smartdns" docker-compose.yml; then
        # Use sed to add ports after the command line
        sed -i '/coredns-smartdns:/,/networks:/ {
            /command: -conf \/etc\/coredns\/Corefile/a\
    ports:\
      - "53:53/udp"\
      - "53:53/tcp"
        }' docker-compose.yml
        
        echo -e "${GREEN}✅ Port mapping added${NC}"
    else
        echo -e "${RED}❌ Could not find coredns-smartdns service${NC}"
        exit 1
    fi
fi

# Restart CoreDNS with new port mapping
echo ""
echo -e "${YELLOW}Recreating CoreDNS container with port mapping...${NC}"
docker-compose down coredns-smartdns 2>/dev/null || docker compose down coredns-smartdns 2>/dev/null || true
docker-compose up -d coredns-smartdns 2>/dev/null || docker compose up -d coredns-smartdns 2>/dev/null
sleep 3

# Verify port mapping
echo ""
echo -e "${BLUE}Verifying port mapping...${NC}"
PORT_MAPPING=$(docker port coredns-smartdns 2>&1 | grep "53" || echo "")
if [ -n "$PORT_MAPPING" ]; then
    echo -e "${GREEN}✅ Port mapping active:${NC}"
    echo "$PORT_MAPPING"
else
    echo -e "${YELLOW}⚠ Port mapping not showing (might need a moment)${NC}"
fi

# Check if CoreDNS is listening
echo ""
echo -e "${BLUE}Checking if CoreDNS is listening on port 53...${NC}"
sleep 2
if ss -tlnp | grep -q ":53.*docker-proxy\|coredns"; then
    echo -e "${GREEN}✅ CoreDNS is listening on port 53${NC}"
else
    echo -e "${YELLOW}⚠ CoreDNS might not be listening yet${NC}"
fi

# Test DNS resolution
echo ""
echo -e "${BLUE}Testing DNS resolution...${NC}"
sleep 2

DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
ACTIVISION_DNS=$(timeout 3 dig @127.0.0.1 activision.com +short 2>/dev/null | head -1 || echo "FAILED")
XBOX_DNS=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS"
echo "  activision.com → $ACTIVISION_DNS"
echo "  xboxlive.com → $XBOX_DNS"

if [ "$DISCORD_DNS" != "FAILED" ] && [ "$ACTIVISION_DNS" != "FAILED" ]; then
    echo ""
    echo -e "${GREEN}✅ DNS resolution working!${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠ DNS may need a moment to start${NC}"
    echo "Try: dig @127.0.0.1 discord.com"
fi

echo ""
echo "================================================"
echo "Fix Complete"
echo "================================================"
echo ""


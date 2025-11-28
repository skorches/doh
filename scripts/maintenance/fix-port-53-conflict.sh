#!/bin/bash

# Fix port 53 conflict with systemd-resolved

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
echo "Fixing Port 53 Conflict with systemd-resolved"
echo "================================================"
echo ""

# Check if systemd-resolved is running
if systemctl is-active --quiet systemd-resolved; then
    echo -e "${YELLOW}systemd-resolved is running and using port 53${NC}"
    echo ""
    echo "Options:"
    echo "  1. Stop systemd-resolved (recommended for this setup)"
    echo "  2. Configure systemd-resolved to not use port 53"
    echo ""
    read -p "Stop systemd-resolved? (y/n): " REPLY
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Stopping systemd-resolved...${NC}"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        
        # Edit /etc/systemd/resolved.conf to disable DNS stub
        if [ -f /etc/systemd/resolved.conf ]; then
            echo -e "${YELLOW}Configuring systemd-resolved to not start...${NC}"
            sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
            sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
            if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then
                echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
            fi
        fi
        
        echo -e "${GREEN}✅ systemd-resolved stopped and disabled${NC}"
    else
        echo -e "${YELLOW}Keeping systemd-resolved running${NC}"
        echo "You'll need to configure it manually or use a different port for CoreDNS"
        exit 0
    fi
else
    echo -e "${GREEN}✅ systemd-resolved is not running${NC}"
fi

# Check what's using port 53
echo ""
echo -e "${BLUE}Checking port 53 status...${NC}"
PORT_53_USAGE=$(ss -tlnp | grep ":53 " || echo "")
if [ -n "$PORT_53_USAGE" ]; then
    echo -e "${YELLOW}⚠ Port 53 still in use:${NC}"
    echo "$PORT_53_USAGE"
    echo ""
    echo "Killing processes using port 53..."
    lsof -ti:53 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 2
else
    echo -e "${GREEN}✅ Port 53 is free${NC}"
fi

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "./doh" ]; then
    DOH_DIR="./doh"
elif [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"
echo -e "${BLUE}Using directory: $DOH_DIR${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

# Check if CoreDNS is listening
echo ""
echo -e "${BLUE}Checking if CoreDNS is listening on port 53...${NC}"
sleep 2
if ss -tlnp | grep -q ":53.*coredns\|docker-proxy"; then
    echo -e "${GREEN}✅ CoreDNS is listening on port 53${NC}"
else
    echo -e "${YELLOW}⚠ CoreDNS might not be listening on host port 53${NC}"
    echo "Checking container status..."
    docker ps | grep coredns-smartdns || echo "Container not running"
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
    echo -e "${RED}❌ DNS still not working${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check CoreDNS logs: docker logs coredns-smartdns"
    echo "  2. Check if port 53 is free: ss -tlnp | grep ':53'"
    echo "  3. Try restarting CoreDNS: docker restart coredns-smartdns"
    echo "  4. Check CoreDNS config: cat coredns/Corefile"
fi

echo ""
echo "================================================"
echo "Fix Complete"
echo "================================================"
echo ""


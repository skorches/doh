#!/bin/bash

# Comprehensive CoreDNS fix (ports, conflicts, connection issues)

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
echo "CoreDNS Comprehensive Fix"
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

# Step 1: Check port 53 conflict
echo -e "${YELLOW}[1/4] Checking port 53...${NC}"
PORT_53_USAGE=$(ss -tlnp | grep ":53 " || echo "")
if [ -n "$PORT_53_USAGE" ]; then
    echo -e "${YELLOW}⚠ Port 53 is in use:${NC}"
    echo "$PORT_53_USAGE"
    
    if echo "$PORT_53_USAGE" | grep -q "systemd-resolved"; then
        echo -e "${YELLOW}systemd-resolved is using port 53${NC}"
        read -p "Stop systemd-resolved? (y/n): " REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl stop systemd-resolved
            systemctl disable systemd-resolved
            sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
            sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
            if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf 2>/dev/null; then
                echo "DNSStubListener=no" >> /etc/systemd/resolved.conf 2>/dev/null || true
            fi
            echo -e "${GREEN}✅ systemd-resolved stopped${NC}"
        fi
    fi
else
    echo -e "${GREEN}✅ Port 53 is free${NC}"
fi

# Step 2: Check docker-compose port mapping
echo ""
echo -e "${YELLOW}[2/4] Checking docker-compose port mapping...${NC}"
if grep -q "coredns-smartdns" docker-compose.yml && grep -q "53:53" docker-compose.yml; then
    echo -e "${GREEN}✅ Port 53 mapped in docker-compose.yml${NC}"
else
    echo -e "${YELLOW}⚠ Port 53 not mapped, adding...${NC}"
    cp docker-compose.yml docker-compose.yml.backup.$(date +%s)
    
    # Add ports to coredns-smartdns
    sed -i '/coredns-smartdns:/,/networks:/ {
        /command: -conf \/etc\/coredns\/Corefile/a\
    ports:\
      - "53:53/udp"\
      - "53:53/tcp"
    }' docker-compose.yml
    
    echo -e "${GREEN}✅ Port mapping added${NC}"
fi

# Step 3: Restart CoreDNS
echo ""
echo -e "${YELLOW}[3/4] Restarting CoreDNS...${NC}"
docker compose down coredns-smartdns 2>/dev/null || docker-compose down coredns-smartdns 2>/dev/null || true
docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

# Step 4: Verify
echo ""
echo -e "${YELLOW}[4/4] Verifying CoreDNS...${NC}"
sleep 2

if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS container running${NC}"
    
    PORT_MAPPING=$(docker port coredns-smartdns 2>&1 | grep "53" || echo "")
    if [ -n "$PORT_MAPPING" ]; then
        echo -e "${GREEN}✅ Port mapping active${NC}"
    fi
    
    # Test DNS
    DNS_TEST=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DNS_TEST" != "FAILED" ]; then
        echo -e "${GREEN}✅ DNS responding: $DNS_TEST${NC}"
    else
        echo -e "${RED}❌ DNS not responding${NC}"
        echo "Check logs: docker logs coredns-smartdns"
    fi
else
    echo -e "${RED}❌ CoreDNS container not running${NC}"
    echo "Check logs: docker logs coredns-smartdns"
fi

echo ""
echo "================================================"
echo "✅ CoreDNS Fix Complete"
echo "================================================"
echo ""




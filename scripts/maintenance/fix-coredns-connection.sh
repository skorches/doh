#!/bin/bash

# Fix CoreDNS connection refused issue

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
echo "Fixing CoreDNS Connection Issue"
echo "================================================"
echo ""

cd /root/doh || cd /home/wars09/Cursor/doh || { echo -e "${RED}❌ Could not find doh directory${NC}"; exit 1; }

# Check if container is running
if ! docker ps | grep -q coredns-smartdns; then
    echo -e "${RED}❌ CoreDNS container not running${NC}"
    echo "Starting CoreDNS..."
    docker-compose up -d coredns-smartdns 2>/dev/null || docker compose up -d coredns-smartdns 2>/dev/null
    sleep 3
fi

# Check container status
echo -e "${BLUE}Checking CoreDNS container...${NC}"
CONTAINER_STATUS=$(docker ps --filter "name=coredns-smartdns" --format "{{.Status}}" | head -1)
echo "Status: $CONTAINER_STATUS"

# Check if port 53 is exposed
echo ""
echo -e "${BLUE}Checking port 53...${NC}"
PORT_53=$(docker port coredns-smartdns 2>/dev/null | grep "53" || echo "")
if [ -n "$PORT_53" ]; then
    echo -e "${GREEN}✅ Port 53 exposed: $PORT_53${NC}"
else
    echo -e "${YELLOW}⚠ Port 53 not exposed in docker-compose${NC}"
    echo "Checking docker-compose.yml..."
    
    if grep -q "53:53" docker-compose.yml; then
        echo -e "${GREEN}✅ Port 53 configured in docker-compose.yml${NC}"
    else
        echo -e "${RED}❌ Port 53 NOT configured${NC}"
        echo "CoreDNS needs port 53 exposed to work!"
    fi
fi

# Check container logs
echo ""
echo -e "${BLUE}Checking CoreDNS logs...${NC}"
docker logs coredns-smartdns --tail 20 2>&1 | head -10

# Check if CoreDNS is listening inside container
echo ""
echo -e "${BLUE}Checking if CoreDNS is listening inside container...${NC}"
docker exec coredns-smartdns ss -tuln 2>/dev/null | grep ":53" || echo "Could not check (container might not have ss command)"

# Test from inside container
echo ""
echo -e "${BLUE}Testing DNS from inside container...${NC}"
docker exec coredns-smartdns nslookup xboxlive.com 127.0.0.1 2>/dev/null | head -5 || echo "nslookup not available in container"

# Check if port 53 is in use on host
echo ""
echo -e "${BLUE}Checking if port 53 is in use on host...${NC}"
PORT_53_HOST=$(ss -tuln | grep ":53 " || echo "")
if [ -n "$PORT_53_HOST" ]; then
    echo -e "${YELLOW}⚠ Port 53 is in use on host:${NC}"
    echo "$PORT_53_HOST"
    echo ""
    echo "This might be blocking CoreDNS. Checking what's using it..."
    
    # Find process using port 53
    PID=$(lsof -ti:53 2>/dev/null | head -1 || echo "")
    if [ -n "$PID" ]; then
        PROCESS=$(ps -p "$PID" -o comm= 2>/dev/null || echo "unknown")
        echo -e "${YELLOW}Process using port 53: $PROCESS (PID: $PID)${NC}"
        
        if echo "$PROCESS" | grep -qE "systemd-resolved|dnsmasq|bind"; then
            echo -e "${YELLOW}⚠ System DNS resolver is using port 53${NC}"
            echo "This might conflict with CoreDNS."
            echo ""
            echo "Options:"
            echo "  1. Disable systemd-resolved (if using):"
            echo "     systemctl stop systemd-resolved"
            echo "     systemctl disable systemd-resolved"
            echo ""
            echo "  2. Or configure CoreDNS to use different port"
        fi
    fi
else
    echo -e "${GREEN}✅ Port 53 is free on host${NC}"
fi

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null
sleep 3

# Test again
echo ""
echo -e "${BLUE}Testing CoreDNS after restart...${NC}"
sleep 2
if timeout 2 dig +short xboxlive.com @127.0.0.1 > /dev/null 2>&1; then
    RESULT=$(dig +short xboxlive.com @127.0.0.1 | head -1)
    echo -e "${GREEN}✅ CoreDNS responding: $RESULT${NC}"
else
    echo -e "${RED}❌ CoreDNS still not responding${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check logs: docker logs coredns-smartdns"
    echo "  2. Check config: cat coredns/Corefile"
    echo "  3. Check if systemd-resolved is using port 53:"
    echo "     systemctl status systemd-resolved"
    echo "  4. Try stopping systemd-resolved:"
    echo "     systemctl stop systemd-resolved"
    echo "     systemctl disable systemd-resolved"
fi

echo ""



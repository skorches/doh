#!/bin/bash

# Complete cleanup - removes all DoH/Smart DNS setup

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
echo "Complete Cleanup - Removing All DoH Setup"
echo "================================================"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will remove ALL DoH/Smart DNS setup${NC}"
echo "This includes:"
echo "  • All Docker containers"
echo "  • All Docker volumes"
echo "  • All configuration files"
echo "  • SNIProxy service"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "[1/6] Stopping all Docker containers..."
cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  doh directory not found, checking for containers...${NC}"
}

docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
docker stop coredns-smartdns doh-nginx doh-backend 2>/dev/null || true
docker rm coredns-smartdns doh-nginx doh-backend 2>/dev/null || true
echo -e "${GREEN}✅ Docker containers stopped${NC}"
echo ""

echo "[2/6] Removing Docker volumes..."
docker volume prune -f 2>/dev/null || true
echo -e "${GREEN}✅ Docker volumes removed${NC}"
echo ""

echo "[3/6] Stopping and removing SNIProxy..."
systemctl stop sniproxy 2>/dev/null || true
systemctl disable sniproxy 2>/dev/null || true
apt-get remove -y sniproxy 2>/dev/null || true
echo -e "${GREEN}✅ SNIProxy removed${NC}"
echo ""

echo "[4/6] Removing configuration files..."
if [ -d "/root/doh" ]; then
    cd /root/doh
    rm -rf coredns/* nginx/* ssl/* 2>/dev/null || true
    rm -f docker-compose.yml 2>/dev/null || true
    echo -e "${GREEN}✅ Configuration files removed${NC}"
else
    echo -e "${YELLOW}⚠️  /root/doh not found, skipping file removal${NC}"
fi
echo ""

echo "[5/6] Cleaning up Docker network..."
docker network prune -f 2>/dev/null || true
echo -e "${GREEN}✅ Docker networks cleaned${NC}"
echo ""

echo "[6/6] Verifying cleanup and port release..."
echo "Checking for remaining containers:"
REMAINING=$(docker ps -a --filter "name=coredns-smartdns" --filter "name=doh-nginx" --filter "name=doh-backend" --format "{{.Names}}" 2>/dev/null | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✅ No containers remaining${NC}"
else
    echo -e "${YELLOW}⚠️  Some containers still exist:${NC}"
    docker ps -a --filter "name=coredns-smartdns" --filter "name=doh-nginx" --filter "name=doh-backend" --format "{{.Names}}"
fi

echo ""
echo "Checking SNIProxy:"
if systemctl is-active sniproxy >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  SNIProxy is still running${NC}"
else
    echo -e "${GREEN}✅ SNIProxy is stopped${NC}"
fi

echo ""
echo "Checking ports are free:"
PORTS_USED=0

# Check port 53 (DNS)
if ss -tuln | grep -q ":53"; then
    echo -e "${YELLOW}⚠️  Port 53 still in use:${NC}"
    ss -tuln | grep ":53"
    PORTS_USED=1
else
    echo -e "${GREEN}✅ Port 53 (DNS) is free${NC}"
fi

# Check port 443 (SNIProxy)
if ss -tuln | grep -q ":443"; then
    PROCESS=$(ss -tlnp | grep ":443" | grep -oE 'users:\(\([^)]+\)' | head -1)
    if echo "$PROCESS" | grep -q "sniproxy"; then
        echo -e "${YELLOW}⚠️  Port 443 still in use by SNIProxy${NC}"
        PORTS_USED=1
    else
        echo -e "${YELLOW}⚠️  Port 443 in use by other process:${NC}"
        ss -tlnp | grep ":443"
        PORTS_USED=1
    fi
else
    echo -e "${GREEN}✅ Port 443 (HTTPS) is free${NC}"
fi

# Check port 8443 (Nginx internal)
if ss -tuln | grep -q ":8443"; then
    echo -e "${YELLOW}⚠️  Port 8443 still in use:${NC}"
    ss -tuln | grep ":8443"
    PORTS_USED=1
else
    echo -e "${GREEN}✅ Port 8443 (Nginx internal) is free${NC}"
fi

# Check port 8080 (Nginx internal)
if ss -tuln | grep -q ":8080"; then
    echo -e "${YELLOW}⚠️  Port 8080 still in use:${NC}"
    ss -tuln | grep ":8080"
    PORTS_USED=1
else
    echo -e "${GREEN}✅ Port 8080 (Nginx internal) is free${NC}"
fi

if [ $PORTS_USED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All ports are free!${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Some ports are still in use${NC}"
    echo "If you see this, you may need to:"
    echo "  • Kill remaining processes manually"
    echo "  • Check for other services using these ports"
fi
echo ""

echo "================================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "All DoH/Smart DNS setup has been removed."
echo ""
echo "To reinstall from scratch:"
echo "  1. cd /root/doh"
echo "  2. git pull origin main  # Get latest code"
echo "  3. bash scripts/setup/install.sh"
echo ""
echo "The install script will:"
echo "  • Install all dependencies"
echo "  • Set up Docker containers"
echo "  • Configure CoreDNS"
echo "  • Set up SNIProxy"
echo "  • Generate SSL certificates"
echo "  • Configure all domains"
echo ""


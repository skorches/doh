#!/bin/bash

# Ensure all services needed for Xbox are running

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

echo "================================================"
echo "Ensuring All Xbox Services Are Running"
echo "================================================"
echo ""

# 1. Docker service
echo "[1/5] Starting Docker service..."
if systemctl is-active docker >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker is already running${NC}"
else
    systemctl start docker
    sleep 2
    if systemctl is-active docker >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker started${NC}"
    else
        echo -e "${RED}❌ Failed to start Docker${NC}"
        exit 1
    fi
fi
echo ""

# 2. Docker containers
echo "[2/5] Starting Docker containers..."
if [ -f "docker-compose.yml" ]; then
    docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || {
        echo -e "${YELLOW}⚠️  docker-compose failed, trying individual containers...${NC}"
        docker start coredns-smartdns doh-nginx doh-backend 2>/dev/null || true
    }
    sleep 5
    
    # Check each container
    if docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$"; then
        echo -e "${GREEN}✅ coredns-smartdns: Running${NC}"
    else
        echo -e "${RED}❌ coredns-smartdns: Failed to start${NC}"
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^doh-backend$"; then
        echo -e "${GREEN}✅ doh-backend: Running${NC}"
    else
        echo -e "${RED}❌ doh-backend: Failed to start${NC}"
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^doh-nginx$"; then
        echo -e "${GREEN}✅ doh-nginx: Running${NC}"
    else
        echo -e "${RED}❌ doh-nginx: Failed to start${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  docker-compose.yml not found${NC}"
    echo "Starting containers individually..."
    docker start coredns-smartdns doh-nginx doh-backend 2>/dev/null || true
fi
echo ""

# 3. SNIProxy
echo "[3/5] Starting SNIProxy..."
if systemctl is-active sniproxy >/dev/null 2>&1; then
    echo -e "${GREEN}✅ SNIProxy is already running${NC}"
else
    systemctl start sniproxy
    sleep 2
    if systemctl is-active sniproxy >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SNIProxy started${NC}"
    else
        echo -e "${YELLOW}⚠️  SNIProxy failed to start (may not be installed)${NC}"
        echo "  Install with: apt-get install -y sniproxy"
    fi
fi
echo ""

# 4. Verify hosts file
echo "[4/5] Verifying hosts file..."
HOSTS_FILE="coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${YELLOW}⚠️  Hosts file not found, regenerating...${NC}"
    if [ -f "scripts/maintenance/regenerate-hosts.sh" ]; then
        bash scripts/maintenance/regenerate-hosts.sh
    else
        echo -e "${RED}❌ Cannot regenerate hosts file (script not found)${NC}"
    fi
else
    echo -e "${GREEN}✅ Hosts file exists${NC}"
    
    # Check if it has content
    LINE_COUNT=$(wc -l < "$HOSTS_FILE" 2>/dev/null || echo "0")
    if [ "$LINE_COUNT" -lt 10 ]; then
        echo -e "${YELLOW}⚠️  Hosts file seems empty or incomplete ($LINE_COUNT lines)${NC}"
        echo "  Regenerating..."
        if [ -f "scripts/maintenance/regenerate-hosts.sh" ]; then
            bash scripts/maintenance/regenerate-hosts.sh
        fi
    else
        echo -e "${GREEN}✅ Hosts file has content ($LINE_COUNT lines)${NC}"
    fi
fi
echo ""

# 5. Restart CoreDNS to ensure hosts file is loaded
echo "[5/5] Restarting CoreDNS to load hosts file..."
docker restart coredns-smartdns 2>/dev/null || true
sleep 3
echo -e "${GREEN}✅ CoreDNS restarted${NC}"
echo ""

# Quick test
echo "================================================"
echo "Quick Test"
echo "================================================"
echo ""

# Test DNS
echo "Testing DNS (port 53):"
DNS_RESULT=$(timeout 2 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
if [ "$DNS_RESULT" != "FAILED" ] && [ -n "$DNS_RESULT" ]; then
    echo -e "  ${GREEN}✅ DNS working: xboxlive.com → $DNS_RESULT${NC}"
else
    echo -e "  ${RED}❌ DNS not responding${NC}"
fi

# Test DoH
echo "Testing DoH (port 8443):"
DOH_RESULT=$(curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>/dev/null | grep -o '"Status":[0-9]*' || echo "FAILED")
if echo "$DOH_RESULT" | grep -q "Status\":0"; then
    echo -e "  ${GREEN}✅ DoH working${NC}"
else
    echo -e "  ${RED}❌ DoH not responding${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Service Check Complete!${NC}"
echo "================================================"
echo ""
echo "Run full verification:"
echo "  bash scripts/maintenance/verify-xbox-services.sh"
echo ""


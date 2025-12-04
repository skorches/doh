#!/bin/bash

# Check if all services are working after VPS restart

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Post-Restart Service Check"
echo "================================================"
echo ""

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "./doh" ]; then
    DOH_DIR="./doh"
elif [ -d "." ] && [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"

ISSUES=0

# 1. Check Docker
echo -e "${YELLOW}[1/8] Docker Service${NC}"
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✅ Docker is running${NC}"
else
    echo -e "${RED}❌ Docker is not running${NC}"
    echo "   Starting Docker..."
    systemctl start docker
    sleep 3
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✅ Docker started${NC}"
    else
        echo -e "${RED}❌ Failed to start Docker${NC}"
        ISSUES=$((ISSUES + 1))
    fi
fi

# 2. Check Docker containers
echo ""
echo -e "${YELLOW}[2/8] Docker Containers${NC}"

EXPECTED_CONTAINERS=("coredns-smartdns" "doh-backend" "doh-nginx")
MISSING_CONTAINERS=()

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        STATUS=$(docker ps --format "{{.Status}}" --filter "name=${container}")
        echo -e "${GREEN}✅ $container: Running ($STATUS)${NC}"
    else
        echo -e "${RED}❌ $container: Not running${NC}"
        MISSING_CONTAINERS+=("$container")
        ISSUES=$((ISSUES + 1))
    fi
done

# Start missing containers
if [ ${#MISSING_CONTAINERS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Starting missing containers...${NC}"
    docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || {
        echo -e "${RED}❌ Failed to start containers${NC}"
    }
    sleep 5
fi

# 3. Check SNIProxy
echo ""
echo -e "${YELLOW}[3/8] SNIProxy Service${NC}"
if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
elif systemctl is-enabled --quiet sniproxy; then
    echo -e "${YELLOW}⚠ SNIProxy is enabled but not running${NC}"
    echo "   Starting SNIProxy..."
    systemctl start sniproxy
    sleep 2
    if systemctl is-active --quiet sniproxy; then
        echo -e "${GREEN}✅ SNIProxy started${NC}"
    else
        echo -e "${RED}❌ Failed to start SNIProxy${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "${YELLOW}⚠ SNIProxy is not enabled${NC}"
fi

# 4. Check 3proxy (if installed)
echo ""
echo -e "${YELLOW}[4/8] 3proxy Service (Discord)${NC}"
if systemctl list-unit-files | grep -q "3proxy.*enabled"; then
    if systemctl is-active --quiet 3proxy-discord 2>/dev/null || systemctl is-active --quiet 3proxy 2>/dev/null; then
        echo -e "${GREEN}✅ 3proxy is running${NC}"
    else
        echo -e "${YELLOW}⚠ 3proxy is enabled but not running${NC}"
        systemctl start 3proxy-discord 2>/dev/null || systemctl start 3proxy 2>/dev/null || true
    fi
else
    echo -e "${BLUE}ℹ 3proxy not configured (optional)${NC}"
fi

# 5. Check port 443
echo ""
echo -e "${YELLOW}[5/8] Port 443 (SNIProxy)${NC}"
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
else
    echo -e "${RED}❌ Nothing listening on port 443${NC}"
    ISSUES=$((ISSUES + 1))
fi

# 6. Check port 53
echo ""
echo -e "${YELLOW}[6/8] Port 53 (CoreDNS)${NC}"
if ss -tlnp | grep -q ":53.*coredns" || ss -ulnp | grep -q ":53.*coredns"; then
    echo -e "${GREEN}✅ CoreDNS listening on port 53${NC}"
else
    echo -e "${RED}❌ CoreDNS not listening on port 53${NC}"
    ISSUES=$((ISSUES + 1))
fi

# 7. Test DNS resolution
echo ""
echo -e "${YELLOW}[7/8] DNS Resolution Test${NC}"

TEST_DOMAINS=("xboxlive.com" "callofduty.com" "discord.com")
DNS_SUCCESS=0
DNS_FAILED=0

for domain in "${TEST_DOMAINS[@]}"; do
    RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$RESULT" != "FAILED" ] && [ -n "$RESULT" ]; then
        echo -e "${GREEN}✅ $domain → $RESULT${NC}"
        DNS_SUCCESS=$((DNS_SUCCESS + 1))
    else
        echo -e "${RED}❌ $domain → FAILED${NC}"
        DNS_FAILED=$((DNS_FAILED + 1))
    fi
done

if [ "$DNS_FAILED" -gt 0 ]; then
    ISSUES=$((ISSUES + 1))
fi

# 8. Test DoH endpoint
echo ""
echo -e "${YELLOW}[8/8] DoH Endpoint Test${NC}"

# Get domain from config
DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "localhost")
if [ "$DOMAIN" != "localhost" ]; then
    DOH_URL="https://$DOMAIN/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
else
    DOH_URL="https://localhost:8443/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
fi

DOH_RESULT=$(timeout 5 $DOH_CMD -H 'accept: application/dns-json' "$DOH_URL" 2>&1 | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "FAILED")

if [ "$DOH_RESULT" == "0" ]; then
    echo -e "${GREEN}✅ DoH endpoint working (Status: 0)${NC}"
elif [ "$DOH_RESULT" == "FAILED" ]; then
    echo -e "${RED}❌ DoH endpoint not responding${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${YELLOW}⚠ DoH endpoint returned Status: $DOH_RESULT${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✅ All services are working correctly!${NC}"
    echo ""
    echo "Everything started successfully after restart."
    echo ""
    echo "Next steps:"
    echo "  • Test Xbox connectivity"
    echo "  • Test Warzone matchmaking"
    echo "  • Monitor DoH stability: ./scripts/maintenance/check-doh-stability.sh"
else
    echo -e "${YELLOW}⚠ Found $ISSUES issue(s)${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check container logs: docker logs <container-name>"
    echo "  2. Check service status: systemctl status <service-name>"
    echo "  3. Restart services: docker compose restart"
    echo "  4. Check firewall: ufw status"
fi

echo ""


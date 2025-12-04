#!/bin/bash

# Check DoH stability and diagnose issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "DoH Stability Check"
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

# 1. Check container status
echo -e "${YELLOW}[1/7] Container Status${NC}"
echo ""

COREDNS_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "coredns-smartdns" || echo "0")
DOH_BACKEND_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "doh-backend" || echo "0")
DOH_NGINX_RUNNING=$(docker ps --format "{{.Names}}" | grep -c "doh-nginx" || echo "0")

if [ "$COREDNS_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ CoreDNS: Running${NC}"
else
    echo -e "${RED}❌ CoreDNS: Not running${NC}"
fi

if [ "$DOH_BACKEND_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ DoH Backend: Running${NC}"
else
    echo -e "${RED}❌ DoH Backend: Not running${NC}"
fi

if [ "$DOH_NGINX_RUNNING" -eq 1 ]; then
    echo -e "${GREEN}✅ DoH Nginx: Running${NC}"
else
    echo -e "${RED}❌ DoH Nginx: Not running${NC}"
fi

# 2. Check DoH backend health
echo ""
echo -e "${YELLOW}[2/7] DoH Backend Health${NC}"
HEALTH=$(docker inspect doh-backend --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
if [ "$HEALTH" == "healthy" ]; then
    echo -e "${GREEN}✅ Health Status: $HEALTH${NC}"
else
    echo -e "${YELLOW}⚠ Health Status: $HEALTH${NC}"
fi

# 3. Check recent errors
echo ""
echo -e "${YELLOW}[3/7] Recent Errors (Last 50 logs)${NC}"

COREDNS_ERRORS=$(docker logs coredns-smartdns --tail 50 2>&1 | grep -i "error\|timeout\|servfail" | wc -l)
DOH_ERRORS=$(docker logs doh-backend --tail 50 2>&1 | grep -i "error\|timeout\|fail\|panic" | wc -l)

if [ "$COREDNS_ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✅ CoreDNS: No errors${NC}"
else
    echo -e "${YELLOW}⚠ CoreDNS: $COREDNS_ERRORS errors found${NC}"
    echo "   Recent errors:"
    docker logs coredns-smartdns --tail 50 2>&1 | grep -i "error\|timeout\|servfail" | tail -3 | sed 's/^/   /'
fi

if [ "$DOH_ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✅ DoH Backend: No errors${NC}"
else
    echo -e "${YELLOW}⚠ DoH Backend: $DOH_ERRORS errors found${NC}"
    echo "   Recent errors:"
    docker logs doh-backend --tail 50 2>&1 | grep -i "error\|timeout\|fail" | tail -3 | sed 's/^/   /'
fi

# 4. Test DNS resolution
echo ""
echo -e "${YELLOW}[4/7] DNS Resolution Test${NC}"

TEST_DOMAINS=("google.com" "xboxlive.com" "callofduty.com" "discord.com")
SUCCESS=0
FAILED=0

for domain in "${TEST_DOMAINS[@]}"; do
    RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$RESULT" != "FAILED" ] && [ -n "$RESULT" ]; then
        echo -e "${GREEN}✅ $domain → $RESULT${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${RED}❌ $domain → FAILED${NC}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✅ All DNS tests passed ($SUCCESS/$SUCCESS)${NC}"
else
    echo -e "${YELLOW}⚠ Some DNS tests failed ($SUCCESS passed, $FAILED failed)${NC}"
fi

# 5. Test DoH endpoint
echo ""
echo -e "${YELLOW}[5/7] DoH Endpoint Test${NC}"

# Get domain from config
DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "localhost")
if [ "$DOMAIN" == "localhost" ]; then
    DOH_URL="https://localhost:8443/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
else
    DOH_URL="https://$DOMAIN/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
fi

DOH_RESULT=$(timeout 5 $DOH_CMD -H 'accept: application/dns-json' "$DOH_URL" 2>&1 | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "FAILED")

if [ "$DOH_RESULT" == "0" ]; then
    echo -e "${GREEN}✅ DoH endpoint responding (Status: 0 = Success)${NC}"
elif [ "$DOH_RESULT" == "FAILED" ]; then
    echo -e "${RED}❌ DoH endpoint not responding${NC}"
else
    echo -e "${YELLOW}⚠ DoH endpoint returned Status: $DOH_RESULT${NC}"
fi

# 6. Check resource usage
echo ""
echo -e "${YELLOW}[6/7] Resource Usage${NC}"

COREDNS_CPU=$(docker stats coredns-smartdns --no-stream --format "{{.CPUPerc}}" 2>/dev/null || echo "N/A")
COREDNS_MEM=$(docker stats coredns-smartdns --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
DOH_CPU=$(docker stats doh-backend --no-stream --format "{{.CPUPerc}}" 2>/dev/null || echo "N/A")
DOH_MEM=$(docker stats doh-backend --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")

echo "   CoreDNS: CPU $COREDNS_CPU | Memory $COREDNS_MEM"
echo "   DoH Backend: CPU $DOH_CPU | Memory $DOH_MEM"

# 7. Check network connectivity to upstream DNS
echo ""
echo -e "${YELLOW}[7/7] Upstream DNS Connectivity${NC}"

DNS_SERVERS=("1.1.1.1:53" "8.8.8.8:53")
for dns in "${DNS_SERVERS[@]}"; do
    if timeout 2 nc -zu $(echo $dns | cut -d: -f1) $(echo $dns | cut -d: -f2) 2>/dev/null; then
        echo -e "${GREEN}✅ $dns: Reachable${NC}"
    else
        echo -e "${RED}❌ $dns: Not reachable${NC}"
    fi
done

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

ISSUES=0

if [ "$COREDNS_RUNNING" -ne 1 ] || [ "$DOH_BACKEND_RUNNING" -ne 1 ] || [ "$DOH_NGINX_RUNNING" -ne 1 ]; then
    echo -e "${RED}❌ Some containers are not running${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$HEALTH" != "healthy" ]; then
    echo -e "${YELLOW}⚠ DoH backend health check: $HEALTH${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$COREDNS_ERRORS" -gt 10 ] || [ "$DOH_ERRORS" -gt 10 ]; then
    echo -e "${YELLOW}⚠ High error count detected${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$FAILED" -gt 0 ]; then
    echo -e "${YELLOW}⚠ DNS resolution failures detected${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✅ DoH appears stable${NC}"
    echo ""
    echo "Monitor for a few minutes during Warzone matchmaking"
    echo "to ensure stability under load."
else
    echo -e "${YELLOW}⚠ Found $ISSUES potential issue(s)${NC}"
    echo ""
    echo "Recommendations:"
    echo "  • Check VPS network connectivity"
    echo "  • Monitor logs: docker logs -f coredns-smartdns"
    echo "  • Add missing domains to xbox-hosts if errors persist"
fi

echo ""


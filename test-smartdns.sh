#!/bin/bash

# Test Smart DNS Setup
# Verify that Xbox domains return VPS IP

echo "================================================"
echo "Smart DNS Test"
echo "================================================"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VPS_IP=$(curl -s ifconfig.me)
DOMAIN="bypass.440.info"

echo "VPS IP: $VPS_IP"
echo "DoH Domain: $DOMAIN"
echo ""

echo "Testing Xbox domains through your DoH server..."
echo "These should return VPS IP ($VPS_IP) not real Xbox IPs"
echo ""

# Test function
test_domain() {
    local domain=$1
    echo -n "Testing $domain ... "
    
    result=$(curl -s -H 'accept: application/dns-json' "https://$DOMAIN/dns-query?name=$domain&type=A" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ "$result" = "$VPS_IP" ]; then
        echo -e "${GREEN}✅ Returns VPS IP: $result${NC}"
        return 0
    elif [ -n "$result" ]; then
        echo -e "${RED}❌ Returns real IP: $result (should be $VPS_IP)${NC}"
        return 1
    else
        echo -e "${RED}❌ No response${NC}"
        return 1
    fi
}

# Test Xbox domains
echo "Testing Xbox Live domains:"
echo "---"
test_domain "xboxlive.com"
test_domain "title.auth.xboxlive.com"
test_domain "notify.xboxlive.com"
test_domain "xccs.xboxlive.com"

echo ""
echo "Testing Xbox Services:"
echo "---"
test_domain "contentaccess.exp.xboxservices.com"
test_domain "catalog.gamepass.com"

echo ""
echo "Testing Microsoft domains:"
echo "---"
test_domain "login.live.com"
test_domain "dns.msftncsi.com"

echo ""
echo "Testing Discord domains:"
echo "---"
test_domain "discord.com"
test_domain "gateway.discord.gg"
test_domain "cdn.discordapp.com"

echo ""
echo "Testing non-Xbox/Discord domain (should return real IP):"
echo "---"
test_domain "google.com"

echo ""
echo "================================================"
echo "HAProxy Status"
echo "================================================"
echo ""
echo "Check HAProxy stats: http://$VPS_IP:8404/stats"
echo ""
echo "HAProxy status:"
systemctl status haproxy --no-pager -l | head -10

echo ""
echo "================================================"
echo "Testing from VPS directly:"
echo "================================================"
curl -s -H 'accept: application/dns-json' 'http://localhost/dns-query?name=xboxlive.com&type=A' | jq '.' 2>/dev/null || curl -s -H 'accept: application/dns-json' 'http://localhost/dns-query?name=xboxlive.com&type=A'

echo ""
echo "================================================"


#!/bin/bash

# Diagnose Xbox connectivity issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Xbox Connectivity Diagnostics"
echo "================================================"
echo ""

cd /root/doh

echo -e "${YELLOW}[1/6] Checking CoreDNS logs for Xbox queries...${NC}"
echo "Recent DNS queries (last 50 lines):"
docker logs coredns-smartdns --tail 50 2>&1 | grep -i xbox || echo "No Xbox queries found in recent logs"
echo ""

echo -e "${YELLOW}[2/6] Checking DoH backend logs...${NC}"
echo "Recent DoH queries:"
docker logs doh-backend --tail 50 2>&1 | grep -i xbox || echo "No Xbox queries found"
echo ""

echo -e "${YELLOW}[3/6] Testing if sniproxy can reach Xbox servers...${NC}"
echo "Testing connection to xboxlive.com:443..."
timeout 5 curl -v --resolve xboxlive.com:443:20.76.201.171 https://xboxlive.com 2>&1 | head -20 || echo "Connection test failed"
echo ""

echo -e "${YELLOW}[4/6] Checking sniproxy configuration...${NC}"
echo "Current sniproxy table entries:"
grep -E "table|\.xbox|\.discord" /etc/sniproxy.conf | head -20
echo ""

echo -e "${YELLOW}[5/6] Testing Smart DNS resolution...${NC}"
echo "Testing xboxlive.com (should return VPS IP):"
curl -s -H 'accept: application/dns-json' 'http://localhost:8053/dns-query?name=xboxlive.com&type=A' | grep -o '"data":"[^"]*"' || echo "Query failed"
echo ""

echo -e "${YELLOW}[6/6] Checking if Xbox domains are in hosts file...${NC}"
echo "Xbox domains in xbox-hosts:"
grep -c "xboxlive.com\|xboxservices.com\|xbox.com" coredns/xbox-hosts || echo "0 domains found"
echo "Total entries:"
wc -l coredns/xbox-hosts
echo ""

echo "================================================"
echo "Next Steps:"
echo "1. Check if Xbox is actually using Keenetic's DNS"
echo "2. Monitor logs while Xbox tries to connect:"
echo "   docker logs -f coredns-smartdns"
echo "   tail -f /var/log/sniproxy/https_access.log"
echo "3. Test Xbox connection from VPS:"
echo "   curl -v --resolve xboxlive.com:443:91.235.234.92 https://xboxlive.com"
echo "================================================"


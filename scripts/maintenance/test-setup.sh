#!/bin/bash

# Test the complete DoH + Smart DNS setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Testing DoH + Smart DNS Setup"
echo "================================================"
echo ""

cd /root/doh

VPS_IP=$(curl -4 -s ifconfig.me)

# Test 1: Check containers
echo -e "${YELLOW}[1/5] Checking Docker containers...${NC}"
docker-compose ps
echo ""

# Test 2: Check SNIProxy
echo -e "${YELLOW}[2/5] Checking SNIProxy...${NC}"
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
else
    echo -e "${RED}❌ SNIProxy not listening on port 443${NC}"
fi
echo ""

# Test 3: Test DoH server
echo -e "${YELLOW}[3/5] Testing DoH server...${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' "https://bypass.440.info/dns-query?name=google.com&type=A" 2>&1)
if echo "$RESULT" | grep -q '"Status":0'; then
    echo -e "${GREEN}✅ DoH server responding${NC}"
    echo "$RESULT" | grep -o '"data":"[^"]*"' | head -1
else
    echo -e "${RED}❌ DoH server not responding${NC}"
    echo "$RESULT"
fi
echo ""

# Test 4: Test Smart DNS (Xbox domain should return VPS IP)
echo -e "${YELLOW}[4/5] Testing Smart DNS (xboxlive.com should return VPS IP)...${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' "https://bypass.440.info/dns-query?name=xboxlive.com&type=A" 2>&1)
if echo "$RESULT" | grep -q "$VPS_IP"; then
    echo -e "${GREEN}✅ Smart DNS working - xboxlive.com returns VPS IP${NC}"
    echo "$RESULT" | grep -o '"data":"[^"]*"'
else
    echo -e "${RED}❌ Smart DNS not working - xboxlive.com should return $VPS_IP${NC}"
    echo "$RESULT"
fi
echo ""

# Test 5: Test regular domain (should return real IP)
echo -e "${YELLOW}[5/5] Testing regular domain (google.com should return real IP)...${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' "https://bypass.440.info/dns-query?name=google.com&type=A" 2>&1)
if echo "$RESULT" | grep -q '"data":"142.251\|"data":"216.58\|"data":"172.217"'; then
    echo -e "${GREEN}✅ Regular DNS working - google.com returns real IP${NC}"
    echo "$RESULT" | grep -o '"data":"[^"]*"' | head -1
else
    echo -e "${YELLOW}⚠ Check: google.com should return real Google IP${NC}"
    echo "$RESULT" | grep -o '"data":"[^"]*"' | head -1
fi
echo ""

echo "================================================"
echo "Test Summary"
echo "================================================"
echo ""
echo "If all tests passed:"
echo "  1. Configure Keenetic router with DoH: https://bypass.440.info/dns-query"
echo "  2. Test Xbox network connection"
echo "  3. If Xbox still has issues, add more domains from Wireshark analysis"
echo ""
echo "================================================"


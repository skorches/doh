#!/bin/bash

# Test Smart DNS from your PC (run this on your local machine)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Testing Smart DNS Setup"
echo "================================================"
echo ""

echo -e "${YELLOW}Test 1: Xbox domain should return VPS IP${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A')
echo "$RESULT"
if echo "$RESULT" | grep -q "91.235.234.92"; then
    echo -e "${GREEN}✅ PASS: xboxlive.com returns VPS IP${NC}"
else
    echo -e "${RED}❌ FAIL: xboxlive.com should return 91.235.234.92${NC}"
fi
echo ""

echo -e "${YELLOW}Test 2: Discord domain should return VPS IP${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=discord.com&type=A')
echo "$RESULT"
if echo "$RESULT" | grep -q "91.235.234.92"; then
    echo -e "${GREEN}✅ PASS: discord.com returns VPS IP${NC}"
else
    echo -e "${RED}❌ FAIL: discord.com should return 91.235.234.92${NC}"
fi
echo ""

echo -e "${YELLOW}Test 3: Regular domain should return real IP${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A')
echo "$RESULT"
if echo "$RESULT" | grep -q "142.251"; then
    echo -e "${GREEN}✅ PASS: google.com returns real IP${NC}"
else
    echo -e "${YELLOW}⚠ Check: google.com should return real Google IP (142.251.x.x)${NC}"
fi
echo ""

echo "================================================"
echo "Summary:"
echo "  - Xbox/Discord domains should resolve to your VPS"
echo "  - Regular domains should resolve to real IPs"
echo "  - If tests pass, configure Xbox to use Keenetic DoH"
echo "================================================"


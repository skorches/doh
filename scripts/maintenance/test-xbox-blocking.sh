#!/bin/bash

# Test if Xbox Live is blocking the VPS IP

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
echo "Testing Xbox Live Server Responses"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Test 1: Direct connection from VPS
echo -e "${YELLOW}[1/4] Testing direct connection from VPS...${NC}"
DIRECT_RESULT=$(timeout 10 curl -s -I https://xboxlive.com 2>&1 | head -5 || echo "TIMEOUT")
if echo "$DIRECT_RESULT" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ VPS can reach Xbox servers directly${NC}"
elif echo "$DIRECT_RESULT" | grep -q "TIMEOUT"; then
    echo -e "${RED}❌ VPS cannot reach Xbox servers (timeout)${NC}"
else
    echo -e "${YELLOW}⚠ VPS connection result:${NC}"
    echo "$DIRECT_RESULT" | head -3
fi

# Test 2: Through SNIProxy (simulating Xbox)
echo ""
echo -e "${YELLOW}[2/4] Testing through SNIProxy (Xbox path)...${NC}"
SNI_RESULT=$(timeout 10 curl -k -s -I --resolve xboxlive.com:443:$VPS_IP https://xboxlive.com 2>&1 | head -5 || echo "TIMEOUT")
if echo "$SNI_RESULT" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ SNIProxy can forward to Xbox servers${NC}"
elif echo "$SNI_RESULT" | grep -q "TIMEOUT"; then
    echo -e "${RED}❌ SNIProxy forwarding timeout${NC}"
else
    echo -e "${YELLOW}⚠ SNIProxy result:${NC}"
    echo "$SNI_RESULT" | head -3
fi

# Test 3: Check Xbox authentication endpoint
echo ""
echo -e "${YELLOW}[3/4] Testing Xbox authentication endpoint...${NC}"
AUTH_RESULT=$(timeout 10 curl -s -I https://auth.xboxlive.com 2>&1 | head -5 || echo "TIMEOUT")
if echo "$AUTH_RESULT" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ Auth endpoint reachable${NC}"
elif echo "$AUTH_RESULT" | grep -q "TIMEOUT"; then
    echo -e "${RED}❌ Auth endpoint timeout${NC}"
else
    echo -e "${YELLOW}⚠ Auth endpoint result:${NC}"
    echo "$AUTH_RESULT" | head -3
fi

# Test 4: Check recent SNIProxy logs for errors
echo ""
echo -e "${YELLOW}[4/4] Checking SNIProxy logs for errors...${NC}"
if [ -f /var/log/sniproxy/https_access.log ]; then
    RECENT_ERRORS=$(tail -50 /var/log/sniproxy/https_access.log | grep -iE "error|failed|timeout|refused" || echo "")
    if [ -n "$RECENT_ERRORS" ]; then
        echo -e "${YELLOW}⚠ Found errors in SNIProxy logs:${NC}"
        echo "$RECENT_ERRORS" | head -5
    else
        echo -e "${GREEN}✅ No errors in recent SNIProxy logs${NC}"
    fi
    
    # Show connection durations
    echo ""
    echo -e "${BLUE}Recent connection durations:${NC}"
    tail -20 /var/log/sniproxy/https_access.log | grep -oE "[0-9]+\.[0-9]+ seconds" | tail -5 || echo "No duration data"
else
    echo -e "${YELLOW}⚠ SNIProxy log file not found${NC}"
fi

echo ""
echo "================================================"
echo "Analysis"
echo "================================================"
echo ""
echo "If all tests show timeouts or connection refused:"
echo "  → Xbox Live might be blocking Russian VPS IPs"
echo ""
echo "If direct connection works but SNIProxy doesn't:"
echo "  → SNIProxy configuration issue"
echo ""
echo "If connections work but Xbox still shows error:"
echo "  → Xbox Live might be detecting proxy"
echo "  → Or blocking based on source IP"
echo ""
echo "Error 0x80a40401 with working connections suggests:"
echo "  → Xbox Live is rejecting connections from VPS IP"
echo "  → Possibly geo-blocking or proxy detection"
echo ""


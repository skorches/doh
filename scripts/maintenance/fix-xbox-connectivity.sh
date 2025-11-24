#!/bin/bash

# Fix Xbox connectivity - handle Xbox Live ports and check firewall

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
echo "Fixing Xbox Connectivity Issues"
echo "================================================"
echo ""

cd /root/doh

VPS_IP=$(curl -4 -s ifconfig.me)

# Step 1: Check firewall
echo -e "${YELLOW}[1/4] Checking firewall...${NC}"
ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
ufw allow 443/tcp comment "HTTPS/Xbox" 2>/dev/null || true
ufw allow 3074/tcp comment "Xbox Live TCP" 2>/dev/null || true
ufw allow 3074/udp comment "Xbox Live UDP" 2>/dev/null || true
ufw allow 3544/udp comment "Xbox Teredo" 2>/dev/null || true
echo -e "${GREEN}✅ Firewall ports opened${NC}"

# Step 2: Check if Xbox is actually resolving to VPS IP
echo ""
echo -e "${YELLOW}[2/4] Testing DNS resolution...${NC}"
RESULT=$(curl -s -H 'accept: application/dns-json' "http://localhost:8053/dns-query?name=xboxlive.com&type=A" 2>&1)
if echo "$RESULT" | grep -q "$VPS_IP"; then
    echo -e "${GREEN}✅ xboxlive.com resolves to VPS IP${NC}"
else
    echo -e "${RED}❌ xboxlive.com does NOT resolve to VPS IP${NC}"
    echo "$RESULT"
fi

# Step 3: Check if VPS can reach Xbox servers
echo ""
echo -e "${YELLOW}[3/4] Testing connectivity to Xbox servers...${NC}"
if timeout 5 curl -s -I https://xboxlive.com > /dev/null 2>&1; then
    echo -e "${GREEN}✅ VPS can reach Xbox servers${NC}"
else
    echo -e "${YELLOW}⚠ VPS cannot reach Xbox servers (might be blocked)${NC}"
fi

# Step 4: Check SNIProxy status
echo ""
echo -e "${YELLOW}[4/6] Checking SNIProxy status...${NC}"

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
    echo ""
    echo -e "${YELLOW}Checking SNIProxy logs...${NC}"
    journalctl -u sniproxy -n 10 --no-pager
    echo ""
    echo -e "${YELLOW}Attempting to start SNIProxy...${NC}"
    systemctl start sniproxy
    sleep 2
    
    if systemctl is-active --quiet sniproxy; then
        echo -e "${GREEN}✅ SNIProxy started successfully${NC}"
    else
        echo -e "${RED}❌ SNIProxy failed to start${NC}"
        echo "Check config: cat /etc/sniproxy.conf"
    fi
fi

# Step 5: Check if port 443 is in use
echo ""
echo -e "${YELLOW}[5/6] Checking port 443...${NC}"

PORT_443_USAGE=$(ss -tlnp | grep ":443" || echo "")
if [ -z "$PORT_443_USAGE" ]; then
    echo -e "${RED}❌ Nothing listening on port 443${NC}"
    echo "SNIProxy should be listening on port 443"
elif echo "$PORT_443_USAGE" | grep -q "sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy is listening on port 443${NC}"
else
    echo -e "${YELLOW}⚠ Port 443 is in use by something else:${NC}"
    echo "$PORT_443_USAGE"
    echo ""
    echo "This might prevent SNIProxy from starting"
fi

# Step 6: Test SNIProxy forwarding
echo ""
echo -e "${YELLOW}[6/6] Testing SNIProxy forwarding...${NC}"

if systemctl is-active --quiet sniproxy; then
    if timeout 5 curl -k -v --resolve xboxlive.com:443:$VPS_IP https://xboxlive.com 2>&1 | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ SNIProxy can forward Xbox traffic${NC}"
    else
        echo -e "${YELLOW}⚠ SNIProxy forwarding test inconclusive${NC}"
    fi
else
    echo -e "${RED}❌ Cannot test - SNIProxy is not running${NC}"
fi

echo ""
echo "================================================"
echo "Diagnosis"
echo "================================================"
echo ""
echo "If Xbox shows 'NAT unavailable' and no connections appear in logs:"
echo ""
echo "Possible causes:"
echo "  1. ISP is blocking your VPS IP for Xbox traffic"
echo "  2. Xbox needs port 3074 (UDP/TCP) - check router port forwarding"
echo "  3. Xbox is using cached DNS (restart Xbox)"
echo "  4. Router firewall blocking Xbox → VPS"
echo ""
echo "Solutions to try:"
echo ""
echo "1. Restart Xbox (unplug for 30 seconds)"
echo ""
echo "2. Check router port forwarding:"
echo "   - Forward port 3074 (UDP/TCP) to Xbox IP"
echo "   - Forward port 3544 (UDP) to Xbox IP"
echo ""
echo "3. Test from PC if Xbox can reach VPS:"
echo "   curl -v --resolve xboxlive.com:443:$VPS_IP https://xboxlive.com"
echo ""
echo "4. If ISP is blocking VPS IP, consider:"
echo "   - Using Cloudflare proxy (already enabled)"
echo "   - Getting a Russian VPS (lower latency, less blocking)"
echo ""
echo "================================================"


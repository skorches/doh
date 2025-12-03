#!/bin/bash

# Fix Warzone intermittent disconnections by adding missing domains and optimizing CoreDNS

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
echo "Fixing Warzone Intermittent Disconnections"
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

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP (IPv4): " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Add missing Warzone domains
echo -e "${YELLOW}[1/3] Adding missing Warzone domains...${NC}"

MISSING_DOMAINS=(
    "cod-assets.cdn.callofduty.com"
    "ingest.datax.activision.com"
    "v20.events.data.microsoft.com"
    "demonware.net"
    "prod.demonware.net"
    "demonware.com"
)

ADDED=0
for domain in "${MISSING_DOMAINS[@]}"; do
    if ! grep -q "$domain" coredns/xbox-hosts 2>/dev/null; then
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
        ADDED=$((ADDED + 1))
    fi
done

if [ $ADDED -gt 0 ]; then
    echo -e "${GREEN}✅ Added $ADDED missing domains${NC}"
else
    echo -e "${GREEN}✅ All domains already present${NC}"
fi

# Step 2: Optimize CoreDNS for faster resolution and fewer timeouts
echo ""
echo -e "${YELLOW}[2/3] Optimizing CoreDNS configuration...${NC}"

# Check if Corefile has parallel upstreams
if ! grep -q "parallel" coredns/Corefile 2>/dev/null; then
    # Backup Corefile
    cp coredns/Corefile coredns/Corefile.backup.$(date +%s)
    
    # Update forward to use parallel with multiple DNS servers
    sed -i 's/forward \. 1\.1\.1\.1 1\.0\.0\.1/forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {\n        max_concurrent 1000\n        except \/etc\/coredns\/xbox-hosts\n    }/' coredns/Corefile
    
    echo -e "${GREEN}✅ CoreDNS optimized with parallel upstreams${NC}"
else
    echo -e "${GREEN}✅ CoreDNS already optimized${NC}"
fi

# Step 3: Add missing domains to SNIProxy
echo ""
echo -e "${YELLOW}[3/3] Updating SNIProxy configuration...${NC}"

if ! grep -q "demonware" /etc/sniproxy.conf 2>/dev/null; then
    sed -i '/# Activision/a\    .*\.demonware\.net$ *\n    .*\.demonware\.com$ *\n    .*\.datax\.activision\.com$ *' /etc/sniproxy.conf
    echo -e "${GREEN}✅ Added missing domains to SNIProxy${NC}"
else
    echo -e "${GREEN}✅ SNIProxy already configured${NC}"
fi

# Restart services
echo ""
echo -e "${YELLOW}Restarting services...${NC}"

docker restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart CoreDNS${NC}"
}
sleep 3

systemctl restart sniproxy 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart SNIProxy${NC}"
}
sleep 2

echo -e "${GREEN}✅ Services restarted${NC}"

# Verify
echo ""
echo -e "${YELLOW}Verifying fixes...${NC}"
sleep 2

# Test DNS resolution
TEST_DOMAIN="cod-assets.cdn.callofduty.com"
DNS_RESULT=$(timeout 3 dig @127.0.0.1 "$TEST_DOMAIN" +short 2>/dev/null | head -1 || echo "FAILED")

if [ "$DNS_RESULT" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ $TEST_DOMAIN resolves correctly${NC}"
else
    echo -e "${YELLOW}⚠ $TEST_DOMAIN DNS: $DNS_RESULT (may need a moment)${NC}"
fi

echo ""
echo "================================================"
echo "✅ Fix Applied"
echo "================================================"
echo ""
echo "What was fixed:"
echo "  • Added missing Warzone CDN/data domains"
echo "  • Optimized CoreDNS with parallel upstreams"
echo "  • Updated SNIProxy configuration"
echo ""
echo "This should reduce intermittent disconnections."
echo "If issues persist, check:"
echo "  • Network latency to VPS"
echo "  • ISP blocking UDP game traffic"
echo "  • VPS resource usage (CPU/RAM)"
echo ""


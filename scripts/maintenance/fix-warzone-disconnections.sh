#!/bin/bash

# Fix Warzone disconnections by adding missing domains

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
echo "Fixing Warzone Disconnections"
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

# Step 1: Add demonware.net to hosts file
echo -e "${YELLOW}[1/3] Adding Warzone game server domains...${NC}"

if ! grep -q "demonware.net" coredns/xbox-hosts 2>/dev/null; then
    echo "" >> coredns/xbox-hosts
    echo "# Warzone game servers (Demonware)" >> coredns/xbox-hosts
    echo "$VPS_IP demonware.net" >> coredns/xbox-hosts
    echo "$VPS_IP prod.demonware.net" >> coredns/xbox-hosts
    echo "$VPS_IP demonware.com" >> coredns/xbox-hosts
    echo -e "${GREEN}✅ Added demonware.net domains${NC}"
else
    echo -e "${GREEN}✅ demonware.net domains already present${NC}"
fi

# Step 2: Add demonware to SNIProxy config
echo ""
echo -e "${YELLOW}[2/3] Updating SNIProxy configuration...${NC}"

if ! grep -q "demonware" /etc/sniproxy.conf 2>/dev/null; then
    # Add demonware rules before the catch-all
    sed -i '/# Activision/a\    .*\.demonware\.net$ *\n    .*\.demonware\.com$ *' /etc/sniproxy.conf
    echo -e "${GREEN}✅ Added demonware to SNIProxy${NC}"
else
    echo -e "${GREEN}✅ demonware already in SNIProxy config${NC}"
fi

# Step 3: Restart services
echo ""
echo -e "${YELLOW}[3/3] Restarting services...${NC}"

# Restart CoreDNS
docker restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart CoreDNS${NC}"
}
sleep 3

# Restart SNIProxy
systemctl restart sniproxy 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart SNIProxy${NC}"
}
sleep 2

echo -e "${GREEN}✅ Services restarted${NC}"

# Verify
echo ""
echo -e "${YELLOW}Verifying DNS resolution...${NC}"
sleep 2

DEMONWARE_DNS=$(timeout 3 dig @127.0.0.1 demonware.net +short 2>/dev/null | head -1 || echo "FAILED")
if [ "$DEMONWARE_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ demonware.net resolves to VPS IP${NC}"
else
    echo -e "${YELLOW}⚠ demonware.net DNS: $DEMONWARE_DNS (expected: $VPS_IP)${NC}"
    echo "   CoreDNS may need a moment to update"
fi

echo ""
echo "================================================"
echo "Important Notes"
echo "================================================"
echo ""
echo -e "${YELLOW}⚠️  SNIProxy Limitation:${NC}"
echo "   SNIProxy only handles HTTPS/TLS traffic."
echo "   Warzone game traffic uses UDP, which SNIProxy"
echo "   cannot proxy. This means:"
echo ""
echo "   ✅ Authentication/Profile data → Works (HTTPS)"
echo "   ✅ Matchmaking requests → Works (HTTPS)"
echo "   ❌ Actual game traffic (UDP) → Goes directly"
echo ""
echo "If disconnections continue, it might be because:"
echo "   1. Your ISP is blocking UDP game traffic"
echo "   2. Game servers are blocking your VPS IP"
echo "   3. Network latency is too high"
echo ""
echo "Solutions:"
echo "   • Use a VPN on your router (routes all traffic)"
echo "   • Check if your ISP blocks gaming traffic"
echo "   • Try a different VPS location"
echo ""
echo "================================================"


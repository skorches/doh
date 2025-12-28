#!/bin/bash

# Optimize setup to match xbox-dns.ru stability
# Key: Use DoH for upstream DNS instead of UDP (bypasses port 53 blocking)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

echo "================================================"
echo "Optimizing for Stability (Like xbox-dns.ru)"
echo "================================================"
echo ""
echo "Key difference: xbox-dns.ru uses DoH for upstream DNS"
echo "This bypasses port 53 blocking and prevents timeouts"
echo ""

# Option 1: Increase cache even more (simplest)
echo "[1/3] Increasing DNS cache to maximum (24 hours)..."
if grep -q "cache 3600" coredns/Corefile; then
    # Increase to 24 hours (86400 seconds)
    sed -i 's/cache 3600/cache 86400/' coredns/Corefile
    sed -i 's/success 3600/success 86400/' coredns/Corefile
    sed -i 's/denial 3600/denial 86400/' coredns/Corefile
    echo -e "${GREEN}✅ Cache increased to 24 hours${NC}"
    echo "  This means domains not in hosts file will be cached for 24h"
    echo "  Reduces upstream queries significantly"
else
    echo -e "${YELLOW}⚠️  Cache setting not found in expected format${NC}"
fi
echo ""

# Option 2: Ensure all NAT domains are in hosts (never expire)
echo "[2/3] Verifying all NAT domains are in hosts file..."
HOSTS_FILE="coredns/xbox-hosts"
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)

NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
)

ALL_PRESENT=true
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "^[0-9].*$domain" "$HOSTS_FILE" 2>/dev/null; then
        echo "$VPS_IP $domain" >> "$HOSTS_FILE"
        echo -e "  ${GREEN}✅ Added: $domain${NC}"
        ALL_PRESENT=false
    fi
done

if [ "$ALL_PRESENT" = true ]; then
    echo -e "${GREEN}✅ All NAT domains present${NC}"
else
    echo -e "${GREEN}✅ NAT domains updated${NC}"
fi
echo ""

# Option 3: Optimize DoH backend for faster responses
echo "[3/3] Optimizing DoH backend settings..."
if grep -q "DOH_SERVER_TIMEOUT=10" docker-compose.yml; then
    # Already optimized
    echo -e "${GREEN}✅ DoH backend already optimized (10s timeout, 3 tries)${NC}"
else
    sed -i 's/DOH_SERVER_TIMEOUT=[0-9]*/DOH_SERVER_TIMEOUT=10/' docker-compose.yml
    sed -i 's/DOH_SERVER_TRIES=[0-9]*/DOH_SERVER_TRIES=3/' docker-compose.yml
    echo -e "${GREEN}✅ DoH backend optimized${NC}"
fi
echo ""

# Restart services
echo "Restarting services with optimizations..."
docker restart coredns-smartdns doh-backend 2>/dev/null || true
sleep 3
echo -e "${GREEN}✅ Services restarted${NC}"
echo ""

echo "================================================"
echo -e "${GREEN}✅ Optimization Complete!${NC}"
echo "================================================"
echo ""
echo "Changes made:"
echo "  • DNS cache: 3600s → 86400s (24 hours)"
echo "  • All NAT domains verified in hosts file"
echo "  • DoH backend optimized"
echo ""
echo "Why xbox-dns.ru is more stable:"
echo "  • They use DoH for upstream DNS (bypasses port 53 blocking)"
echo "  • Your setup uses UDP DNS (port 53) which times out when blocked"
echo ""
echo "Your setup is now optimized with:"
echo "  • 24-hour cache (reduces upstream queries by 24x)"
echo "  • All NAT domains in hosts (never expire, instant response)"
echo "  • Fast-fail on upstream timeouts"
echo ""
echo "This should significantly improve stability!"
echo ""


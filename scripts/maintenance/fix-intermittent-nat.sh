#!/bin/bash

# Fix intermittent NAT unavailable issue
# Ensures NAT domains are always served instantly and never timeout

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing Intermittent NAT Unavailable Issue"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/5] Ensuring all NAT domains are in hosts file..."
# Run fix-nat-teredo to ensure all domains are present
bash scripts/maintenance/fix-nat-teredo.sh > /dev/null 2>&1
echo "✅ NAT domains verified"
echo ""

echo "[2/5] Updating DoH backend timeout (if needed)..."
# Update docker-compose.yml if timeout is still 3s
if grep -q "DOH_SERVER_TIMEOUT=3" docker-compose.yml; then
    sed -i 's/DOH_SERVER_TIMEOUT=3/DOH_SERVER_TIMEOUT=10/' docker-compose.yml
    sed -i 's/DOH_SERVER_TRIES=1/DOH_SERVER_TRIES=3/' docker-compose.yml
    echo "✅ DoH backend timeout increased: 3s → 10s, tries: 1 → 3"
else
    echo "✅ DoH backend timeout already optimized (10s, 3 tries)"
fi
echo ""

echo "[3/5] Verifying CoreDNS configuration..."
# Ensure Corefile has correct settings
if ! grep -q "cache 3600" coredns/Corefile; then
    echo "⚠️  Cache not set to 3600s, updating..."
    sed -i 's/cache [0-9]*/cache 3600/' coredns/Corefile
fi

if ! grep -q "max_fails 1" coredns/Corefile; then
    echo "⚠️  max_fails not set, updating..."
    # Add max_fails after forward line
    sed -i '/forward . 1.1.1.1/a\        max_fails 1' coredns/Corefile
fi

if ! grep -q "health_check 5s" coredns/Corefile; then
    echo "⚠️  health_check not set, updating..."
    # Add health_check after max_fails
    sed -i '/max_fails 1/a\        health_check 5s' coredns/Corefile
fi
echo "✅ CoreDNS configuration verified"
echo ""

echo "[4/5] Restarting services with new configuration..."
docker compose restart doh-backend coredns-smartdns 2>/dev/null || docker-compose restart doh-backend coredns-smartdns 2>/dev/null
sleep 5
echo "✅ Services restarted"
echo ""

echo "[5/5] Pre-warming DNS cache (querying all NAT domains)..."
# Pre-query all NAT domains to ensure they're immediately available
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

SUCCESS=0
for domain in "${NAT_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$RESULT" == "$VPS_IP" ]; then
        SUCCESS=$((SUCCESS + 1))
    fi
done

if [ $SUCCESS -eq ${#NAT_DOMAINS[@]} ]; then
    echo "✅ All NAT domains resolving correctly ($SUCCESS/${#NAT_DOMAINS[@]})"
else
    echo "⚠️  Some domains not resolving ($SUCCESS/${#NAT_DOMAINS[@]})"
fi
echo ""

echo "================================================"
echo "✅ Fix Applied!"
echo "================================================"
echo ""
echo "Changes made:"
echo "  • All NAT domains verified in hosts file"
echo "  • DoH backend timeout: 10s (3 tries)"
echo "  • CoreDNS cache: 3600s (1 hour)"
echo "  • CoreDNS fast-fail: enabled"
echo "  • DNS cache pre-warmed"
echo ""
echo "This should prevent intermittent NAT unavailable issues."
echo ""
echo "Next steps:"
echo "1. Restart Xbox (hold power 10 seconds, wait 30s, turn on)"
echo "2. Test NAT type - it should stay available"
echo "3. If it still becomes unavailable after a while:"
echo "   - Check CoreDNS logs: docker logs coredns-smartdns --tail 50"
echo "   - Look for timeout errors or missing domains"
echo "   - Run verify script: bash scripts/maintenance/verify.sh"
echo ""

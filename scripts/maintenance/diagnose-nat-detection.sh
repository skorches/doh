#!/bin/bash

# Diagnose why NAT type is unavailable despite no timeout errors

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Diagnosing NAT Detection Issue"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/6] Checking all NAT domains resolve correctly..."
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
    "msftncsi.com"
    "msftconnecttest.com"
)

ALL_CORRECT=1
for domain in "${NAT_DOMAINS[@]}"; do
    # Test via DoH
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo "  ✅ $domain → $RESULT"
    else
        echo "  ❌ $domain → $RESULT (expected $VPS_IP)"
        ALL_CORRECT=0
    fi
done
echo ""

echo "[2/6] Checking if Teredo resolves to real servers..."
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$TEREDO_RESULT" ] && [ "$TEREDO_RESULT" != "$VPS_IP" ]; then
    echo "  ✅ teredo.ipv6.microsoft.com → $TEREDO_RESULT (real server - correct)"
else
    echo "  ❌ teredo.ipv6.microsoft.com → $TEREDO_RESULT (should NOT be $VPS_IP)"
    ALL_CORRECT=0
fi
echo ""

echo "[3/6] Checking CoreDNS logs for recent queries..."
echo "Last 100 lines of CoreDNS logs:"
docker logs coredns-smartdns --tail 100 2>&1 | tail -20
echo ""

echo "[4/6] Checking for any Xbox-related queries in logs..."
XBOX_QUERIES=$(docker logs coredns-smartdns --tail 500 2>&1 | grep -iE "xbox|msft|microsoft|teredo" | tail -20)
if [ -n "$XBOX_QUERIES" ]; then
    echo "Recent Xbox-related queries:"
    echo "$XBOX_QUERIES"
else
    echo "  ⚠️  No Xbox-related queries found in recent logs"
    echo "  This might mean Xbox isn't querying DNS, or queries are being cached"
fi
echo ""

echo "[5/6] Testing DNS resolution directly (bypassing DoH)..."
echo "Testing via direct DNS (port 53):"
for domain in "xbox.nat.microsoft.com" "dns.msftncsi.com"; do
    echo -n "  $domain: "
    RESULT=$(timeout 2 dig @127.0.0.1 $domain +short 2>/dev/null | head -1)
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo "✅ $RESULT"
    else
        echo "❌ $RESULT (expected $VPS_IP)"
        ALL_CORRECT=0
    fi
done
echo ""

echo "[6/6] Checking if Xbox DNS is configured correctly..."
echo "Xbox should be using your VPS as DNS server:"
echo "  Primary DNS: $VPS_IP"
echo "  Secondary DNS: 8.8.8.8 (or leave empty)"
echo ""
echo "To check on Xbox:"
echo "  Settings → Network → Network settings"
echo "  Advanced settings → DNS settings"
echo "  Should be set to: Manual"
echo "  Primary DNS: $VPS_IP"
echo ""

echo "================================================"
if [ $ALL_CORRECT -eq 1 ]; then
    echo "✅ DNS Resolution: All Correct"
    echo ""
    echo "If NAT is still unavailable, the issue is likely:"
    echo "  1. Xbox DNS not set to VPS IP ($VPS_IP)"
    echo "  2. Router blocking Xbox traffic"
    echo "  3. Double NAT (router behind another router)"
    echo "  4. UPnP disabled on router"
    echo "  5. Port 3074 not forwarded to Xbox"
    echo ""
    echo "DNS is working correctly - this is a network/router issue."
else
    echo "⚠️  DNS Resolution Issues Found"
    echo ""
    echo "Some NAT domains are not resolving correctly."
    echo "Run: bash scripts/maintenance/fix-nat-teredo.sh"
fi
echo "================================================"
echo ""


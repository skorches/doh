#!/bin/bash

# Diagnose why Xbox isn't using DoH

echo "================================================"
echo "Diagnosing Keenetic DoH Connection"
echo "================================================"
echo ""

cd /root/doh

echo "=== Test 1: Is DoH server accessible? ==="
RESULT=$(curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A' 2>&1)
if echo "$RESULT" | grep -q '"Status":0'; then
    echo "✅ DoH server is responding"
else
    echo "❌ DoH server not responding"
    echo "$RESULT"
fi
echo ""

echo "=== Test 2: Check recent DoH queries ==="
echo "Last 20 DoH queries:"
docker logs doh-backend --tail 20 2>&1 | grep -E "POST|GET" | tail -10
echo ""

echo "=== Test 3: Check CoreDNS queries ==="
echo "Last 20 CoreDNS queries:"
docker logs coredns-smartdns --tail 20 2>&1 | grep -v "maxprocs\|CoreDNS\|SIGTERM" | tail -10
echo ""

echo "================================================"
echo "Diagnosis:"
echo ""
echo "If you see NO queries above, Xbox/Keenetic is NOT using your DoH server."
echo ""
echo "Possible causes:"
echo "  1. Keenetic DoH not enabled or misconfigured"
echo "  2. Xbox not using Keenetic's DNS (check Xbox DNS settings)"
echo "  3. Keenetic's DNS proxy service not running"
echo ""
echo "Solutions:"
echo "  1. On Keenetic: Internet → DNS → Enable 'Use DNS over HTTPS'"
echo "     URL: https://bypass.440.info/dns-query"
echo ""
echo "  2. On Xbox: Settings → Network → Advanced → DNS Settings"
echo "     Set to 'Automatic' (uses router DNS)"
echo ""
echo "  3. Restart Keenetic router"
echo ""
echo "  4. Test from a PC on the same network:"
echo "     nslookup google.com 192.168.1.1"
echo "     (Should use Keenetic's DNS)"
echo ""
echo "================================================"


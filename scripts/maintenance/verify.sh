#!/bin/bash

# Comprehensive verification script - checks everything

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "DoH Setup Verification"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "Current VPS IP: $VPS_IP"
echo ""

# Critical NAT domains
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

echo "=== [1/5] Checking NAT Domains in Hosts File ==="
MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        RESOLVED_IP=$(grep "^[0-9].*$domain" coredns/xbox-hosts | head -1 | awk '{print $1}')
        if [ "$RESOLVED_IP" == "$VPS_IP" ]; then
            echo "  ✅ $domain → $RESOLVED_IP"
        else
            echo "  ⚠️  $domain → $RESOLVED_IP (should be $VPS_IP)"
            MISSING=1
        fi
    else
        echo "  ❌ $domain MISSING"
        MISSING=1
    fi
done
echo ""

echo "=== [2/5] Checking Teredo ==="
if grep -q "^[0-9].*teredo\.ipv6\.microsoft\.com" coredns/xbox-hosts; then
    echo "  ❌ teredo.ipv6.microsoft.com should NOT be in hosts file"
    MISSING=1
else
    echo "  ✅ Teredo correctly removed (resolves to real servers)"
fi
echo ""

echo "=== [3/5] Checking CoreDNS Configuration ==="
if grep -q "cache 3600" coredns/Corefile; then
    echo "  ✅ Cache: 3600s"
else
    echo "  ⚠️  Cache not set to 3600s"
fi

if grep -q "max_fails 1" coredns/Corefile; then
    echo "  ✅ max_fails: 1"
else
    echo "  ⚠️  max_fails not set"
fi

if grep -q "health_check 5s" coredns/Corefile; then
    echo "  ✅ health_check: 5s"
else
    echo "  ⚠️  health_check not set"
fi
echo ""

echo "=== [4/5] Checking Docker Containers ==="
if docker ps | grep -q coredns-smartdns; then
    echo "  ✅ CoreDNS: Running"
else
    echo "  ❌ CoreDNS: NOT running"
    MISSING=1
fi

if docker ps | grep -q doh-nginx; then
    echo "  ✅ Nginx: Running"
else
    echo "  ❌ Nginx: NOT running"
    MISSING=1
fi

if docker ps | grep -q doh-backend; then
    echo "  ✅ DoH Backend: Running"
else
    echo "  ❌ DoH Backend: NOT running"
    MISSING=1
fi
echo ""

echo "=== [5/5] Testing DNS Resolution ==="
echo -n "  xbox.nat.microsoft.com: "
NAT_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$NAT_RESULT" == "$VPS_IP" ]; then
    echo "✅ $NAT_RESULT"
else
    echo "⚠️  $NAT_RESULT (expected $VPS_IP)"
    MISSING=1
fi

echo -n "  teredo.ipv6.microsoft.com: "
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$TEREDO_RESULT" ] && [ "$TEREDO_RESULT" != "$VPS_IP" ]; then
    echo "✅ $TEREDO_RESULT (resolves to real server - correct)"
else
    echo "⚠️  $TEREDO_RESULT (should NOT be VPS IP)"
fi
echo ""

echo "================================================"
if [ $MISSING -eq 0 ]; then
    echo "✅ All Checks Passed!"
    echo ""
    echo "Your setup is configured correctly."
    echo "If NAT is still unavailable on Xbox:"
    echo "  1. Verify Xbox DNS is set to VPS IP: $VPS_IP"
    echo "  2. Restart Xbox (hold power 10 seconds)"
    echo "  3. Check router UPnP settings"
else
    echo "⚠️  Issues Found"
    echo ""
    echo "To fix:"
    echo "  bash scripts/maintenance/fix-nat-teredo.sh"
fi
echo "================================================"
echo ""


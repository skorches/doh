#!/bin/bash

# Comprehensive NAT/Teredo verification and fix

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "NAT/Teredo Verification & Fix"
echo "================================================"
echo ""

# Get current VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "Current VPS IP: $VPS_IP"
echo ""

# Required NAT domains
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

echo "=== Checking NAT Domains ==="
MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        RESOLVED_IP=$(grep "^[0-9].*$domain" coredns/xbox-hosts | awk '{print $1}')
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

# Check Teredo
echo "=== Checking Teredo ==="
if grep -q "^[0-9].*teredo\.ipv6\.microsoft\.com" coredns/xbox-hosts; then
    echo "  ❌ ERROR: Teredo is in hosts file (must be removed)"
    MISSING=1
else
    echo "  ✅ Teredo NOT in hosts file (will resolve to real servers)"
fi

# Test Teredo resolution
TEREDO_DNS=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$TEREDO_DNS" ] && [ "$TEREDO_DNS" != "$VPS_IP" ]; then
    echo "  ✅ Teredo resolves to: $TEREDO_DNS (real server - correct)"
else
    echo "  ⚠️  Teredo resolution issue: $TEREDO_DNS"
fi
echo ""

# Check CoreDNS cache
echo "=== Checking CoreDNS Configuration ==="
if grep -q "cache 3600" coredns/Corefile; then
    echo "  ✅ Cache: 3600s (1 hour)"
else
    echo "  ⚠️  Cache not set to 3600s"
    grep "cache" coredns/Corefile || echo "    No cache setting found"
fi

if grep -q "max_fails 1" coredns/Corefile; then
    echo "  ✅ max_fails: 1 (fast fail)"
else
    echo "  ⚠️  max_fails not set"
fi

if grep -q "health_check 5s" coredns/Corefile; then
    echo "  ✅ health_check: 5s"
else
    echo "  ⚠️  health_check not set"
fi
echo ""

# Check VPS IP in hosts file
echo "=== Checking VPS IP ==="
OLD_IP=$(grep -m1 "^[0-9]" coredns/xbox-hosts | head -1 | awk '{print $1}')
if [ "$OLD_IP" == "$VPS_IP" ]; then
    echo "  ✅ All IPs correct: $VPS_IP"
else
    echo "  ⚠️  Found old IP: $OLD_IP (should be $VPS_IP)"
    echo "  Run: bash scripts/maintenance/fix-nat-teredo.sh"
fi
echo ""

# Test DNS resolution
echo "=== Testing DNS Resolution ==="
echo -n "  xbox.nat.microsoft.com: "
NAT_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$NAT_RESULT" == "$VPS_IP" ]; then
    echo "✅ $NAT_RESULT"
else
    echo "⚠️  $NAT_RESULT (expected $VPS_IP)"
fi

echo -n "  dns.msftncsi.com: "
MSFT_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=dns.msftncsi.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$MSFT_RESULT" == "$VPS_IP" ]; then
    echo "✅ $MSFT_RESULT"
else
    echo "⚠️  $MSFT_RESULT (expected $VPS_IP)"
fi
echo ""

# Check CoreDNS container
echo "=== Checking CoreDNS Container ==="
if docker ps | grep -q coredns-smartdns; then
    echo "  ✅ CoreDNS is running"
    RESTART_TIME=$(docker inspect coredns-smartdns --format '{{.State.StartedAt}}' 2>/dev/null | cut -d'T' -f1)
    echo "  Started: $RESTART_TIME"
else
    echo "  ❌ CoreDNS is NOT running"
    echo "  Start it: docker compose up -d coredns-smartdns"
fi
echo ""

# Summary and recommendations
echo "================================================"
if [ $MISSING -eq 0 ]; then
    echo "✅ All Checks Passed!"
    echo "================================================"
    echo ""
    echo "Everything looks correct. If NAT is still unavailable:"
    echo ""
    echo "1. Verify Xbox DNS is set to VPS IP: $VPS_IP"
    echo "   Settings → Network → Advanced → DNS Settings"
    echo ""
    echo "2. Restart Xbox completely:"
    echo "   - Hold power button 10 seconds"
    echo "   - Wait 30 seconds"
    echo "   - Turn back on"
    echo ""
    echo "3. Check router settings:"
    echo "   - Enable UPnP"
    echo "   - Forward port 3074 (TCP/UDP) to Xbox"
    echo "   - Check for double NAT"
    echo ""
    echo "4. Teredo error is usually a network/router issue, not DNS:"
    echo "   - Teredo uses UDP port 3544"
    echo "   - Some routers block Teredo"
    echo "   - Teredo is NOT required if NAT type shows (Open/Moderate/Strict)"
else
    echo "⚠️  Issues Found"
    echo "================================================"
    echo ""
    echo "Run the fix script:"
    echo "  bash scripts/maintenance/fix-nat-teredo.sh"
    echo ""
fi


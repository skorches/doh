#!/bin/bash

# Verify all required domains are in hosts file and scripts

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Verifying All Required Domains"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "Current VPS IP: $VPS_IP"
echo ""

# Critical NAT domains (must be present)
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

echo "=== Checking Hosts File ==="
MISSING_IN_HOSTS=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        RESOLVED_IP=$(grep "^[0-9].*$domain" coredns/xbox-hosts | head -1 | awk '{print $1}')
        if [ "$RESOLVED_IP" == "$VPS_IP" ]; then
            echo "  ✅ $domain → $RESOLVED_IP"
        else
            echo "  ⚠️  $domain → $RESOLVED_IP (should be $VPS_IP)"
            MISSING_IN_HOSTS=1
        fi
    else
        echo "  ❌ $domain MISSING"
        MISSING_IN_HOSTS=1
    fi
done
echo ""

# Check if Teredo is incorrectly present
if grep -q "^[0-9].*teredo\.ipv6\.microsoft\.com" coredns/xbox-hosts; then
    echo "  ❌ teredo.ipv6.microsoft.com should NOT be in hosts file"
    MISSING_IN_HOSTS=1
else
    echo "  ✅ teredo.ipv6.microsoft.com correctly removed"
fi
echo ""

# Check for problematic domains that should NOT be present
echo "=== Checking for Excluded Domains ==="
PROBLEMATIC=0

# 2K Games domains (should NOT be present)
for domain in "2k.com" "2ksports.com" "take2games.com"; do
    if grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        echo "  ❌ $domain should NOT be in hosts file (causes NBA 2K disconnections)"
        PROBLEMATIC=1
    fi
done

# Akamai CDN (should NOT be present)
if grep -q "^[0-9].*a978.i6g1.akamai.net" coredns/xbox-hosts; then
    echo "  ❌ a978.i6g1.akamai.net should NOT be in hosts file (causes game disconnections)"
    PROBLEMATIC=1
fi

if [ $PROBLEMATIC -eq 0 ]; then
    echo "  ✅ No problematic domains found"
fi
echo ""

# Check scripts
echo "=== Checking Install Script ==="
MISSING_IN_INSTALL=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "\$VPS_IP.*$domain" scripts/setup/install.sh; then
        echo "  ✅ $domain in install.sh"
    else
        echo "  ❌ $domain MISSING in install.sh"
        MISSING_IN_INSTALL=1
    fi
done
echo ""

echo "=== Checking Regenerate Script ==="
MISSING_IN_REGENERATE=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "\$VPS_IP.*$domain" scripts/maintenance/regenerate-hosts.sh; then
        echo "  ✅ $domain in regenerate-hosts.sh"
    else
        echo "  ❌ $domain MISSING in regenerate-hosts.sh"
        MISSING_IN_REGENERATE=1
    fi
done
echo ""

# Summary
echo "================================================"
if [ $MISSING_IN_HOSTS -eq 0 ] && [ $PROBLEMATIC -eq 0 ] && [ $MISSING_IN_INSTALL -eq 0 ] && [ $MISSING_IN_REGENERATE -eq 0 ]; then
    echo "✅ All checks passed!"
    echo ""
    echo "All required domains are present and correct."
else
    echo "⚠️  Issues found:"
    [ $MISSING_IN_HOSTS -eq 1 ] && echo "  • Missing domains in hosts file"
    [ $PROBLEMATIC -eq 1 ] && echo "  • Problematic domains in hosts file"
    [ $MISSING_IN_INSTALL -eq 1 ] && echo "  • Missing domains in install.sh"
    [ $MISSING_IN_REGENERATE -eq 1 ] && echo "  • Missing domains in regenerate-hosts.sh"
    echo ""
    echo "To fix:"
    echo "  bash scripts/maintenance/regenerate-hosts.sh"
fi
echo "================================================"
echo ""


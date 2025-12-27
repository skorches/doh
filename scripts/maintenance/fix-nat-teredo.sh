#!/bin/bash

# Fix NAT and Teredo Issues
# This script adds all required NAT detection domains and ensures Teredo resolves correctly

set -e

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing NAT and Teredo Issues"
echo "================================================"
echo ""

# Get current VPS IP
echo "[1/6] Detecting VPS IP..."
VPS_IP=""
for service in "ifconfig.me" "icanhazip.com" "ipinfo.io/ip" "api.ipify.org"; do
    VPS_IP=$(curl -4 -s --max-time 3 "$service" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -n "$VPS_IP" ]; then
        break
    fi
done

if [ -z "$VPS_IP" ]; then
    echo "❌ Could not detect VPS IP"
    read -p "Enter VPS IP manually: " VPS_IP
fi

echo "✅ VPS IP: $VPS_IP"
echo ""

# Backup hosts file
echo "[2/6] Backing up hosts file..."
cp coredns/xbox-hosts "coredns/xbox-hosts.backup.$(date +%s)" 2>/dev/null || true
echo "✅ Backup created"
echo ""

# Remove Teredo domain if present (must resolve to real servers)
echo "[3/6] Removing Teredo domain from hosts (must resolve to real servers)..."
sed -i '/teredo\.ipv6\.microsoft\.com/d' coredns/xbox-hosts
echo "✅ Teredo domain removed"
echo ""

# Add all required NAT detection domains
echo "[4/6] Adding all required NAT detection domains..."

# List of all required NAT domains
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

# Remove old entries for these domains
for domain in "${NAT_DOMAINS[@]}"; do
    sed -i "/[0-9].*$domain/d" coredns/xbox-hosts
done

# Add NAT detection section if it doesn't exist
if ! grep -q "# === NAT DETECTION ===" coredns/xbox-hosts; then
    echo "" >> coredns/xbox-hosts
    echo "# === NAT DETECTION ===" >> coredns/xbox-hosts
    echo "# CRITICAL: These domains are required for Xbox NAT type detection" >> coredns/xbox-hosts
    echo "# Missing any of these will cause \"NAT unavailable\" errors" >> coredns/xbox-hosts
fi

# Remove old NAT detection section and add new one
sed -i '/# === NAT DETECTION ===/,/^$/d' coredns/xbox-hosts

# Add all NAT domains
cat >> coredns/xbox-hosts << EOF

# === NAT DETECTION ===
# CRITICAL: These domains are required for Xbox NAT type detection
# Missing any of these will cause "NAT unavailable" errors
$VPS_IP xbox.nat.microsoft.com
$VPS_IP xbox.ipv4.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftncsi.com
$VPS_IP ipv6.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv4.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com
# NOTE: teredo.ipv6.microsoft.com must resolve to REAL Teredo servers (not VPS IP)
# It is intentionally NOT in this hosts file

EOF

echo "✅ All NAT detection domains added"
echo ""

# Update VPS IP in hosts file
echo "[5/6] Updating VPS IP throughout hosts file..."
OLD_IP=$(grep -m1 "^[0-9]" coredns/xbox-hosts | head -1 | awk '{print $1}')
if [ "$OLD_IP" != "$VPS_IP" ]; then
    sed -i "s/$OLD_IP/$VPS_IP/g" coredns/xbox-hosts
    echo "✅ Updated IP from $OLD_IP to $VPS_IP"
else
    echo "✅ IP already correct"
fi
echo ""

# Restart CoreDNS to clear cache
echo "[6/6] Restarting CoreDNS to clear cache..."
docker restart coredns-smartdns
sleep 3
echo "✅ CoreDNS restarted"
echo ""

# Verification
echo "================================================"
echo "Verification"
echo "================================================"
echo ""

echo "Checking NAT domains in hosts file:"
MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "$domain" coredns/xbox-hosts; then
        echo "  ✅ $domain"
    else
        echo "  ❌ $domain MISSING"
        MISSING=1
    fi
done
echo ""

# Check Teredo is NOT in hosts
if grep -q "teredo\.ipv6\.microsoft\.com" coredns/xbox-hosts; then
    echo "❌ ERROR: teredo.ipv6.microsoft.com is still in hosts file!"
    echo "   This must be removed - Teredo must resolve to real servers"
    MISSING=1
else
    echo "✅ Teredo domain correctly removed from hosts file"
fi
echo ""

# Test DNS resolution
echo "Testing DNS resolution:"
echo -n "  xbox.nat.microsoft.com: "
RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ $RESULT (correct)"
else
    echo "⚠️  $RESULT (expected $VPS_IP)"
fi

echo -n "  teredo.ipv6.microsoft.com: "
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$TEREDO_RESULT" ] && [ "$TEREDO_RESULT" != "$VPS_IP" ]; then
    echo "✅ $TEREDO_RESULT (resolves to real server - correct)"
else
    echo "⚠️  $TEREDO_RESULT (should NOT be VPS IP)"
fi
echo ""

# Final status
if [ $MISSING -eq 0 ]; then
    echo "================================================"
    echo "✅ NAT and Teredo Fix Complete!"
    echo "================================================"
    echo ""
    echo "All required NAT detection domains are present:"
    echo "  • xbox.nat.microsoft.com"
    echo "  • xbox.ipv4.microsoft.com"
    echo "  • xbox.ipv6.microsoft.com"
    echo "  • dns.msftncsi.com"
    echo "  • www.msftncsi.com"
    echo "  • ipv6.msftncsi.com"
    echo "  • www.msftconnecttest.com"
    echo "  • ipv4.msftconnecttest.com"
    echo "  • ipv6.msftconnecttest.com"
    echo ""
    echo "Teredo domain correctly removed (resolves to real servers)"
    echo ""
    echo "Next steps:"
    echo "1. Restart your Xbox (hold power 10 seconds, wait 30s, turn on)"
    echo "2. Check NAT type: Settings → Network → Network settings → Test NAT type"
    echo "3. If still unavailable, check:"
    echo "   - Xbox DNS is set to VPS IP: $VPS_IP"
    echo "   - Router UPnP is enabled"
    echo "   - Port 3074 (TCP/UDP) is forwarded to Xbox"
    echo "   - No double NAT (router behind another router)"
    echo ""
else
    echo "================================================"
    echo "⚠️  Some issues found - please review above"
    echo "================================================"
    exit 1
fi


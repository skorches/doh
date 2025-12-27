#!/bin/bash

# Fix volume mount and verify hosts file is accessible

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing Volume Mount and Hosts File"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/5] Verifying hosts file exists and is readable..."
if [ ! -f "coredns/xbox-hosts" ]; then
    echo "❌ Hosts file not found! Creating..."
    bash scripts/maintenance/regenerate-hosts.sh
else
    echo "✅ Hosts file exists"
    ls -lh coredns/xbox-hosts
    echo "   First 5 lines:"
    head -5 coredns/xbox-hosts
fi
echo ""

echo "[2/5] Checking file permissions..."
chmod 644 coredns/xbox-hosts
chown root:root coredns/xbox-hosts 2>/dev/null || true
ls -lh coredns/xbox-hosts
echo "✅ Permissions set"
echo ""

echo "[3/5] Verifying NAT domains in hosts file..."
grep "xbox.nat.microsoft.com" coredns/xbox-hosts | head -1
grep "dns.msftncsi.com" coredns/xbox-hosts | head -1
echo ""

echo "[4/5] Checking docker-compose.yml volume mount..."
if grep -q "xbox-hosts:/etc/coredns/xbox-hosts" docker-compose.yml; then
    echo "✅ Volume mount configured correctly"
    grep -A 2 "coredns-smartdns" docker-compose.yml | grep -A 2 volumes
else
    echo "❌ Volume mount might be incorrect"
    echo "Fixing docker-compose.yml..."
    # This would need to be done manually or we update the file
fi
echo ""

echo "[5/5] Testing with curl (bypasses dig requirement)..."
echo "Testing DoH endpoint (should use CoreDNS):"
echo -n "  xbox.nat.microsoft.com via DoH: "
RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ $RESULT"
else
    echo "❌ $RESULT (expected $VPS_IP)"
    echo "   This means CoreDNS isn't serving from hosts file"
fi

echo -n "  dns.msftncsi.com via DoH: "
RESULT2=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=dns.msftncsi.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$RESULT2" == "$VPS_IP" ]; then
    echo "✅ $RESULT2"
else
    echo "❌ $RESULT2 (expected $VPS_IP)"
fi
echo ""

echo "================================================"
echo "If DoH also fails, the issue is CoreDNS"
echo "not loading the hosts file."
echo ""
echo "Possible causes:"
echo "1. Volume mount path incorrect"
echo "2. Hosts file format issue"
echo "3. CoreDNS hosts plugin not working"
echo ""
echo "Next: Check if we need to use absolute paths"
echo "or verify the Corefile hosts plugin syntax"
echo "================================================"
echo ""


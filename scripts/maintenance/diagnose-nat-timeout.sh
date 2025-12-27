#!/bin/bash

# Diagnose why NAT becomes unavailable so quickly

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Diagnosing NAT Timeout Issue"
echo "================================================"
echo ""

echo "[1/5] Checking CoreDNS logs for recent errors/timeouts..."
echo "Last 50 lines of CoreDNS logs:"
docker logs coredns-smartdns --tail 50 2>&1 | grep -iE "error|timeout|servfail|read udp" | tail -20
echo ""

echo "[2/5] Checking what domains are being queried..."
echo "Recent queries (last 30 lines):"
docker logs coredns-smartdns --tail 100 2>&1 | grep -E "\.(A|AAAA)" | tail -30
echo ""

echo "[3/5] Testing NAT domain resolution directly..."
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)
echo "VPS IP: $VPS_IP"
echo ""

NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
)

for domain in "${NAT_DOMAINS[@]}"; do
    echo -n "  $domain: "
    RESULT=$(timeout 2 dig @127.0.0.1 $domain +short 2>/dev/null | head -1)
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo "✅ $RESULT"
    else
        echo "❌ $RESULT (expected $VPS_IP)"
    fi
done
echo ""

echo "[4/5] Checking if hosts file is being loaded correctly..."
if docker exec coredns-smartdns test -f /etc/coredns/xbox-hosts; then
    echo "✅ Hosts file exists in container"
    HOSTS_COUNT=$(docker exec coredns-smartdns wc -l /etc/coredns/xbox-hosts 2>/dev/null | awk '{print $1}')
    echo "   Lines in hosts file: $HOSTS_COUNT"
    
    # Check if NAT domains are in container's hosts file
    echo "   Checking NAT domains in container:"
    for domain in "${NAT_DOMAINS[@]}"; do
        if docker exec coredns-smartdns grep -q "^[0-9].*$domain" /etc/coredns/xbox-hosts 2>/dev/null; then
            echo "     ✅ $domain"
        else
            echo "     ❌ $domain MISSING"
        fi
    done
else
    echo "❌ Hosts file NOT found in container!"
fi
echo ""

echo "[5/5] Checking CoreDNS configuration..."
echo "Current Corefile:"
docker exec coredns-smartdns cat /etc/coredns/Corefile 2>/dev/null | head -30
echo ""

echo "================================================"
echo "Analysis"
echo "================================================"
echo ""
echo "Look for:"
echo "1. Timeout errors in logs (read udp ...->1.1.1.1:53: i/o timeout)"
echo "2. Missing domains in hosts file"
echo "3. Queries for domains not in hosts file"
echo "4. CoreDNS configuration issues"
echo ""
echo "If you see timeouts, it means CoreDNS is trying to query upstream"
echo "for domains not in the hosts file. Add those domains to fix it."
echo ""


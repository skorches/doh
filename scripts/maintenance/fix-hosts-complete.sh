#!/bin/bash

# Complete fix for hosts file loading

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Complete Hosts File Fix"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/6] Updating ALL IPs in hosts file to current VPS IP..."
# Update all IP addresses in hosts file
sed -i "s/^[0-9][0-9.]*[0-9]/$VPS_IP/g" coredns/xbox-hosts
# Update comment
sed -i "s/# VPS IP: .*/# VPS IP: $VPS_IP/" coredns/xbox-hosts
echo "✅ All IPs updated to $VPS_IP"
echo ""

echo "[2/6] Verifying hosts file format (CoreDNS requires: IP domain)..."
# Check format - CoreDNS hosts plugin expects: IP domain (or IP domain1 domain2)
INVALID_LINES=$(grep -v "^#" coredns/xbox-hosts | grep -v "^$" | grep -vE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} " | wc -l)
if [ "$INVALID_LINES" -gt 0 ]; then
    echo "⚠️  Found $INVALID_LINES potentially invalid lines"
    grep -v "^#" coredns/xbox-hosts | grep -v "^$" | grep -vE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} " | head -5
else
    echo "✅ Hosts file format looks correct"
fi
echo ""

echo "[3/6] Ensuring all NAT domains are present..."
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

for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "^$VPS_IP.*$domain" coredns/xbox-hosts; then
        echo "  Adding: $domain"
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
    fi
done
echo "✅ All NAT domains verified"
echo ""

echo "[4/6] Verifying Corefile syntax..."
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts file
    # CoreDNS hosts plugin format: IP domain [domain...]
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward to upstream DNS
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Cache
    cache 3600 {
        success 3600
        denial 3600
    }
    
    # Log errors
    errors
    
    # Health check
    health :8080
}
EOFCORE
echo "✅ Corefile updated"
echo ""

echo "[5/6] Restarting CoreDNS with clean restart..."
docker compose stop coredns-smartdns 2>/dev/null || docker-compose stop coredns-smartdns 2>/dev/null || true
docker compose rm -f coredns-smartdns 2>/dev/null || docker-compose rm -f coredns-smartdns 2>/dev/null || true
docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null
sleep 5
echo "✅ CoreDNS restarted"
echo ""

echo "[6/6] Testing DNS resolution..."
echo "Testing NAT domains (should resolve to $VPS_IP):"
for domain in "xbox.nat.microsoft.com" "dns.msftncsi.com"; do
    echo -n "  $domain: "
    RESULT=$(timeout 3 dig @127.0.0.1 $domain +short 2>/dev/null | head -1)
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo "✅ $RESULT"
    else
        echo "❌ $RESULT (expected $VPS_IP)"
        echo "     Checking CoreDNS logs..."
        docker logs coredns-smartdns --tail 10 2>&1 | tail -5
    fi
done
echo ""

echo "================================================"
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ Fix Complete - NAT domains resolving!"
else
    echo "⚠️  Still not resolving - checking container..."
    echo ""
    echo "Checking if hosts file is in container:"
    docker exec coredns-smartdns sh -c "ls -la /etc/coredns/xbox-hosts 2>&1" || echo "File not found in container!"
    echo ""
    echo "First few lines of hosts file in container:"
    docker exec coredns-smartdns sh -c "head -5 /etc/coredns/xbox-hosts 2>&1" || echo "Cannot read file"
fi
echo "================================================"
echo ""


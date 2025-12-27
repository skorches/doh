#!/bin/bash

# Fix hosts file loading issue in CoreDNS

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing Hosts File Loading Issue"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/5] Checking hosts file..."
if [ ! -f "coredns/xbox-hosts" ]; then
    echo "❌ Hosts file not found! Regenerating..."
    bash scripts/maintenance/regenerate-hosts.sh
else
    echo "✅ Hosts file exists"
    LINE_COUNT=$(wc -l < coredns/xbox-hosts)
    echo "   Lines: $LINE_COUNT"
fi

# Check if NAT domains are present
echo ""
echo "[2/5] Verifying NAT domains in hosts file..."
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

MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        RESOLVED_IP=$(grep "^[0-9].*$domain" coredns/xbox-hosts | head -1 | awk '{print $1}')
        if [ "$RESOLVED_IP" == "$VPS_IP" ]; then
            echo "  ✅ $domain → $RESOLVED_IP"
        else
            echo "  ⚠️  $domain → $RESOLVED_IP (should be $VPS_IP)"
            # Fix it
            sed -i "s/^[0-9].*$domain/$VPS_IP $domain/" coredns/xbox-hosts
            MISSING=1
        fi
    else
        echo "  ❌ $domain MISSING - adding..."
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
        MISSING=1
    fi
done

if [ $MISSING -eq 0 ]; then
    echo "✅ All NAT domains correct"
else
    echo "✅ Fixed NAT domains"
fi
echo ""

echo "[3/5] Fixing Corefile - need fallthrough for other domains..."
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains
    # fallthrough allows other domains to be resolved via upstream
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward with exception for hosts file
    # except ensures hosts file domains NEVER go to upstream
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Cache for non-hosts domains
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
echo "✅ Corefile updated (with fallthrough)"
echo ""

echo "[4/5] Verifying Docker volume mount..."
if grep -q "xbox-hosts" docker-compose.yml; then
    echo "✅ Volume mount configured in docker-compose.yml"
else
    echo "❌ Volume mount missing! Checking docker-compose.yml..."
    grep -A 5 "coredns-smartdns" docker-compose.yml | grep -A 3 volumes
fi
echo ""

echo "[5/5] Restarting CoreDNS..."
docker compose down coredns-smartdns 2>/dev/null || docker-compose down coredns-smartdns 2>/dev/null || true
docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null
sleep 5
echo "✅ CoreDNS restarted"
echo ""

echo "Testing DNS resolution..."
echo -n "  xbox.nat.microsoft.com: "
RESULT=$(timeout 2 dig @127.0.0.1 xbox.nat.microsoft.com +short 2>/dev/null | head -1)
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ $RESULT"
else
    echo "❌ $RESULT (expected $VPS_IP)"
    echo "   Checking if CoreDNS is running..."
    docker ps | grep coredns || echo "   CoreDNS is NOT running!"
fi

echo -n "  dns.msftncsi.com: "
RESULT2=$(timeout 2 dig @127.0.0.1 dns.msftncsi.com +short 2>/dev/null | head -1)
if [ "$RESULT2" == "$VPS_IP" ]; then
    echo "✅ $RESULT2"
else
    echo "❌ $RESULT2 (expected $VPS_IP)"
fi
echo ""

echo "================================================"
if [ "$RESULT" == "$VPS_IP" ] && [ "$RESULT2" == "$VPS_IP" ]; then
    echo "✅ Fix Complete - NAT domains resolving correctly!"
else
    echo "⚠️  NAT domains still not resolving"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check CoreDNS logs: docker logs coredns-smartdns"
    echo "2. Verify hosts file: cat coredns/xbox-hosts | grep xbox.nat"
    echo "3. Check CoreDNS config: docker exec coredns-smartdns ls -la /etc/coredns/"
fi
echo "================================================"
echo ""


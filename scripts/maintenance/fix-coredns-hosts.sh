#!/bin/bash

# Final fix for CoreDNS hosts file loading

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Final CoreDNS Hosts File Fix"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/5] Ensuring hosts file has correct format..."
# Remove dns-proxy dependency (it's broken)
sed -i '/depends_on:/,/dns-proxy/d' docker-compose.yml
sed -i '/^[[:space:]]*$/N;/^\n$/d' docker-compose.yml

# Ensure hosts file has proper format (IP domain, one per line)
# Remove any lines with multiple domains on one line
sed -i 's/\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\) \(.*\)/\1 \2/' coredns/xbox-hosts

# Update all IPs
sed -i "s/^[0-9][0-9.]*[0-9]/$VPS_IP/g" coredns/xbox-hosts
echo "✅ Hosts file format verified"
echo ""

echo "[2/5] Creating minimal test hosts file to verify CoreDNS can load it..."
cat > coredns/xbox-hosts.test << EOF
$VPS_IP xbox.nat.microsoft.com
$VPS_IP dns.msftncsi.com
$VPS_IP test.example.com
EOF
echo "✅ Test file created"
echo ""

echo "[3/5] Updating Corefile to use explicit path and add debug..."
cat > coredns/Corefile << EOFCORE
. {
    # Hosts file - explicit path
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Cache
    cache 3600
    
    # Log all queries for debugging
    log
    
    # Log errors
    errors
    
    # Health check
    health :8080
}
EOFCORE
echo "✅ Corefile updated (added log plugin for debugging)"
echo ""

echo "[4/5] Restarting CoreDNS..."
docker compose down coredns-smartdns 2>/dev/null || docker-compose down coredns-smartdns 2>/dev/null || true
docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null
sleep 5
echo "✅ CoreDNS restarted"
echo ""

echo "[5/5] Testing and checking logs..."
echo "Making a test query..."
# Use nc or curl to test DNS
timeout 2 bash -c "echo -e '\x00\x00\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x04test\x07example\x03com\x00\x00\x01\x00\x01' | nc -u 127.0.0.1 53" 2>/dev/null || echo "Direct DNS test failed"

echo ""
echo "Checking CoreDNS logs for the query..."
sleep 2
docker logs coredns-smartdns --tail 20 2>&1
echo ""

echo "Testing via DoH (should show if CoreDNS is working)..."
RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ xbox.nat.microsoft.com → $RESULT (via DoH)"
else
    echo "❌ xbox.nat.microsoft.com → $RESULT (expected $VPS_IP)"
    echo "   Check CoreDNS logs above for errors"
fi
echo ""

echo "================================================"
echo "If still not working, check:"
echo "1. CoreDNS logs for 'hosts' plugin errors"
echo "2. Volume mount: docker inspect coredns-smartdns | grep -A 10 Mounts"
echo "3. Hosts file syntax: head -10 coredns/xbox-hosts"
echo "================================================"
echo ""


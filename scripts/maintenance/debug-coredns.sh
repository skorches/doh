#!/bin/bash

# Debug CoreDNS hosts file loading

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Debugging CoreDNS Hosts File Loading"
echo "================================================"
echo ""

echo "[1/6] Checking CoreDNS container status..."
docker ps | grep coredns-smartdns
echo ""

echo "[2/6] Checking CoreDNS logs for errors..."
docker logs coredns-smartdns --tail 20
echo ""

echo "[3/6] Checking if hosts file exists in container..."
# Use sh instead of test/cat (minimal alpine image)
docker exec coredns-smartdns sh -c "ls -la /etc/coredns/" 2>&1
echo ""

echo "[4/6] Checking hosts file content in container..."
docker exec coredns-smartdns sh -c "head -20 /etc/coredns/xbox-hosts" 2>&1 | head -20
echo ""

echo "[5/6] Checking if NAT domains are in container's hosts file..."
docker exec coredns-smartdns sh -c "grep 'xbox.nat.microsoft.com' /etc/coredns/xbox-hosts" 2>&1
echo ""

echo "[6/6] Testing CoreDNS directly with a query..."
# Test if CoreDNS responds at all
echo "Querying CoreDNS for xbox.nat.microsoft.com:"
timeout 2 dig @127.0.0.1 xbox.nat.microsoft.com +short 2>&1
echo ""

echo "Checking Corefile syntax..."
docker exec coredns-smartdns sh -c "cat /etc/coredns/Corefile" 2>&1
echo ""

echo "================================================"
echo "If hosts file is empty or missing in container,"
echo "the volume mount might not be working correctly."
echo "================================================"
echo ""


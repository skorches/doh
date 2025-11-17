#!/bin/bash

# Fix port 443 conflict between Docker and HAProxy

set -e

echo "================================================"
echo "Fixing Port 443 Conflict"
echo "================================================"
echo ""

cd /root/doh

# Stop everything
echo "Stopping all services..."
docker-compose down --remove-orphans
systemctl stop haproxy 2>/dev/null || true

echo ""
echo "Current docker-compose.yml port 443 lines:"
grep -n "443" docker-compose.yml

echo ""
echo "Fixing port mapping: 443:443 → 8443:443 (internal only)"

# Fix all port 443 mappings
sed -i 's/"443:443"/"8443:443"/g' docker-compose.yml
sed -i 's/- 443:443/- 8443:443/g' docker-compose.yml
sed -i "s/- '443:443'/- '8443:443'/g" docker-compose.yml

echo ""
echo "New port mappings:"
grep -n "8443" docker-compose.yml

echo ""
echo "Starting Docker containers (Nginx on port 8443 internal)..."
docker-compose up -d

echo ""
echo "Waiting for containers..."
sleep 5

echo ""
echo "Checking port 443 is free..."
if netstat -tlnp | grep -q ":443"; then
    echo "ERROR: Port 443 still in use!"
    netstat -tlnp | grep ":443"
    exit 1
else
    echo "✅ Port 443 is free!"
fi

echo ""
echo "Starting HAProxy..."
systemctl start haproxy

sleep 2

if systemctl is-active --quiet haproxy; then
    echo ""
    echo "✅ HAProxy started successfully!"
    echo ""
    echo "Testing DoH..."
    curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A' | grep -q '"Status":0' && echo "✅ DoH working!" || echo "❌ DoH not working"
else
    echo ""
    echo "❌ HAProxy failed to start"
    journalctl -xeu haproxy -n 20
    exit 1
fi

echo ""
echo "================================================"
echo "✅ Port conflict fixed!"
echo "================================================"
echo ""
echo "Architecture:"
echo "  Port 443 → HAProxy"
echo "  Port 8443 → Nginx (internal)"
echo ""
echo "Next: ./integrate-coredns-smartdns.sh"


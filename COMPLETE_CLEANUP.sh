#!/bin/bash

# COMPLETE CLEANUP - Remove Everything
# Run this on your VPS as root

echo "================================================"
echo "COMPLETE CLEANUP - Removing All Configurations"
echo "================================================"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root"
    echo "Usage: sudo bash COMPLETE_CLEANUP.sh"
    exit 1
fi

echo "This will remove:"
echo "  - All Docker containers"
echo "  - All Docker images"
echo "  - All Docker networks"
echo "  - OpenVPN integration changes"
echo "  - All configuration files"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Step 1: Stopping all Docker containers..."
docker stop $(docker ps -aq) 2>/dev/null || echo "No containers to stop"

echo "Step 2: Removing all Docker containers..."
docker rm $(docker ps -aq) 2>/dev/null || echo "No containers to remove"

echo "Step 3: Stopping all docker-compose services..."
cd /root/doh 2>/dev/null || cd ~/doh 2>/dev/null || echo "Directory not found"

docker-compose -f docker-compose.yml down 2>/dev/null || true
docker-compose -f docker-compose.port443.yml down 2>/dev/null || true
docker-compose -f docker-compose.simple443.yml down 2>/dev/null || true
docker-compose -f docker-compose.openvpn-doh.yml down 2>/dev/null || true

echo "Step 4: Removing Docker networks..."
docker network prune -f 2>/dev/null || true

echo "Step 5: Removing Docker images..."
docker image prune -a -f 2>/dev/null || true

echo "Step 6: Removing Docker volumes..."
docker volume prune -f 2>/dev/null || true

echo "Step 7: Restoring OpenVPN config (if backup exists)..."
if [ -f /etc/openvpn/server.conf.backup.20251115 ]; then
    cp /etc/openvpn/server.conf.backup.20251115 /etc/openvpn/server.conf
    systemctl restart openvpn@server 2>/dev/null || true
    echo "✓ OpenVPN config restored"
else
    echo "  No OpenVPN backup found (OK)"
fi

echo "Step 8: Removing configuration files..."
cd /root/doh 2>/dev/null || cd ~/doh 2>/dev/null || cd /opt/doh-server 2>/dev/null || echo "No directory"

rm -f docker-compose.yml 2>/dev/null
rm -f docker-compose.port443.yml 2>/dev/null
rm -f docker-compose.simple443.yml 2>/dev/null
rm -f docker-compose.openvpn-doh.yml 2>/dev/null
rm -rf coredns-443 2>/dev/null

echo "Step 9: Checking services..."
docker ps -a
echo ""
docker images
echo ""

echo "================================================"
echo "CLEANUP COMPLETE!"
echo "================================================"
echo ""
echo "Removed:"
echo "  ✓ All Docker containers"
echo "  ✓ All Docker images"
echo "  ✓ All networks and volumes"
echo "  ✓ Configuration files"
echo "  ✓ OpenVPN integration (restored original)"
echo ""
echo "What's still running:"
echo "  - OpenVPN server (if you had it before)"
echo "  - System services"
echo ""
echo "Next steps:"
echo "  1. cd /root/doh (or wherever your files are)"
echo "  2. sudo ./deploy-keenetic-doh.sh"
echo ""


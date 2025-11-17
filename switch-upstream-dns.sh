#!/bin/bash

# Switch to faster upstream DNS servers
# For better Xbox compatibility

set -e

echo "================================================"
echo "Switching to Faster Upstream DNS"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd /root/doh

echo "Current upstream: Quad9 (9.9.9.9, 149.112.112.112)"
echo ""
echo "Choose faster alternative:"
echo "1) Cloudflare (1.1.1.1) - Fastest globally"
echo "2) Google (8.8.8.8) - Very fast, reliable"
echo "3) Cloudflare + Google (both)"
echo "4) Keep Quad9 (current)"
echo ""
read -p "Select (1-4): " choice

case $choice in
    1)
        UPSTREAM="udp:1.1.1.1:53,udp:1.0.0.1:53"
        NAME="Cloudflare"
        ;;
    2)
        UPSTREAM="udp:8.8.8.8:53,udp:8.8.4.4:53"
        NAME="Google"
        ;;
    3)
        UPSTREAM="udp:1.1.1.1:53,udp:8.8.8.8:53,udp:1.0.0.1:53"
        NAME="Cloudflare + Google"
        ;;
    4)
        echo "Keeping Quad9"
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Updating to $NAME DNS...${NC}"

# Backup current config
cp docker-compose.yml docker-compose.yml.backup

# Update upstream DNS in docker-compose
sed -i "s|UPSTREAM_DNS_SERVER=.*|UPSTREAM_DNS_SERVER=$UPSTREAM|g" docker-compose.yml

echo -e "${GREEN}✓ Configuration updated${NC}"

# Restart services
echo -e "${YELLOW}Restarting services...${NC}"
docker-compose down
docker-compose up -d

sleep 5

if docker ps | grep -q "doh-backend"; then
    echo -e "${GREEN}✓ DoH server restarted with $NAME DNS${NC}"
else
    echo "Failed to restart. Restoring backup..."
    mv docker-compose.yml.backup docker-compose.yml
    docker-compose up -d
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}Upstream DNS changed to: $NAME${NC}"
echo "================================================"
echo ""
echo "Test from your computer:"
echo "  nslookup xbox.com"
echo ""
echo "Should be faster now!"
echo ""


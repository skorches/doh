#!/bin/bash

# Clean up all existing configurations
# Start fresh for Keenetic DoH setup

echo "================================================"
echo "Cleanup - Removing All Previous Configurations"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${YELLOW}Stopping all Docker containers...${NC}"

# Stop all containers
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove all containers
docker rm $(docker ps -aq) 2>/dev/null || true

echo -e "${GREEN}✓ All containers removed${NC}"

# Stop docker-compose services
echo -e "${YELLOW}Removing docker-compose services...${NC}"
docker-compose -f docker-compose.yml down 2>/dev/null || true
docker-compose -f docker-compose.port443.yml down 2>/dev/null || true
docker-compose -f docker-compose.simple443.yml down 2>/dev/null || true
docker-compose -f docker-compose.openvpn-doh.yml down 2>/dev/null || true

# Remove networks
docker network prune -f 2>/dev/null || true

echo -e "${GREEN}✓ Docker cleaned up${NC}"

# Clean up old configs
echo -e "${YELLOW}Removing old configuration files...${NC}"
rm -f docker-compose.port443.yml
rm -f docker-compose.simple443.yml
rm -f docker-compose.openvpn-doh.yml
rm -rf coredns-443

echo -e "${GREEN}✓ Old configs removed${NC}"

# Free up ports
echo -e "${YELLOW}Freeing ports...${NC}"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true

echo -e "${GREEN}✓ Ports freed${NC}"

# Clean Docker images (optional)
echo ""
read -p "Clean unused Docker images too? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker image prune -a -f
    echo -e "${GREEN}✓ Images cleaned${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "Ready for fresh Keenetic-compatible DoH setup"
echo "Next step: sudo ./deploy-keenetic-doh.sh"
echo ""


#!/bin/bash

# Fix DNS Proxy Errors
# Run this if you're getting dns-proxy errors

set -e

echo "================================================"
echo "DNS Proxy Error Fix"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${YELLOW}Stopping all DNS-related containers...${NC}"

# Stop all potentially conflicting containers
docker stop dns-proxy 2>/dev/null || true
docker stop dns-proxy-client 2>/dev/null || true
docker stop doh-proxy 2>/dev/null || true
docker stop doh-server 2>/dev/null || true
docker stop doh-https 2>/dev/null || true
docker stop doh-server-internal 2>/dev/null || true
docker stop coredns 2>/dev/null || true

# Remove them
docker rm dns-proxy 2>/dev/null || true
docker rm dns-proxy-client 2>/dev/null || true
docker rm doh-proxy 2>/dev/null || true
docker rm doh-server 2>/dev/null || true
docker rm doh-https 2>/dev/null || true
docker rm doh-server-internal 2>/dev/null || true
docker rm coredns 2>/dev/null || true

echo -e "${GREEN}✓ Cleaned up old containers${NC}"

# Stop any services using port 53 and 443
echo -e "${YELLOW}Freeing ports 53 and 443...${NC}"

# Check what's using port 53
if lsof -Pi :53 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "Port 53 in use, stopping services..."
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
fi

# Check what's using port 443
if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "Port 443 in use, stopping web servers..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
fi

echo -e "${GREEN}✓ Ports freed${NC}"

# Remove old compose files
echo -e "${YELLOW}Cleaning up old configurations...${NC}"
docker-compose -f docker-compose.yml down 2>/dev/null || true
docker-compose -f docker-compose.port443.yml down 2>/dev/null || true
docker-compose -f docker-compose.simple443.yml down 2>/dev/null || true

echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""
echo "================================================"
echo "Now try one of these:"
echo "================================================"
echo ""
echo "Option 1: Simple DoH on port 443 (recommended)"
echo "  ./deploy-doh-443-simple.sh"
echo ""
echo "Option 2: Regular DoH on port 443"
echo "  ./deploy-doh-443.sh"
echo ""
echo "Option 3: Standard deployment"
echo "  ./deploy.sh"
echo ""


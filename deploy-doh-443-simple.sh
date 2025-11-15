#!/bin/bash

# Simplified DoH on Port 443 - Minimal Configuration
# Use this if deploy-doh-443.sh gives errors

set -e

echo "================================================"
echo "Simplified DNS-over-HTTPS on Port 443"
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

VPS_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Stop any conflicting services
echo -e "${YELLOW}Stopping services on port 443...${NC}"
docker stop doh-https 2>/dev/null || true
docker stop doh-proxy 2>/dev/null || true
docker stop nginx 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# Create minimal docker-compose
cat > docker-compose.simple443.yml << 'EOF'
version: '3.8'

services:
  # Internal DNS resolver
  doh-internal:
    image: cloudflare/cloudflared:latest
    container_name: doh-internal
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5053
    networks:
      - doh-net

  # DoH on port 443
  doh-443:
    image: satishweb/doh-server:latest
    container_name: doh-443
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=doh-internal:5053
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:443
    ports:
      - "443:443/tcp"
    networks:
      - doh-net
    depends_on:
      - doh-internal

  # Simple DNS forwarder on port 53
  dns-53:
    image: cloudflare/cloudflared:latest
    container_name: dns-53
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=53
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    networks:
      - doh-net

networks:
  doh-net:
    driver: bridge
EOF

# Firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
ufw allow 443/tcp 2>/dev/null || true
ufw allow 53/udp 2>/dev/null || true
ufw allow 53/tcp 2>/dev/null || true

# Start
echo -e "${YELLOW}Starting services...${NC}"
docker-compose -f docker-compose.simple443.yml down 2>/dev/null || true
docker-compose -f docker-compose.simple443.yml up -d

sleep 5

# Check
if docker ps | grep -q "doh-443"; then
    echo -e "${GREEN}✓ Success! DoH running on port 443${NC}"
else
    echo -e "${RED}✗ Error starting services${NC}"
    docker-compose -f docker-compose.simple443.yml logs
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "================================================"
echo ""
echo "DoH Server: https://$VPS_IP/dns-query"
echo "DNS Server: $VPS_IP (port 53)"
echo ""
echo "Test from Xbox:"
echo "  Settings → Network → DNS: $VPS_IP"
echo ""
echo "View logs:"
echo "  docker-compose -f docker-compose.simple443.yml logs -f"
echo ""


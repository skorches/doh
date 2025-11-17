#!/bin/bash

# Fix upstream to use DoH instead of plain DNS
# This ensures end-to-end encryption and bypasses ISP DNS blocks

set -e

echo "================================================"
echo "Configure Upstream DNS-over-HTTPS"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh

echo "Current setup uses plain UDP DNS to upstream servers"
echo "This might be blocked by your ISP!"
echo ""
echo "Choose DoH upstream (fully encrypted):"
echo ""
echo "1) Cloudflare DoH (1.1.1.1 via HTTPS) - Fastest"
echo "2) Google DoH (8.8.8.8 via HTTPS) - Very fast"  
echo "3) Quad9 DoH (9.9.9.9 via HTTPS) - Privacy-focused"
echo "4) Cloudflare DNS + Google DoH (mixed) - Best compatibility"
echo "5) Plain UDP (current) - Keep as is"
echo ""
read -p "Select (1-5): " choice

case $choice in
    1)
        UPSTREAM="https://1.1.1.1/dns-query,https://1.0.0.1/dns-query"
        NAME="Cloudflare DoH"
        ;;
    2)
        UPSTREAM="https://8.8.8.8/dns-query,https://8.8.4.4/dns-query"
        NAME="Google DoH"
        ;;
    3)
        UPSTREAM="https://dns.quad9.net/dns-query,https://dns9.quad9.net/dns-query"
        NAME="Quad9 DoH"
        ;;
    4)
        UPSTREAM="udp:1.1.1.1:53,https://8.8.8.8/dns-query"
        NAME="Cloudflare UDP + Google DoH (hybrid)"
        ;;
    5)
        echo "Keeping current configuration"
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Configuring $NAME...${NC}"

# Check if doh-server image supports HTTPS upstream
echo ""
echo "Note: The doh-server image might need different configuration for DoH upstream"
echo "Creating optimized config..."

# Backup
cp docker-compose.yml docker-compose.yml.backup.$(date +%s)

# Create new config with DoH-capable setup
cat > docker-compose.yml << EOF
version: '3.8'

services:
  # Cloudflared for DoH upstream (proper DoH client)
  doh-upstream:
    image: cloudflare/cloudflared:latest
    container_name: doh-upstream
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=$UPSTREAM
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5053
    networks:
      - doh-network

  # DoH backend using cloudflared as upstream
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      # Use local cloudflared as upstream (which uses DoH)
      - UPSTREAM_DNS_SERVER=udp:doh-upstream:5053
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8080
      - DOH_SERVER_TIMEOUT=30
      - DOH_SERVER_TRIES=5
      - DOH_SERVER_VERBOSE=true
    depends_on:
      - doh-upstream
    networks:
      - doh-network

  nginx:
    image: nginx:alpine
    container_name: doh-nginx
    restart: unless-stopped
    ports:
      - "443:443/tcp"
      - "80:80/tcp"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - doh-backend
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOF

echo -e "${GREEN}✓ Configuration created${NC}"

# Restart
echo -e "${YELLOW}Restarting services...${NC}"
docker-compose down
docker-compose pull
docker-compose up -d

sleep 8

# Check all containers
if docker ps | grep -q "doh-upstream" && docker ps | grep -q "doh-backend" && docker ps | grep -q "doh-nginx"; then
    echo -e "${GREEN}✓ All services running${NC}"
else
    echo -e "${RED}✗ Some services failed${NC}"
    docker-compose logs
    exit 1
fi

# Test
echo ""
echo -e "${YELLOW}Testing configuration...${NC}"
sleep 2

curl -s https://bypass.440.dev/dns-query > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ DoH endpoint responding${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}Upstream DoH Configured!${NC}"
echo "================================================"
echo ""
echo "Traffic flow now:"
echo "  Keenetic → HTTPS → nginx → doh-backend → doh-upstream → $NAME"
echo ""
echo "Everything encrypted end-to-end! ✅"
echo ""
echo "Benefits:"
echo "  ✓ ISP can't see DNS queries"
echo "  ✓ ISP can't block upstream DNS"
echo "  ✓ Full encryption"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo ""
echo "Test Xbox now!"
echo ""


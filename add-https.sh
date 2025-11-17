#!/bin/bash

# Add HTTPS support to DoH server with self-signed certificate
# For Keenetic routers that require HTTPS

set -e

echo "================================================"
echo "Adding HTTPS Support to DoH Server"
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

VPS_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Stop current service
echo -e "${YELLOW}Stopping current DoH service...${NC}"
cd /root/doh
docker-compose down

# Create SSL directory
mkdir -p ssl

# Generate self-signed certificate
echo -e "${YELLOW}Generating SSL certificate...${NC}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ssl/doh.key \
    -out ssl/doh.crt \
    -subj "/C=US/ST=State/L=City/O=DoH/CN=$VPS_IP" \
    2>/dev/null

chmod 644 ssl/doh.crt
chmod 600 ssl/doh.key

echo -e "${GREEN}✓ SSL certificate created${NC}"

# Create new docker-compose with HTTPS support
echo -e "${YELLOW}Creating HTTPS configuration...${NC}"

cat > docker-compose.yml << EOF
version: '3.8'

services:
  # DNS-over-HTTPS with SSL
  doh-server:
    image: satishweb/doh-server:latest
    container_name: doh-keenetic
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=udp:9.9.9.9:53,udp:149.112.112.112:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:443
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
      - DOH_SERVER_VERBOSE=true
      # SSL Configuration
      - DOH_SERVER_CERT=/etc/doh/ssl/doh.crt
      - DOH_SERVER_KEY=/etc/doh/ssl/doh.key
    ports:
      - "443:443/tcp"
    volumes:
      - ./ssl:/etc/doh/ssl:ro
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOF

# Start with HTTPS
echo -e "${YELLOW}Starting DoH server with HTTPS...${NC}"
docker-compose up -d

sleep 5

# Test
if docker ps | grep -q "doh-keenetic"; then
    echo -e "${GREEN}✓ DoH server with HTTPS running!${NC}"
else
    echo -e "${RED}✗ Failed to start${NC}"
    docker-compose logs
    exit 1
fi

# Test HTTPS endpoint
echo ""
echo -e "${YELLOW}Testing HTTPS endpoint...${NC}"
curl -k -I https://localhost:443/dns-query 2>&1 | head -5

echo ""
echo "================================================"
echo -e "${GREEN}HTTPS DoH Server Ready!${NC}"
echo "================================================"
echo ""
echo "Your HTTPS DoH URL:"
echo "  https://$VPS_IP/dns-query"
echo ""
echo "In Keenetic, use:"
echo "  https://$VPS_IP/dns-query"
echo ""
echo "Note: Using self-signed certificate"
echo "  - Keenetic might show security warning"
echo "  - Click 'Proceed anyway' or 'Trust certificate'"
echo ""
echo "Test from your computer:"
echo "  curl -k https://$VPS_IP/dns-query"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo ""
echo "================================================"


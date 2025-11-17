#!/bin/bash

# Fix HTTPS for DoH Server using Nginx reverse proxy
# This properly handles SSL termination

set -e

echo "================================================"
echo "Setting Up Proper HTTPS for DoH Server"
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
echo -e "${YELLOW}Stopping current services...${NC}"
cd /root/doh
docker-compose down 2>/dev/null || true

# Create directories
mkdir -p ssl nginx

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

# Create nginx config
echo -e "${YELLOW}Creating nginx configuration...${NC}"

cat > nginx/default.conf << 'EOF'
server {
    listen 443 ssl http2;
    server_name _;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/doh.crt;
    ssl_certificate_key /etc/nginx/ssl/doh.key;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # DoH endpoint
    location /dns-query {
        proxy_pass http://doh-backend:8080/dns-query;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers for DoH
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Create docker-compose with nginx + DoH backend
echo -e "${YELLOW}Creating docker-compose configuration...${NC}"

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # DoH backend (HTTP only, internal)
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=udp:9.9.9.9:53,udp:149.112.112.112:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8080
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
      - DOH_SERVER_VERBOSE=true
    networks:
      - doh-network

  # Nginx for HTTPS termination
  nginx:
    image: nginx:alpine
    container_name: doh-nginx
    restart: unless-stopped
    ports:
      - "443:443/tcp"
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

# Start services
echo -e "${YELLOW}Starting services...${NC}"
docker-compose up -d

sleep 5

# Check status
if docker ps | grep -q "doh-nginx" && docker ps | grep -q "doh-backend"; then
    echo -e "${GREEN}✓ Services running!${NC}"
else
    echo -e "${RED}✗ Failed to start${NC}"
    docker-compose logs
    exit 1
fi

# Test HTTPS
echo ""
echo -e "${YELLOW}Testing HTTPS endpoint...${NC}"
sleep 2

RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost/dns-query 2>/dev/null)

if [ "$RESPONSE" == "415" ] || [ "$RESPONSE" == "400" ]; then
    echo -e "${GREEN}✓ HTTPS endpoint working! (HTTP $RESPONSE is expected)${NC}"
else
    echo -e "${YELLOW}⚠ Got HTTP $RESPONSE${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}HTTPS DoH Server Ready!${NC}"
echo "================================================"
echo ""
echo "Your HTTPS DoH URL:"
echo "  https://$VPS_IP/dns-query"
echo ""
echo "Configure in Keenetic:"
echo "  https://$VPS_IP/dns-query"
echo ""
echo "Architecture:"
echo "  Keenetic → nginx (HTTPS) → doh-backend (HTTP) → Quad9 DNS"
echo ""
echo "Test from your computer:"
echo "  curl -k -I https://$VPS_IP/dns-query"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo "  docker-compose logs -f nginx     # Nginx logs"
echo "  docker-compose logs -f doh-backend  # DoH logs"
echo ""
echo "Note: Self-signed certificate"
echo "  Keenetic might require 'trust' or 'skip validation'"
echo ""
echo "================================================"


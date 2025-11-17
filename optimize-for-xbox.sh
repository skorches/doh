#!/bin/bash

# Optimize DoH server for Xbox connectivity
# Increase timeouts and add faster DNS

set -e

echo "================================================"
echo "Optimizing DoH Server for Xbox"
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

echo -e "${YELLOW}Backing up current configuration...${NC}"
cp docker-compose.yml docker-compose.yml.backup.$(date +%s)

echo -e "${YELLOW}Creating optimized configuration...${NC}"

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      # Use fastest DNS servers (Cloudflare + Google)
      - UPSTREAM_DNS_SERVER=udp:1.1.1.1:53,udp:8.8.8.8:53,udp:1.0.0.1:53,udp:8.8.4.4:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8080
      # Increased timeouts for Xbox
      - DOH_SERVER_TIMEOUT=30
      - DOH_SERVER_TRIES=5
      - DOH_SERVER_VERBOSE=true
    networks:
      - doh-network
    # Performance optimizations
    dns:
      - 1.1.1.1
      - 8.8.8.8

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

# Update nginx config for better performance
cat > nginx/default.conf << 'EOF'
server {
    listen 443 ssl;
    server_name bypass.440.dev;

    ssl_certificate /etc/nginx/ssl/doh.crt;
    ssl_certificate_key /etc/nginx/ssl/doh.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Increased timeouts for Xbox
    proxy_connect_timeout 30s;
    proxy_send_timeout 30s;
    proxy_read_timeout 30s;
    send_timeout 30s;

    location /dns-query {
        proxy_pass http://doh-backend:8080/dns-query;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Buffering settings
        proxy_buffering off;
        proxy_request_buffering off;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
    }

    location /health {
        access_log off;
        return 200 "DoH Server OK\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen 80;
    server_name bypass.440.dev;
    return 301 https://$server_name$request_uri;
}
EOF

echo -e "${GREEN}✓ Configuration optimized${NC}"

# Restart services
echo -e "${YELLOW}Restarting services...${NC}"
docker-compose down
docker-compose up -d

sleep 5

if docker ps | grep -q "doh-backend" && docker ps | grep -q "doh-nginx"; then
    echo -e "${GREEN}✓ Services restarted${NC}"
else
    echo "Failed! Restoring backup..."
    cp docker-compose.yml.backup.* docker-compose.yml 2>/dev/null || true
    docker-compose up -d
    exit 1
fi

# Test
echo ""
echo -e "${YELLOW}Testing optimized configuration...${NC}"
sleep 2

curl -s https://bypass.440.dev/dns-query > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ DoH endpoint responding${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}Optimization Complete!${NC}"
echo "================================================"
echo ""
echo "Changes made:"
echo "  ✓ Switched to Cloudflare + Google DNS (fastest)"
echo "  ✓ Increased timeout from 10s to 30s"
echo "  ✓ Increased retry attempts from 3 to 5"
echo "  ✓ Optimized nginx proxy settings"
echo ""
echo "This should fix Xbox NAT timeout issues!"
echo ""
echo "Test Xbox now:"
echo "  Settings → Network → Test connection"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo ""


#!/bin/bash

# DoH Server on Port 443 - For ISPs that block port 53
# This makes DoH look like regular HTTPS traffic

set -e

echo "================================================"
echo "DNS-over-HTTPS on Port 443 Setup"
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

# Get VPS IP
VPS_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker not found. Please run ./deploy.sh first${NC}"
    exit 1
fi

# Stop any service using port 443
echo -e "${YELLOW}Checking port 443...${NC}"
if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo -e "${YELLOW}Port 443 is in use. Attempting to free it...${NC}"
    # Try to stop common services on 443
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
fi

# Create alternative docker-compose configuration
echo -e "${YELLOW}Creating DoH-443 configuration...${NC}"

cat > docker-compose.port443.yml << 'EOF'
version: '3.8'

services:
  # DNS-over-HTTPS Server (internal)
  doh-server:
    image: cloudflare/cloudflared:latest
    container_name: doh-server-internal
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query,https://doh.cleanbrowsing.org/doh/security-filter/
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5053
      - TUNNEL_METRICS=0.0.0.0:49312
    networks:
      - doh-network

  # DoH Server on Port 443 (looks like HTTPS)
  doh-https:
    image: satishweb/doh-server:latest
    container_name: doh-https
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=doh-server-internal:5053
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:443
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
      - DOH_SERVER_VERBOSE=false
    ports:
      - "443:443/tcp"
    networks:
      - doh-network
    depends_on:
      - doh-server

  # DNS Proxy using CoreDNS (simpler, more reliable)
  dns-proxy:
    image: coredns/coredns:latest
    container_name: dns-proxy
    restart: unless-stopped
    command: -conf /etc/coredns/Corefile
    volumes:
      - ./coredns-443/Corefile:/etc/coredns/Corefile:ro
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    networks:
      - doh-network
    depends_on:
      - doh-server

networks:
  doh-network:
    driver: bridge
EOF

# Configure firewall
echo -e "${YELLOW}Configuring firewall for port 443...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 443/tcp
    ufw allow 53/tcp
    ufw allow 53/udp
    echo -e "${GREEN}UFW firewall rules added${NC}"
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=53/tcp
    firewall-cmd --permanent --add-port=53/udp
    firewall-cmd --reload
    echo -e "${GREEN}FirewallD rules added${NC}"
fi

# Create CoreDNS config directory
echo -e "${YELLOW}Creating DNS proxy configuration...${NC}"
mkdir -p coredns-443

cat > coredns-443/Corefile << 'EOF'
. {
    log
    errors
    
    # Forward to internal DoH server
    forward . doh-server-internal:5053 {
        max_concurrent 1000
        health_check 5s
    }
    
    # Cache DNS responses
    cache {
        success 9984 3600
        denial 9984 60
    }
}
EOF

# Start services
echo -e "${YELLOW}Starting DoH services on port 443...${NC}"
docker-compose -f docker-compose.port443.yml down 2>/dev/null || true
docker-compose -f docker-compose.port443.yml pull
docker-compose -f docker-compose.port443.yml up -d

# Wait for services
sleep 5

# Test the service
echo -e "${YELLOW}Testing DoH server...${NC}"
if docker ps | grep -q "doh-https"; then
    echo -e "${GREEN}✓ DoH server running on port 443${NC}"
else
    echo -e "${RED}✗ Failed to start DoH server${NC}"
    docker-compose -f docker-compose.port443.yml logs
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}DoH on Port 443 Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Your DoH server is now accessible:"
echo ""
echo "  DoH URL: https://$VPS_IP/dns-query"
echo "  Port: 443 (HTTPS - harder to block)"
echo "  Also: DNS on port 53 (for compatible devices)"
echo ""
echo "================================================"
echo "Testing Connection"
echo "================================================"
echo ""

# Test DNS resolution
if command -v dig &> /dev/null; then
    echo "Testing DNS resolution:"
    dig @localhost xbox.com +short
    echo ""
fi

# Test HTTPS endpoint
if command -v curl &> /dev/null; then
    echo "Testing HTTPS DoH endpoint:"
    response=$(curl -s -w "%{http_code}" https://localhost:443/dns-query -H "Content-Type: application/dns-message" -o /dev/null --insecure)
    if [ "$response" -eq 200 ] || [ "$response" -eq 400 ]; then
        echo -e "${GREEN}✓ HTTPS DoH endpoint responding${NC}"
    else
        echo -e "${YELLOW}⚠ Got HTTP $response (might still work)${NC}"
    fi
    echo ""
fi

echo "================================================"
echo "Next Steps"
echo "================================================"
echo ""
echo "Option 1: Test from your home computer"
echo "  Windows:"
echo "    nslookup xbox.com $VPS_IP"
echo ""
echo "Option 2: Configure Xbox DNS"
echo "  Settings → Network → DNS: $VPS_IP"
echo ""
echo "Option 3: If Xbox doesn't work directly:"
echo "  Your ISP might be doing deep packet inspection"
echo "  Consider: GL.iNet router or OpenVPN instead"
echo "  See ALTERNATIVES.md for options"
echo ""
echo "Test if port 443 bypasses blocking:"
echo "  curl -k https://$VPS_IP/dns-query"
echo ""
echo "View logs:"
echo "  docker-compose -f docker-compose.port443.yml logs -f"
echo ""
echo "================================================"


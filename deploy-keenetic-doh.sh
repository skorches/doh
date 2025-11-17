#!/bin/bash

# DoH Server for Keenetic Router
# Similar to xbox-dns.ru setup
# Simple, clean, and works!

set -e

echo "================================================"
echo "DoH Server for Keenetic Router Setup"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

VPS_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Install Docker if needed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Installing Docker Compose...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Ask for port
echo "Which port should DoH server use?"
echo "1) Port 443 (HTTPS - recommended, harder to block)"
echo "2) Port 8053 (Alternative)"
echo "3) Port 3000 (Another alternative)"
echo ""
read -p "Select (1-3) [default: 1]: " port_choice

case $port_choice in
    2)
        DOH_PORT=8053
        ;;
    3)
        DOH_PORT=3000
        ;;
    *)
        DOH_PORT=443
        ;;
esac

echo -e "${GREEN}Using port: $DOH_PORT${NC}"
echo ""

# Stop services on that port
if [ "$DOH_PORT" == "443" ]; then
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi

# Create simple docker-compose
echo -e "${YELLOW}Creating DoH server configuration...${NC}"

cat > docker-compose.yml << EOF
version: '3.8'

services:
  # DNS-over-HTTPS Server (like xbox-dns.ru)
  doh-server:
    image: satishweb/doh-server:latest
    container_name: doh-keenetic
    restart: unless-stopped
    environment:
      # Upstream DNS servers (non-blocked in Russia)
      - UPSTREAM_DNS_SERVER=udp:9.9.9.9:53,udp:149.112.112.112:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:${DOH_PORT}
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
      - DOH_SERVER_VERBOSE=true
    ports:
      - "${DOH_PORT}:${DOH_PORT}/tcp"
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOF

# Enable IP forwarding
echo -e "${YELLOW}Configuring system...${NC}"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf 2>/dev/null || true
sysctl -p 2>/dev/null || true

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${DOH_PORT}/tcp
    echo -e "${GREEN}✓ UFW configured${NC}"
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${DOH_PORT}/tcp
    firewall-cmd --reload
    echo -e "${GREEN}✓ Firewalld configured${NC}"
fi

# Start service
echo -e "${YELLOW}Starting DoH server...${NC}"
docker-compose down 2>/dev/null || true
docker-compose pull
docker-compose up -d

# Wait
sleep 5

# Check
if docker ps | grep -q "doh-keenetic"; then
    echo -e "${GREEN}✓ DoH server is running!${NC}"
else
    echo -e "${RED}✗ Failed to start${NC}"
    docker-compose logs
    exit 1
fi

# Test
echo ""
echo -e "${YELLOW}Testing DoH server...${NC}"
if command -v curl &> /dev/null; then
    # Simple HTTP test
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${DOH_PORT}/dns-query 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "400" ] || [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✓ DoH endpoint responding${NC}"
    else
        echo -e "${YELLOW}HTTP $HTTP_CODE (might still work)${NC}"
    fi
fi

echo ""
echo "================================================"
echo -e "${GREEN}DoH Server Setup Complete!${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}Your DoH URL:${NC}"
if [ "$DOH_PORT" == "443" ]; then
    echo "  https://$VPS_IP/dns-query"
    echo "  or"
    echo "  http://$VPS_IP/dns-query"
else
    echo "  http://$VPS_IP:${DOH_PORT}/dns-query"
fi
echo ""
echo "================================================"
echo -e "${BLUE}Configure Keenetic Router:${NC}"
echo "================================================"
echo ""
echo "1. Access router: http://192.168.1.1 (or your router IP)"
echo ""
echo "2. Go to: Internet → DNS"
echo ""
echo "3. Enable: DNS-over-HTTPS"
echo ""
echo "4. Enter DoH URL:"
if [ "$DOH_PORT" == "443" ]; then
    echo "   https://$VPS_IP/dns-query"
else
    echo "   http://$VPS_IP:${DOH_PORT}/dns-query"
fi
echo ""
echo "5. Save and apply"
echo ""
echo "6. Test: Your Xbox should now connect!"
echo ""
echo "================================================"
echo -e "${BLUE}Alternative: Direct in Keenetic${NC}"
echo "================================================"
echo ""
echo "If web interface method doesn't work, use CLI:"
echo ""
echo "  ssh admin@192.168.1.1"
echo "  opkg dns-over-https"
if [ "$DOH_PORT" == "443" ]; then
    echo "  opkg dns-over-https url https://$VPS_IP/dns-query"
else
    echo "  opkg dns-over-https url http://$VPS_IP:${DOH_PORT}/dns-query"
fi
echo "  system configuration save"
echo ""
echo "================================================"
echo -e "${BLUE}Monitoring:${NC}"
echo "================================================"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo ""
echo "Check status:"
echo "  docker ps"
echo ""
echo "Restart:"
echo "  docker-compose restart"
echo ""
echo "================================================"
echo ""
echo -e "${GREEN}Done! Configure your Keenetic router with the DoH URL above.${NC}"
echo ""


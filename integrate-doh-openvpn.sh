#!/bin/bash

# Integrate DoH Server with Existing OpenVPN
# This adds DNS-over-HTTPS capability to your existing OpenVPN setup

set -e

echo "================================================"
echo "Integrate DoH with Existing OpenVPN"
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

# Check if OpenVPN is running
if ! systemctl is-active --quiet openvpn@server && ! pgrep -x openvpn > /dev/null; then
    echo -e "${RED}Error: OpenVPN doesn't seem to be running${NC}"
    echo "Run: sudo systemctl status openvpn@server"
    exit 1
fi

echo -e "${GREEN}✓ OpenVPN detected${NC}"
echo ""

# Get OpenVPN network
if [ -f /etc/openvpn/server.conf ]; then
    OPENVPN_NETWORK=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2}' | cut -d. -f1-3)
    OPENVPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
    echo "OpenVPN Network: ${OPENVPN_NETWORK}.0"
    echo "OpenVPN Port: $OPENVPN_PORT"
else
    echo -e "${YELLOW}Can't find /etc/openvpn/server.conf${NC}"
    read -p "Enter your OpenVPN network (e.g., 10.8.0): " OPENVPN_NETWORK
fi

VPN_GATEWAY="${OPENVPN_NETWORK}.1"
echo "VPN Gateway IP: $VPN_GATEWAY"
echo ""

# Deploy DoH server (not on port 443 to avoid conflicts)
echo -e "${YELLOW}Deploying DoH server...${NC}"

cat > docker-compose.openvpn-doh.yml << 'EOF'
version: '3.8'

services:
  # DNS-over-HTTPS Server
  doh-server:
    image: cloudflare/cloudflared:latest
    container_name: doh-for-openvpn
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query,https://doh.cleanbrowsing.org/doh/security-filter/
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5353
      - TUNNEL_METRICS=0.0.0.0:49312
    ports:
      - "5353:5353/udp"
      - "5353:5353/tcp"
    networks:
      - doh-network

  # DNS Proxy for OpenVPN clients
  dns-proxy:
    image: coredns/coredns:latest
    container_name: dns-proxy-openvpn
    restart: unless-stopped
    volumes:
      - ./coredns/Corefile:/Corefile:ro
      - ./coredns/xbox-hosts:/etc/coredns/xbox-hosts:ro
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

# Create CoreDNS config if doesn't exist
mkdir -p coredns

if [ ! -f coredns/Corefile ]; then
    cat > coredns/Corefile << 'EOF'
. {
    log
    errors
    
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    cache {
        success 9984 3600
        denial 9984 60
        prefetch 10 60s
    }
    
    forward . 127.0.0.1:5353 {
        max_concurrent 1000
        health_check 5s
    }
    
    reload
}
EOF
fi

if [ ! -f coredns/xbox-hosts ]; then
    touch coredns/xbox-hosts
fi

# Start DoH services
echo -e "${YELLOW}Starting DoH services...${NC}"
docker-compose -f docker-compose.openvpn-doh.yml up -d

sleep 5

# Check if running
if docker ps | grep -q "doh-for-openvpn"; then
    echo -e "${GREEN}✓ DoH server running${NC}"
else
    echo -e "${RED}✗ Failed to start DoH server${NC}"
    docker-compose -f docker-compose.openvpn-doh.yml logs
    exit 1
fi

# Update OpenVPN configuration
echo -e "${YELLOW}Updating OpenVPN DNS settings...${NC}"

# Backup original config
cp /etc/openvpn/server.conf /etc/openvpn/server.conf.backup.$(date +%Y%m%d)

# Remove old DNS push lines
sed -i '/push "dhcp-option DNS/d' /etc/openvpn/server.conf
sed -i '/push "redirect-gateway/d' /etc/openvpn/server.conf

# Add new DNS configuration
cat >> /etc/openvpn/server.conf << EOF

# DNS configuration (added by integrate-doh-openvpn.sh)
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $VPN_GATEWAY"
push "dhcp-option DNS 8.8.8.8"
EOF

# Restart OpenVPN to apply changes
echo -e "${YELLOW}Restarting OpenVPN...${NC}"
systemctl restart openvpn@server || systemctl restart openvpn

sleep 3

# Verify
if systemctl is-active --quiet openvpn@server || pgrep -x openvpn > /dev/null; then
    echo -e "${GREEN}✓ OpenVPN restarted successfully${NC}"
else
    echo -e "${RED}✗ OpenVPN failed to restart${NC}"
    echo "Restoring backup..."
    cp /etc/openvpn/server.conf.backup.$(date +%Y%m%d) /etc/openvpn/server.conf
    systemctl start openvpn@server
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}Integration Complete!${NC}"
echo "================================================"
echo ""
echo "Your OpenVPN now uses DoH for DNS:"
echo "  - OpenVPN clients → $VPN_GATEWAY (VPS)"
echo "  - VPS DNS → DoH → Quad9/OpenDNS"
echo "  - Bypasses ISP DNS blocking"
echo ""
echo "To use with Xbox:"
echo "  1. Download your OpenVPN client config"
echo "  2. Install on:"
echo "     - GL.iNet Router (easiest for Xbox)"
echo "     - Windows PC (share with Xbox)"
echo "     - Your router (if supported)"
echo "  3. Connect Xbox to VPN-enabled device"
echo ""
echo "Test DNS:"
echo "  dig @localhost xbox.com"
echo ""
echo "OpenVPN backup saved:"
echo "  /etc/openvpn/server.conf.backup.$(date +%Y%m%d)"
echo ""
echo "View logs:"
echo "  docker-compose -f docker-compose.openvpn-doh.yml logs -f"
echo "  tail -f /var/log/openvpn.log"
echo ""


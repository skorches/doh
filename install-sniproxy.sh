#!/bin/bash

# Install SNIProxy for Xbox/Discord traffic forwarding

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Installing SNIProxy for Xbox Traffic"
echo "================================================"
echo ""

# Stop HAProxy temporarily
echo -e "${YELLOW}[1/5] Stopping HAProxy...${NC}"
systemctl stop haproxy

# Install sniproxy
echo ""
echo -e "${YELLOW}[2/5] Installing sniproxy...${NC}"
apt-get update -qq
apt-get install -y sniproxy

# Configure sniproxy
echo ""
echo -e "${YELLOW}[3/5] Configuring sniproxy...${NC}"

cat > /etc/sniproxy.conf << 'EOF'
user daemon

pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listen 443 {
    proto tls
    table https_hosts
    
    fallback 127.0.0.1:8443
    
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

listen 80 {
    proto http
    table http_hosts
    
    access_log {
        filename /var/log/sniproxy/http_access.log
        priority notice
    }
}

table https_hosts {
    # DoH server - route to local nginx
    bypass\.440\.info$ 127.0.0.1:8443
    
    # Xbox domains - route to real servers
    .*\.xboxlive\.com$ *
    .*\.xboxservices\.com$ *
    .*\.xbox\.com$ *
    .*\.live\.com$ *
    .*\.microsoft\.com$ *
    .*\.msftncsi\.com$ *
    .*\.msftconnecttest\.com$ *
    .*\.windows\.com$ *
    .*\.msn\.com$ *
    
    # Discord domains
    .*\.discord\.com$ *
    .*\.discordapp\.com$ *
    .*\.discordapp\.net$ *
    .*\.discord\.gg$ *
    .*\.discord\.media$ *
}

table http_hosts {
    # Xbox/Microsoft HTTP traffic
    .*\.xboxlive\.com$ *
    .*\.xboxservices\.com$ *
    .*\.xbox\.com$ *
    .*\.live\.com$ *
    .*\.microsoft\.com$ *
    
    # Discord HTTP traffic
    .*\.discord\.com$ *
    .*\.discordapp\.com$ *
}
EOF

echo -e "${GREEN}✅ sniproxy configured${NC}"

# Create log directory
mkdir -p /var/log/sniproxy
chown nobody:nogroup /var/log/sniproxy

# Enable and start sniproxy
echo ""
echo -e "${YELLOW}[4/5] Starting sniproxy...${NC}"
systemctl enable sniproxy
systemctl restart sniproxy

sleep 2

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ sniproxy started${NC}"
else
    echo -e "${RED}❌ sniproxy failed to start${NC}"
    journalctl -u sniproxy -n 20 --no-pager
    exit 1
fi

# Start Docker containers (if not running)
echo ""
echo -e "${YELLOW}[5/5] Ensuring Docker containers are running...${NC}"
cd /root/doh
docker-compose up -d

echo ""
echo "================================================"
echo -e "${GREEN}✅ SNIProxy Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Services Status:"
echo "  ✅ sniproxy - Listening on ports 80 and 443"
echo "  ✅ Docker containers - DoH backend services"
echo ""
echo "Note: HAProxy has been stopped. sniproxy now handles all traffic."
echo ""
echo "Test from your PC:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Then test Xbox connection!"
echo ""
echo "================================================"


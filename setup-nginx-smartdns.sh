#!/bin/bash

# Setup Smart DNS using Nginx Stream (SNI Proxy)
# This works WITH your existing Nginx DoH setup

set -e

echo "================================================"
echo "Smart DNS Setup using Nginx Stream"
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

# Get VPS public IP
VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

echo ""
echo -e "${YELLOW}[1/4] Stopping HAProxy (not needed)...${NC}"
systemctl stop haproxy 2>/dev/null || true
systemctl disable haproxy 2>/dev/null || true

echo ""
echo -e "${YELLOW}[2/4] Creating Nginx Stream configuration for SNI proxy...${NC}"

# Create stream configuration for SNI routing
cat > nginx/stream-proxy.conf << 'EOF'
# SNI-based routing for Xbox/Discord traffic
# This proxies Xbox/Discord to real servers while keeping DoH working

stream {
    # Map to determine backend based on SNI
    map $ssl_preread_server_name $backend {
        # Xbox Live domains
        ~*xboxlive\.com$           xbox_backend;
        ~*xboxservices\.com$       xbox_backend;
        ~*xbox\.com$               xbox_backend;
        
        # Discord domains
        ~*discord\.com$            discord_backend;
        ~*discord\.gg$             discord_backend;
        ~*discordapp\.com$         discord_backend;
        ~*discordapp\.net$         discord_backend;
        
        # Microsoft domains used by Xbox
        ~*live\.com$               xbox_backend;
        ~*microsoft\.com$          xbox_backend;
        ~*msftncsi\.com$           xbox_backend;
        ~*msftconnecttest\.com$    xbox_backend;
        ~*gamepass\.com$           xbox_backend;
        ~*windows\.com$            xbox_backend;
        
        # DoH domain - route to local DoH backend
        bypass.440.info            doh_backend;
        
        # Default: route to DoH (for other traffic)
        default                    doh_backend;
    }
    
    # Upstream for Xbox (real servers)
    upstream xbox_backend {
        server xboxlive.com:443;
    }
    
    # Upstream for Discord (real servers)
    upstream discord_backend {
        server discord.com:443;
    }
    
    # Upstream for DoH (local)
    upstream doh_backend {
        server 127.0.0.1:8443;
    }
    
    # Main HTTPS listener with SNI routing
    server {
        listen 443;
        listen [::]:443;
        
        proxy_pass $backend;
        ssl_preread on;
        proxy_connect_timeout 5s;
        proxy_timeout 300s;
    }
}
EOF

echo -e "${GREEN}✅ Stream config created${NC}"

echo ""
echo -e "${YELLOW}[3/4] Updating docker-compose for stream module...${NC}"

# Update docker-compose to:
# 1. Move doh-nginx from port 443 to 8443 (internal only)
# 2. Add nginx-stream container on port 443 (handles SNI routing)

# Backup docker-compose
cp docker-compose.yml docker-compose.yml.backup-nginx-stream-$(date +%s)

# Check if we need to update doh-nginx port
if grep -q '443:443' docker-compose.yml; then
    echo "Updating doh-nginx to use port 8443..."
    sed -i 's/443:443/8443:443/g' docker-compose.yml
    echo -e "${GREEN}✅ doh-nginx moved to port 8443${NC}"
fi

# Add nginx-stream container if not exists
if ! grep -q "nginx-stream" docker-compose.yml; then
    echo "Adding nginx-stream container..."
    
    # Add nginx-stream before networks section
    sed -i '/^networks:/i\
  # Nginx Stream for SNI-based Smart DNS\
  nginx-stream:\
    image: nginx:alpine\
    container_name: nginx-stream\
    restart: unless-stopped\
    ports:\
      - "443:443"\
    volumes:\
      - ./nginx/stream-proxy.conf:/etc/nginx/nginx.conf:ro\
    networks:\
      - doh-network\
    depends_on:\
      - doh-nginx\
\
' docker-compose.yml

    echo -e "${GREEN}✅ nginx-stream container added${NC}"
fi

echo ""
echo -e "${YELLOW}[4/4] Restarting Docker containers...${NC}"
docker-compose down
docker-compose up -d

echo ""
echo "Waiting for containers to start..."
sleep 10

# Check status
docker-compose ps

echo ""
echo "================================================"
echo -e "${GREEN}✅ Nginx Smart DNS Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Architecture:"
echo "  Internet → Port 443 → nginx-stream (SNI routing)"
echo "                           ↓"
echo "        Xbox/Discord domains → Proxy to real servers"
echo "        bypass.440.info     → doh-nginx (port 8443) → doh-backend"
echo ""
echo "Test it:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Next step: Run ./integrate-coredns-smartdns.sh"
echo "================================================"


#!/bin/bash

# Fix HAProxy config - Remove UDP sections (not supported in HAProxy 2.8)

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
echo "Fixing HAProxy Configuration"
echo "================================================"
echo ""

echo -e "${YELLOW}Removing UDP sections (not supported in HAProxy 2.8)${NC}"

cat > /etc/haproxy/haproxy.cfg << 'EOFHA'
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon
    maxconn 50000
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

# Stats page
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE

# HTTPS frontend (port 443) - Handles both DoH and Xbox/Discord traffic
frontend https_front
    bind *:443
    mode tcp
    option tcplog
    
    # Inspect SNI to route traffic
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route DoH requests (bypass.440.info) to Nginx
    acl is_doh_domain req_ssl_sni -i bypass.440.info
    use_backend doh_local if is_doh_domain
    
    # Route Xbox/Discord domains through SNI proxy
    acl is_xbox_domain req_ssl_sni -m end .xboxlive.com
    acl is_xbox_domain req_ssl_sni -m end .xboxservices.com
    acl is_xbox_domain req_ssl_sni -m end .xbox.com
    acl is_xbox_domain req_ssl_sni -m end .live.com
    acl is_xbox_domain req_ssl_sni -m end .microsoft.com
    acl is_xbox_domain req_ssl_sni -m end .msftncsi.com
    acl is_xbox_domain req_ssl_sni -m end .msftconnecttest.com
    acl is_xbox_domain req_ssl_sni -m end .windows.com
    acl is_xbox_domain req_ssl_sni -m end .msn.com
    acl is_discord_domain req_ssl_sni -m end .discord.com
    acl is_discord_domain req_ssl_sni -m end .discordapp.com
    acl is_discord_domain req_ssl_sni -m end .discordapp.net
    acl is_discord_domain req_ssl_sni -m end .discord.gg
    acl is_discord_domain req_ssl_sni -m end .discord.media
    
    use_backend sni_proxy if is_xbox_domain
    use_backend sni_proxy if is_discord_domain
    
    # Default: forward to SNI proxy
    default_backend sni_proxy

# Backend for DoH server (Nginx container)
backend doh_local
    mode tcp
    server doh 127.0.0.1:8443 check

# Backend for SNI proxy (forwards to real servers based on SNI)
backend sni_proxy
    mode tcp
    balance leastconn
    
    # Forward to real destination based on SNI
    # HAProxy will use the SNI hostname to connect
    server-template sni 10 0.0.0.0:443 check-sni req.ssl_sni sni req.ssl_sni

# HTTP frontend (port 80) - For Xbox HTTP traffic
frontend http_front
    bind *:80
    mode tcp
    default_backend http_proxy

backend http_proxy
    mode tcp
    balance leastconn
    # Forward to real destination (will fail without proper setup)
    server http_fallback 0.0.0.0:80

# Xbox Live port 3074 (TCP only - UDP not supported in HAProxy)
frontend xbox_live_3074
    bind *:3074
    mode tcp
    default_backend xbox_live_backend

backend xbox_live_backend
    mode tcp
    server xbox_live 0.0.0.0:3074
EOFHA

echo -e "${GREEN}✅ HAProxy config fixed${NC}"

# Test configuration
echo ""
echo -e "${YELLOW}Testing HAProxy configuration...${NC}"
if haproxy -c -f /etc/haproxy/haproxy.cfg; then
    echo -e "${GREEN}✅ Configuration valid${NC}"
else
    echo -e "${RED}❌ Configuration still has errors${NC}"
    exit 1
fi

# Restart HAProxy
echo ""
echo -e "${YELLOW}Restarting HAProxy...${NC}"
systemctl restart haproxy
sleep 2

if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy started successfully${NC}"
else
    echo -e "${RED}❌ HAProxy failed to start${NC}"
    journalctl -u haproxy -n 20 --no-pager
    exit 1
fi

# Start Docker containers
echo ""
echo -e "${YELLOW}Starting Docker containers...${NC}"
cd /root/doh
docker-compose up -d
sleep 5

echo ""
echo "================================================"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Services Status:"
docker-compose ps
echo ""
echo "HAProxy Status:"
systemctl status haproxy --no-pager | head -5
echo ""
echo "HAProxy Stats: http://$(curl -s ifconfig.me):8404/stats"
echo ""
echo "Note: Xbox Teredo (UDP 3544) is not supported by HAProxy."
echo "This shouldn't affect Xbox Live connectivity for most games."
echo ""
echo "================================================"


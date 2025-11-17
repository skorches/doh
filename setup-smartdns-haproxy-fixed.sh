#!/bin/bash

# Setup Smart DNS with HAProxy (Fixed version)
# Moves DoH to internal port, HAProxy handles all port 443 traffic

set -e

echo "================================================"
echo "Smart DNS Setup with HAProxy (Fixed)"
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

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

echo ""
echo -e "${YELLOW}[1/5] Stopping containers and HAProxy...${NC}"
docker-compose down
systemctl stop haproxy 2>/dev/null || true

echo ""
echo -e "${YELLOW}[2/5] Updating docker-compose (move Nginx to port 8443)...${NC}"

# Backup
cp docker-compose.yml docker-compose.yml.backup-haproxy-fixed-$(date +%s)

# Change doh-nginx port from 443 to 8443 (internal only)
sed -i 's/"443:443"/"8443:443"/g' docker-compose.yml
sed -i 's/- 443:443/- 8443:443/g' docker-compose.yml

echo -e "${GREEN}✅ doh-nginx now on port 8443 (internal)${NC}"

echo ""
echo -e "${YELLOW}[3/5] Installing and configuring HAProxy...${NC}"

apt-get update -qq
apt-get install -y haproxy

# Create HAProxy config
cat > /etc/haproxy/haproxy.cfg << 'EOFHAPROXY'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
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
    stats refresh 30s

# Main HTTPS frontend (port 443)
frontend https_front
    bind *:443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route to DoH backend if SNI is bypass.440.info
    use_backend doh_local if { req_ssl_sni -i bypass.440.info }
    
    # Route Xbox/Discord to proxy backends
    use_backend xbox_proxy if { req_ssl_sni -m end xboxlive.com }
    use_backend xbox_proxy if { req_ssl_sni -m end xboxservices.com }
    use_backend xbox_proxy if { req_ssl_sni -m end xbox.com }
    use_backend xbox_proxy if { req_ssl_sni -m end live.com }
    use_backend xbox_proxy if { req_ssl_sni -m end microsoft.com }
    use_backend xbox_proxy if { req_ssl_sni -m end msftncsi.com }
    use_backend xbox_proxy if { req_ssl_sni -m end msftconnecttest.com }
    use_backend xbox_proxy if { req_ssl_sni -m end gamepass.com }
    use_backend xbox_proxy if { req_ssl_sni -m end windows.com }
    
    use_backend discord_proxy if { req_ssl_sni -m end discord.com }
    use_backend discord_proxy if { req_ssl_sni -m end discord.gg }
    use_backend discord_proxy if { req_ssl_sni -m end discordapp.com }
    use_backend discord_proxy if { req_ssl_sni -m end discordapp.net }
    use_backend discord_proxy if { req_ssl_sni -m end discord.media }
    
    # Default: pass through
    default_backend doh_local

# Backend: Local DoH (Nginx on port 8443)
backend doh_local
    mode tcp
    server doh 127.0.0.1:8443 check

# Backend: Xbox Live (proxy to real servers)
backend xbox_proxy
    mode tcp
    balance roundrobin
    server-template xbox 5 xboxlive.com:443 check resolvers dns_resolvers resolve-prefer ipv4

# Backend: Discord (proxy to real servers)  
backend discord_proxy
    mode tcp
    balance roundrobin
    server-template discord 5 discord.com:443 check resolvers dns_resolvers resolve-prefer ipv4

# DNS resolver for dynamic backends
resolvers dns_resolvers
    nameserver dns1 1.1.1.1:53
    nameserver dns2 8.8.8.8:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold valid 10s
EOFHAPROXY

echo -e "${GREEN}✅ HAProxy configured${NC}"

echo ""
echo -e "${YELLOW}[4/5] Starting services...${NC}"

# Start Docker first
docker-compose up -d

# Wait for doh-nginx
sleep 5

# Start HAProxy
systemctl enable haproxy
systemctl restart haproxy

sleep 3

# Check status
if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy is running${NC}"
else
    echo -e "${RED}❌ HAProxy failed to start${NC}"
    echo "Checking logs..."
    journalctl -xeu haproxy -n 20
    exit 1
fi

echo ""
echo -e "${YELLOW}[5/5] Verifying setup...${NC}"

# Test DoH still works
echo "Testing DoH..."
curl -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A' > /dev/null && echo -e "${GREEN}✅ DoH working${NC}" || echo -e "${RED}❌ DoH not responding${NC}"

echo ""
echo "================================================"
echo -e "${GREEN}✅ Smart DNS with HAProxy Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Architecture:"
echo "  Port 443 → HAProxy (SNI routing)"
echo "              ↓"
echo "    bypass.440.info → Nginx:8443 → doh-backend (DoH)"
echo "    xboxlive.com    → Proxy → Real Xbox servers"
echo "    discord.com     → Proxy → Real Discord servers"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo ""
echo "Next step: Run ./integrate-coredns-smartdns.sh"
echo "================================================"


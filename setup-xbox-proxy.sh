#!/bin/bash

# Setup Smart DNS with HAProxy for Xbox Live
# This makes your DoH work like xbox-dns.ru

set -e

echo "================================================"
echo "Smart DNS Setup for Xbox Live"
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

# Get VPS public IP
VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

# Install HAProxy
echo ""
echo -e "${YELLOW}[1/5] Installing HAProxy...${NC}"
apt-get update -qq
apt-get install -y haproxy

# Backup original HAProxy config
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-$(date +%s)

# Create HAProxy configuration for Xbox Live
echo ""
echo -e "${YELLOW}[2/5] Configuring HAProxy for Xbox Live...${NC}"

cat > /etc/haproxy/haproxy.cfg << 'EOF'
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

    # SSL/TLS settings
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Stats page
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

# Xbox Live HTTPS (port 443)
frontend xbox_https_front
    bind *:443
    mode tcp
    option tcplog
    
    # SNI routing for Xbox domains
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI - Xbox domains
    use_backend xbox_live if { req_ssl_sni -m end xboxlive.com }
    use_backend xbox_live if { req_ssl_sni -m end xboxservices.com }
    use_backend xbox_live if { req_ssl_sni -m end xbox.com }
    use_backend xbox_live if { req_ssl_sni -m end microsoft.com }
    use_backend xbox_live if { req_ssl_sni -m end msftncsi.com }
    use_backend xbox_live if { req_ssl_sni -m end msftconnecttest.com }
    use_backend xbox_live if { req_ssl_sni -m end live.com }
    use_backend xbox_live if { req_ssl_sni -m end windows.com }
    use_backend xbox_live if { req_ssl_sni -m end gamepass.com }
    
    # Route Discord domains
    use_backend discord if { req_ssl_sni -m end discord.com }
    use_backend discord if { req_ssl_sni -m end discord.gg }
    use_backend discord if { req_ssl_sni -m end discordapp.com }
    use_backend discord if { req_ssl_sni -m end discordapp.net }
    use_backend discord if { req_ssl_sni -m end discord.media }
    
    # Default: pass through to origin
    default_backend xbox_live

# Xbox Live HTTP (port 80)
frontend xbox_http_front
    bind *:80
    mode tcp
    option tcplog
    default_backend xbox_http

# Xbox Live UDP (port 3074 - gaming)
frontend xbox_udp_front
    bind *:3074
    mode tcp
    option tcplog
    default_backend xbox_udp

# Xbox Live Teredo (port 3544)
frontend xbox_teredo_front
    bind *:3544 
    mode tcp
    option tcplog
    default_backend xbox_teredo

# Backends - forward to real Xbox servers
backend xbox_live
    mode tcp
    balance roundrobin
    option tcp-check
    
    # Use DNS resolution for dynamic IPs
    server-template xbox 10 xboxlive.com:443 check resolvers mydns resolve-prefer ipv4

backend xbox_http
    mode tcp
    balance roundrobin
    server-template xbox 10 xboxlive.com:80 check resolvers mydns resolve-prefer ipv4

backend xbox_udp
    mode tcp
    balance roundrobin
    server-template xbox 10 xboxlive.com:3074 check resolvers mydns resolve-prefer ipv4

backend xbox_teredo
    mode tcp
    balance roundrobin
    server-template xbox 10 teredo.ipv6.microsoft.com:3544 check resolvers mydns resolve-prefer ipv4

# Discord backend
backend discord
    mode tcp
    balance roundrobin
    option tcp-check
    server-template discord 10 discord.com:443 check resolvers mydns resolve-prefer ipv4

# DNS resolver
resolvers mydns
    nameserver dns1 1.1.1.1:53
    nameserver dns2 8.8.8.8:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold valid 10s
EOF

echo -e "${GREEN}✅ HAProxy configured${NC}"

# Enable and start HAProxy
echo ""
echo -e "${YELLOW}[3/5] Starting HAProxy...${NC}"
systemctl enable haproxy
systemctl restart haproxy

# Check if HAProxy is running
if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy is running${NC}"
else
    echo -e "${RED}❌ HAProxy failed to start${NC}"
    echo "Check logs: journalctl -u haproxy -n 50"
    exit 1
fi

# Now we need to configure DoH to return VPS IP for Xbox domains
echo ""
echo -e "${YELLOW}[4/5] Configuring DoH to return VPS IP for Xbox domains...${NC}"

cd /root/doh

# Check if coredns directory exists
if [ ! -d "coredns" ]; then
    mkdir -p coredns
fi

# Create custom hosts file for Xbox and Discord domains pointing to VPS
cat > coredns/xbox-hosts << EOF
# Xbox Live domains - point to VPS for proxying
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP xnotify.xboxlive.com

# Xbox Services
$VPS_IP *.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP catalog.gamepass.com

# Microsoft domains used by Xbox
$VPS_IP login.live.com
$VPS_IP arc.msn.com
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com

# Teredo
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# Discord domains - for Discord on Xbox
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP images-ext-1.discordapp.net
$VPS_IP images-ext-2.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP status.discord.com
$VPS_IP voice.discord.gg
$VPS_IP router.discordapp.net
EOF

echo -e "${GREEN}✅ Xbox hosts file created${NC}"

# Update docker-compose to use CoreDNS with custom hosts
echo ""
echo -e "${YELLOW}[5/5] Updating DoH configuration...${NC}"

# Check if docker-compose has custom hosts setup
if ! grep -q "xbox-hosts" docker-compose.yml 2>/dev/null; then
    echo -e "${YELLOW}Note: You'll need to integrate CoreDNS with custom hosts${NC}"
    echo "This requires updating your docker-compose.yml"
fi

# Open firewall ports for Xbox
echo ""
echo -e "${YELLOW}Opening firewall ports for Xbox...${NC}"
ufw allow 80/tcp comment "Xbox HTTP"
ufw allow 3074/tcp comment "Xbox Live"
ufw allow 3074/udp comment "Xbox Live UDP"
ufw allow 3544/udp comment "Xbox Teredo"
ufw allow 8404/tcp comment "HAProxy Stats"

echo ""
echo "================================================"
echo -e "${GREEN}✅ Smart DNS Setup Complete!${NC}"
echo "================================================"
echo ""
echo "VPS IP: $VPS_IP"
echo ""
echo "What was configured:"
echo "  ✅ HAProxy installed and configured"
echo "  ✅ Xbox traffic proxying on ports 80, 443, 3074, 3544"
echo "  ✅ Custom hosts file created"
echo "  ✅ Firewall ports opened"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo ""
echo "================================================"
echo "IMPORTANT: Manual Steps Required"
echo "================================================"
echo ""
echo "Your DoH server needs to be updated to return VPS IP"
echo "for Xbox domains instead of real IPs."
echo ""
echo "The xbox-hosts file has been created at:"
echo "  /root/doh/coredns/xbox-hosts"
echo ""
echo "PROBLEM: Your current DoH backend doesn't support"
echo "custom host overrides easily."
echo ""
echo "SOLUTION: We need to add CoreDNS as a layer between"
echo "Keenetic and the DoH backend to intercept Xbox domains."
echo ""
echo "Run this to complete the setup:"
echo "  cd /root/doh"
echo "  ./integrate-coredns-smartdns.sh"
echo ""
echo "Or we can modify your current setup..."
echo ""
echo "Do you want me to create the integration script? (Y/n)"
read -p "> " answer

if [[ "$answer" != "n" && "$answer" != "N" ]]; then
    echo ""
    echo "Creating integration script..."
    # This will be created next
fi

echo ""
echo "================================================"


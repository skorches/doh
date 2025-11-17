#!/bin/bash

# Add Discord support to Smart DNS
# This allows Discord on Xbox to bypass blocks

set -e

echo "================================================"
echo "Add Discord to Smart DNS"
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

# Add Discord domains to hosts file
echo ""
echo -e "${YELLOW}[1/4] Adding Discord domains...${NC}"

if [ ! -f "coredns/xbox-hosts" ]; then
    echo -e "${RED}Error: xbox-hosts file not found!${NC}"
    echo "Run ./setup-xbox-proxy.sh first"
    exit 1
fi

# Add Discord domains if not already present
if ! grep -q "discord.com" coredns/xbox-hosts; then
    cat >> coredns/xbox-hosts << EOFDISCORD

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
EOFDISCORD

    echo -e "${GREEN}✅ Discord domains added to hosts file${NC}"
else
    echo -e "${YELLOW}Discord domains already in hosts file${NC}"
fi

# Update HAProxy configuration
echo ""
echo -e "${YELLOW}[2/4] Updating HAProxy for Discord...${NC}"

# Backup current config
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-discord-$(date +%s)

# Add Discord SNI routing to the frontend section
if ! grep -q "discord.com" /etc/haproxy/haproxy.cfg; then
    # Add Discord routing after Xbox routing
    sed -i '/use_backend xbox_live if { req_ssl_sni -m end gamepass.com }/a\    \n    # Discord domains\n    use_backend discord if { req_ssl_sni -m end discord.com }\n    use_backend discord if { req_ssl_sni -m end discord.gg }\n    use_backend discord if { req_ssl_sni -m end discordapp.com }\n    use_backend discord if { req_ssl_sni -m end discordapp.net }\n    use_backend discord if { req_ssl_sni -m end discord.media }' /etc/haproxy/haproxy.cfg
    
    # Add Discord backend before resolvers section
    sed -i '/# DNS resolver/i\
# Discord backend\
backend discord\
    mode tcp\
    balance roundrobin\
    option tcp-check\
    server-template discord 10 discord.com:443 check resolvers mydns resolve-prefer ipv4\
\n' /etc/haproxy/haproxy.cfg

    echo -e "${GREEN}✅ HAProxy configured for Discord${NC}"
else
    echo -e "${YELLOW}Discord already in HAProxy config${NC}"
fi

# Restart HAProxy
echo ""
echo -e "${YELLOW}[3/4] Restarting HAProxy...${NC}"
systemctl restart haproxy

if systemctl is-active --quiet haproxy; then
    echo -e "${GREEN}✅ HAProxy restarted successfully${NC}"
else
    echo -e "${RED}❌ HAProxy failed to start${NC}"
    echo "Restoring backup..."
    cp /etc/haproxy/haproxy.cfg.backup-discord-* /etc/haproxy/haproxy.cfg
    systemctl restart haproxy
    exit 1
fi

# Restart Docker containers to reload hosts file
echo ""
echo -e "${YELLOW}[4/4] Restarting Docker containers...${NC}"
docker-compose restart coredns-smartdns

echo ""
echo "================================================"
echo -e "${GREEN}✅ Discord Support Added!${NC}"
echo "================================================"
echo ""
echo "Discord domains now point to: $VPS_IP"
echo ""
echo "Configured domains:"
echo "  ✅ discord.com"
echo "  ✅ discord.gg"
echo "  ✅ discordapp.com"
echo "  ✅ discordapp.net"
echo "  ✅ discord.media"
echo "  ✅ gateway.discord.gg"
echo "  ✅ cdn.discordapp.com"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo ""
echo "Test Discord DNS:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=discord.com&type=A'"
echo ""
echo "Should return: $VPS_IP"
echo ""
echo "Now Discord on Xbox should work!"
echo "================================================"


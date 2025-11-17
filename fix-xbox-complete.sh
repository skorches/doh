#!/bin/bash

# Complete Xbox fix - ensure all Xbox domains and ports are covered

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
echo "Complete Xbox Fix"
echo "================================================"
echo ""

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

# Step 1: Add ALL Xbox domains (comprehensive list)
echo ""
echo -e "${YELLOW}[1/4] Updating xbox-hosts with comprehensive domain list...${NC}"

cat > coredns/xbox-hosts << EOFHOSTS
# === XBOX AUTHENTICATION ===
$VPS_IP auth.xboxlive.com
$VPS_IP device.auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP sisu.xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP xboxlive.com

# === XBOX SERVICES ===
$VPS_IP notify.xboxlive.com
$VPS_IP xnotify.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP settings.xboxlive.com
$VPS_IP profile.xboxlive.com
$VPS_IP presence.xboxlive.com
$VPS_IP social.xboxlive.com
$VPS_IP achievements.xboxlive.com
$VPS_IP leaderboards.xboxlive.com
$VPS_IP stats.xboxlive.com
$VPS_IP friends.xboxlive.com
$VPS_IP messaging.xboxlive.com
$VPS_IP parties.xboxlive.com
$VPS_IP matchmaking.xboxlive.com
$VPS_IP multiplayer.xboxlive.com

# === XBOX SERVICES DOMAINS ===
$VPS_IP xboxservices.com
$VPS_IP www.xboxservices.com
$VPS_IP activity.xboxservices.com
$VPS_IP contentaccess.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP licensing.xboxservices.com
$VPS_IP catalog.xboxservices.com

# === GAME PASS ===
$VPS_IP gamepass.com
$VPS_IP www.gamepass.com
$VPS_IP catalog.gamepass.com
$VPS_IP storeedgefd.dsx.mp.microsoft.com

# === XBOX.COM ===
$VPS_IP xbox.com
$VPS_IP www.xbox.com
$VPS_IP account.xbox.com
$VPS_IP profile.xbox.com
$VPS_IP live.xbox.com

# === MICROSOFT LOGIN ===
$VPS_IP login.live.com
$VPS_IP account.live.com
$VPS_IP login.microsoftonline.com
$VPS_IP account.microsoft.com

# === MICROSOFT NETWORK CHECKS ===
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftncsi.com
$VPS_IP ipv6.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com

# === OTHER MICROSOFT ===
$VPS_IP arc.msn.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com
$VPS_IP v10.vortex-win.data.microsoft.com
$VPS_IP v20.vortex-win.data.microsoft.com
$VPS_IP telecommand.telemetry.microsoft.com

# === TEREDO (IPv6 tunneling) ===
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# === DISCORD (for Xbox Discord app) ===
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
EOFHOSTS

echo -e "${GREEN}✅ xbox-hosts updated ($(wc -l < coredns/xbox-hosts) domains)${NC}"

# Step 2: Update sniproxy to handle more Xbox domains
echo ""
echo -e "${YELLOW}[2/4] Updating sniproxy configuration...${NC}"

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
    
    # Xbox domains - route to real servers (wildcard match)
    .*\.xboxlive\.com$ *
    .*\.xboxservices\.com$ *
    .*\.xbox\.com$ *
    .*\.live\.com$ *
    .*\.microsoft\.com$ *
    .*\.microsoftonline\.com$ *
    .*\.msftncsi\.com$ *
    .*\.msftconnecttest\.com$ *
    .*\.windows\.com$ *
    .*\.msn\.com$ *
    .*\.gamepass\.com$ *
    
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
    .*\.gamepass\.com$ *
    
    # Discord HTTP traffic
    .*\.discord\.com$ *
    .*\.discordapp\.com$ *
}
EOF

echo -e "${GREEN}✅ sniproxy configuration updated${NC}"

# Step 3: Restart services
echo ""
echo -e "${YELLOW}[3/4] Restarting services...${NC}"
systemctl restart sniproxy
docker-compose restart coredns-smartdns

sleep 3

# Step 4: Verify
echo ""
echo -e "${YELLOW}[4/4] Verifying setup...${NC}"

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ sniproxy running${NC}"
else
    echo -e "${RED}❌ sniproxy not running${NC}"
    exit 1
fi

if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS running${NC}"
else
    echo -e "${RED}❌ CoreDNS not running${NC}"
    exit 1
fi

# Test
echo ""
echo "Testing Smart DNS:"
RESULT=$(curl -s -H 'accept: application/dns-json' 'http://localhost:8053/dns-query?name=xboxlive.com&type=A')
if echo "$RESULT" | grep -q "$VPS_IP"; then
    echo -e "${GREEN}✅ xboxlive.com resolves to VPS IP${NC}"
else
    echo -e "${RED}❌ xboxlive.com resolution failed${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Important: Make sure Xbox is using Keenetic's DNS!"
echo ""
echo "On Xbox:"
echo "  Settings → Network → Advanced Settings → DNS Settings"
echo "  Should be 'Automatic' (uses router DNS)"
echo ""
echo "On Keenetic:"
echo "  Internet → DNS → Use DNS over HTTPS (DoH)"
echo "  URL: https://bypass.440.info/dns-query"
echo ""
echo "Then test Xbox network connection!"
echo ""
echo "================================================"


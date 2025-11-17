#!/bin/bash

# Fix Xbox stability issues - improve timeouts and connection handling

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
echo "Fixing Xbox Stability Issues"
echo "================================================"
echo ""

cd /root/doh

# Step 1: Improve sniproxy config with better timeouts
echo -e "${YELLOW}[1/3] Updating sniproxy with better timeouts...${NC}"

cat > /etc/sniproxy.conf << 'EOF'
user daemon

pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

# Increase timeouts for long-lived connections
resolver {
    nameserver 8.8.8.8
    mode ipv4_only
}

listen 443 {
    proto tls
    table https_hosts
    
    fallback 127.0.0.1:8443
    
    # Increase timeouts for Xbox long connections
    timeout connect 10s
    timeout client 300s
    timeout server 300s
    
    access_log {
        filename /var/log/sniproxy/https_access.log
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
    .*\.xboxgamepass\.com$ *
    
    # Discord domains
    .*\.discord\.com$ *
    .*\.discordapp\.com$ *
    .*\.discordapp\.net$ *
    .*\.discord\.gg$ *
    .*\.discord\.media$ *
}
EOF

echo -e "${GREEN}✅ sniproxy config updated${NC}"

# Step 2: Add more Xbox domains that might be missing
echo ""
echo -e "${YELLOW}[2/3] Adding additional Xbox domains...${NC}"

VPS_IP=$(curl -4 -s ifconfig.me)

# Append additional domains that Xbox might use
cat >> coredns/xbox-hosts << EOFHOSTS

# Additional Xbox domains for stability
$VPS_IP xboxgamepass.com
$VPS_IP www.xboxgamepass.com
$VPS_IP edfs.xboxlive.com
$VPS_IP eds.xboxlive.com
$VPS_IP eeds.xboxlive.com
$VPS_IP ees.xboxlive.com
$VPS_IP licensing.xboxlive.com
$VPS_IP licensing.mp.microsoft.com
$VPS_IP licensing.xboxservices.com
$VPS_IP catalogservice.xboxlive.com
$VPS_IP catalogservice.xboxservices.com
$VPS_IP storeedgefd.dsx.mp.microsoft.com
$VPS_IP displaycatalog.mp.microsoft.com
$VPS_IP purchase.mp.microsoft.com
$VPS_IP commerce.xboxlive.com
$VPS_IP commerce.xboxservices.com
$VPS_IP pdp.xboxlive.com
$VPS_IP pdp.xboxservices.com
$VPS_IP rta.xboxlive.com
$VPS_IP rta.xboxservices.com
$VPS_IP rta.xbox.com
$VPS_IP telemetry.xboxlive.com
$VPS_IP telemetry.xboxservices.com
$VPS_IP telemetry.xbox.com
$VPS_IP v10.vortex-win.data.microsoft.com
$VPS_IP v20.vortex-win.data.microsoft.com
$VPS_IP telecommand.telemetry.microsoft.com
$VPS_IP clientconfig.passport.net
$VPS_IP client.wns.windows.com
$VPS_IP wns.notify.windows.com
$VPS_IP wns2-bn3p.notify.windows.com.akadns.net
$VPS_IP wns2-bn3p.notify.windows.com
$VPS_IP wns2-bn4p.notify.windows.com.akadns.net
$VPS_IP wns2-bn4p.notify.windows.com
$VPS_IP wns2-bn5p.notify.windows.com.akadns.net
$VPS_IP wns2-bn5p.notify.windows.com
$VPS_IP wns2-bn6p.notify.windows.com.akadns.net
$VPS_IP wns2-bn6p.notify.windows.com
$VPS_IP wns2-bn7p.notify.windows.com.akadns.net
$VPS_IP wns2-bn7p.notify.windows.com
$VPS_IP wns2-bn8p.notify.windows.com.akadns.net
$VPS_IP wns2-bn8p.notify.windows.com
$VPS_IP wns2-bn9p.notify.windows.com.akadns.net
$VPS_IP wns2-bn9p.notify.windows.com
$VPS_IP wns2-bn10p.notify.windows.com.akadns.net
$VPS_IP wns2-bn10p.notify.windows.com
$VPS_IP wns2-bn11p.notify.windows.com.akadns.net
$VPS_IP wns2-bn11p.notify.windows.com
$VPS_IP wns2-bn12p.notify.windows.com.akadns.net
$VPS_IP wns2-bn12p.notify.windows.com
$VPS_IP wns2-bn13p.notify.windows.com.akadns.net
$VPS_IP wns2-bn13p.notify.windows.com
$VPS_IP wns2-bn14p.notify.windows.com.akadns.net
$VPS_IP wns2-bn14p.notify.windows.com
$VPS_IP wns2-bn15p.notify.windows.com.akadns.net
$VPS_IP wns2-bn15p.notify.windows.com
$VPS_IP wns2-bn16p.notify.windows.com.akadns.net
$VPS_IP wns2-bn16p.notify.windows.com
$VPS_IP wns2-bn17p.notify.windows.com.akadns.net
$VPS_IP wns2-bn17p.notify.windows.com
$VPS_IP wns2-bn18p.notify.windows.com.akadns.net
$VPS_IP wns2-bn18p.notify.windows.com
$VPS_IP wns2-bn19p.notify.windows.com.akadns.net
$VPS_IP wns2-bn19p.notify.windows.com
$VPS_IP wns2-bn20p.notify.windows.com.akadns.net
$VPS_IP wns2-bn20p.notify.windows.com
$VPS_IP wns2-bn21p.notify.windows.com.akadns.net
$VPS_IP wns2-bn21p.notify.windows.com
$VPS_IP wns2-bn22p.notify.windows.com.akadns.net
$VPS_IP wns2-bn22p.notify.windows.com
$VPS_IP wns2-bn23p.notify.windows.com.akadns.net
$VPS_IP wns2-bn23p.notify.windows.com
$VPS_IP wns2-bn24p.notify.windows.com.akadns.net
$VPS_IP wns2-bn24p.notify.windows.com
$VPS_IP wns2-bn25p.notify.windows.com.akadns.net
$VPS_IP wns2-bn25p.notify.windows.com
$VPS_IP wns2-bn26p.notify.windows.com.akadns.net
$VPS_IP wns2-bn26p.notify.windows.com
$VPS_IP wns2-bn27p.notify.windows.com.akadns.net
$VPS_IP wns2-bn27p.notify.windows.com
$VPS_IP wns2-bn28p.notify.windows.com.akadns.net
$VPS_IP wns2-bn28p.notify.windows.com
$VPS_IP wns2-bn29p.notify.windows.com.akadns.net
$VPS_IP wns2-bn29p.notify.windows.com
$VPS_IP wns2-bn30p.notify.windows.com.akadns.net
$VPS_IP wns2-bn30p.notify.windows.com
$VPS_IP wns2-bn31p.notify.windows.com.akadns.net
$VPS_IP wns2-bn31p.notify.windows.com
$VPS_IP wns2-bn32p.notify.windows.com.akadns.net
$VPS_IP wns2-bn32p.notify.windows.com
$VPS_IP wns2-bn33p.notify.windows.com.akadns.net
$VPS_IP wns2-bn33p.notify.windows.com
$VPS_IP wns2-bn34p.notify.windows.com.akadns.net
$VPS_IP wns2-bn34p.notify.windows.com
$VPS_IP wns2-bn35p.notify.windows.com.akadns.net
$VPS_IP wns2-bn35p.notify.windows.com
$VPS_IP wns2-bn36p.notify.windows.com.akadns.net
$VPS_IP wns2-bn36p.notify.windows.com
$VPS_IP wns2-bn37p.notify.windows.com.akadns.net
$VPS_IP wns2-bn37p.notify.windows.com
$VPS_IP wns2-bn38p.notify.windows.com.akadns.net
$VPS_IP wns2-bn38p.notify.windows.com
$VPS_IP wns2-bn39p.notify.windows.com.akadns.net
$VPS_IP wns2-bn39p.notify.windows.com
$VPS_IP wns2-bn40p.notify.windows.com.akadns.net
$VPS_IP wns2-bn40p.notify.windows.com
$VPS_IP wns2-bn41p.notify.windows.com.akadns.net
$VPS_IP wns2-bn41p.notify.windows.com
$VPS_IP wns2-bn42p.notify.windows.com.akadns.net
$VPS_IP wns2-bn42p.notify.windows.com
$VPS_IP wns2-bn43p.notify.windows.com.akadns.net
$VPS_IP wns2-bn43p.notify.windows.com
$VPS_IP wns2-bn44p.notify.windows.com.akadns.net
$VPS_IP wns2-bn44p.notify.windows.com
$VPS_IP wns2-bn45p.notify.windows.com.akadns.net
$VPS_IP wns2-bn45p.notify.windows.com
$VPS_IP wns2-bn46p.notify.windows.com.akadns.net
$VPS_IP wns2-bn46p.notify.windows.com
$VPS_IP wns2-bn47p.notify.windows.com.akadns.net
$VPS_IP wns2-bn47p.notify.windows.com
$VPS_IP wns2-bn48p.notify.windows.com.akadns.net
$VPS_IP wns2-bn48p.notify.windows.com
$VPS_IP wns2-bn49p.notify.windows.com.akadns.net
$VPS_IP wns2-bn49p.notify.windows.com
$VPS_IP wns2-bn50p.notify.windows.com.akadns.net
$VPS_IP wns2-bn50p.notify.windows.com
EOFHOSTS

echo -e "${GREEN}✅ Additional Xbox domains added ($(wc -l < coredns/xbox-hosts) total domains)${NC}"

# Step 3: Restart services
echo ""
echo -e "${YELLOW}[3/3] Restarting services...${NC}"

# Kill old sniproxy
pkill -9 sniproxy 2>/dev/null || true
sleep 2

# Restart sniproxy
systemctl restart sniproxy
sleep 2

# Restart CoreDNS
docker-compose restart coredns-smartdns
sleep 3

# Verify
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ sniproxy running on port 443${NC}"
else
    echo -e "${RED}❌ sniproxy not running${NC}"
    systemctl status sniproxy --no-pager | head -10
fi

if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS running${NC}"
else
    echo -e "${RED}❌ CoreDNS not running${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Stability Fixes Applied!${NC}"
echo "================================================"
echo ""
echo "Improvements:"
echo "  ✅ Increased connection timeouts (300s)"
echo "  ✅ Added 100+ additional Xbox domains"
echo "  ✅ Improved sniproxy stability"
echo ""
echo "Test Xbox again - it should be more stable now!"
echo ""
echo "================================================"


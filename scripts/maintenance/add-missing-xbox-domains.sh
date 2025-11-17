#!/bin/bash

# Add missing Xbox domains from Wireshark analysis

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh

VPS_IP=$(curl -4 -s ifconfig.me)

echo "================================================"
echo "Adding Missing Xbox Domains"
echo "================================================"
echo ""

# Domains from Wireshark analysis that are likely missing
MISSING_DOMAINS="accounts.xboxlive.com
achievements.xboxlive.com
aqua.xboxservices.com
assets1.xboxlive.com
avty.xboxlive.com
clubhub.xboxlive.com
cms-assets.xboxservices.com
collections.md.mp.microsoft.com
collections.mp.microsoft.com
comments.xboxlive.com
continuum.dds.microsoft.com
ctldl.windowsupdate.com
dlassets-ssl.xboxlive.com
eplists.xboxlive.com
fe3cr.delivery.mp.microsoft.com
licensing.mp.microsoft.com
mediahub.xboxlive.com
notificationinbox.xboxlive.com
notifier.xboxlive.com
packages.xboxlive.com
peoplehub.xboxlive.com
plaid.xboxservices.com
privacy.xboxlive.com
rta.xboxlive.com
sessiondirectory.xboxlive.com
settings-win.data.microsoft.com
silver.xboxservices.com
slscr.update.microsoft.com
social.xboxlive.com
store-images.s-microsoft.com
streaming.xboxlive.com
titlehub.xboxlive.com
title.mgt.xboxlive.com
titlestoragewus0505.blob.core.windows.net
titlestorage.xboxlive.com
update.xboxlive.com
userpresence.xboxlive.com
userstats.xboxlive.com
usertitles.xboxlive.com
v10.events.data.microsoft.com
v20.events.data.microsoft.com
www.xboxab.com
xbaccessories-bhf7bsbfgxdpbrg4.b02.azurefd.net
xblmessaging.xboxlive.com
xgrant.xboxlive.com"

# Check existing domains
EXISTING=$(cat coredns/xbox-hosts 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{print $2}' | sort -u)

# Add missing domains
echo -e "${YELLOW}Checking and adding missing domains...${NC}"

ADDED=0
echo "" >> coredns/xbox-hosts
echo "# === ADDITIONAL XBOX DOMAINS (from Wireshark) ===" >> coredns/xbox-hosts
echo "# Added: $(date)" >> coredns/xbox-hosts

while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        if ! echo "$EXISTING" | grep -q "^${domain}$"; then
            echo "$VPS_IP $domain" >> coredns/xbox-hosts
            ADDED=$((ADDED + 1))
        fi
    fi
done <<< "$MISSING_DOMAINS"

echo -e "${GREEN}✅ Added $ADDED new domains${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns
sleep 3

echo ""
echo "================================================"
echo -e "${GREEN}✅ Complete!${NC}"
echo "================================================"
echo ""
echo "Total domains: $(wc -l < coredns/xbox-hosts)"
echo ""
echo "Test again:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=accounts.xboxlive.com&type=A'"
echo ""
echo "Should now return VPS IP ($VPS_IP)"
echo ""
echo "================================================"


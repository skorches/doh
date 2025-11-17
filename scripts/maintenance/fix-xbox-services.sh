#!/bin/bash

# Fix Xbox services issues - improve SNIProxy and add missing domains

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
echo "Fixing Xbox Services Issues"
echo "================================================"
echo ""

cd /root/doh

VPS_IP=$(curl -4 -s ifconfig.me)

# Step 1: Add more Xbox domains
echo -e "${YELLOW}[1/3] Adding missing Xbox service domains...${NC}"

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
social.xboxlive.com
store-images.s-microsoft.com
streaming.xboxlive.com
titlehub.xboxlive.com
title.mgt.xboxlive.com
titlestorage.xboxlive.com
update.xboxlive.com
userpresence.xboxlive.com
userstats.xboxlive.com
usertitles.xboxlive.com
v10.events.data.microsoft.com
v20.events.data.microsoft.com
www.xboxab.com
xblmessaging.xboxlive.com
xgrant.xboxlive.com"

EXISTING=$(cat coredns/xbox-hosts 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{print $2}' | sort -u)

echo "" >> coredns/xbox-hosts
echo "# === ADDITIONAL XBOX SERVICE DOMAINS ===" >> coredns/xbox-hosts
echo "# Added: $(date)" >> coredns/xbox-hosts

ADDED=0
while IFS= read -r domain; do
    if [ ! -z "$domain" ] && ! echo "$EXISTING" | grep -q "^${domain}$"; then
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
        ADDED=$((ADDED + 1))
    fi
done <<< "$MISSING_DOMAINS"

echo -e "${GREEN}✅ Added $ADDED domains${NC}"

# Step 2: Restart CoreDNS
echo ""
echo -e "${YELLOW}[2/3] Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns
sleep 3

# Step 3: Verify SNIProxy is working
echo ""
echo -e "${YELLOW}[3/3] Checking SNIProxy...${NC}"

if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy running on port 443${NC}"
else
    echo -e "${RED}❌ SNIProxy not running${NC}"
    systemctl restart sniproxy
    sleep 2
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Fix Applied!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Restart Xbox (unplug for 30 seconds)"
echo "  2. Test network connection again"
echo "  3. Monitor SNIProxy logs:"
echo "     tail -f /var/log/sniproxy/https_access.log"
echo ""
echo "If still not working, check:"
echo "  - Are Xbox domains connecting? (check SNIProxy logs)"
echo "  - Is SNIProxy forwarding? (should see real Xbox IPs in logs)"
echo ""
echo "================================================"


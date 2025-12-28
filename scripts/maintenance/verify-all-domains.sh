#!/bin/bash

# Comprehensive verification of all Xbox and game domains

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

HOSTS_FILE="coredns/xbox-hosts"
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)

echo "================================================"
echo "Comprehensive Domain Verification"
echo "================================================"
echo ""
echo "VPS IP: $VPS_IP"
echo "Hosts file: $HOSTS_FILE"
echo ""

if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    exit 1
fi

TOTAL_DOMAINS=0
MISSING_DOMAINS=0
PRESENT_DOMAINS=0

# Define all critical domains by category
declare -A DOMAIN_CATEGORIES

# === XBOX CORE ===
DOMAIN_CATEGORIES["Xbox Core"]="
xboxlive.com
xbox.com
xboxservices.com
xboxgamepass.com
gamepass.com
catalog.xboxservices.com
catalog.gamepass.com
"

# === XBOX AUTHENTICATION ===
DOMAIN_CATEGORIES["Xbox Authentication"]="
login.live.com
account.live.com
login.microsoftonline.com
xsts.auth.xboxlive.com
user.auth.xboxlive.com
device.auth.xboxlive.com
title.auth.xboxlive.com
"

# === NAT DETECTION (CRITICAL) ===
DOMAIN_CATEGORIES["NAT Detection (CRITICAL)"]="
xbox.nat.microsoft.com
xbox.ipv4.microsoft.com
xbox.ipv6.microsoft.com
dns.msftncsi.com
www.msftncsi.com
ipv6.msftncsi.com
www.msftconnecttest.com
ipv4.msftconnecttest.com
ipv6.msftconnecttest.com
"

# === XBOX GAMING SERVICES ===
DOMAIN_CATEGORIES["Xbox Gaming Services"]="
rta.xboxlive.com
titlestorage.xboxlive.com
titlestoragewus0505.blob.core.windows.net
multiplayeractivity.xboxlive.com
achievements.xboxlive.com
userstats.xboxlive.com
displaycatalog.mp.microsoft.com
v10.events.data.microsoft.com
v20.events.data.microsoft.com
ntp.servercore.com
activity.windows.com
client.wns.windows.com
"

# === MICROSOFT SERVICES ===
DOMAIN_CATEGORIES["Microsoft Services"]="
arc.msn.com
fs.microsoft.com
licensing.mp.microsoft.com
"

# === DISCORD ===
DOMAIN_CATEGORIES["Discord"]="
discord.com
www.discord.com
gateway.discord.gg
cdn.discordapp.com
media.discordapp.net
discord.gg
discordapp.com
discordapp.net
discord.media
"

# === CALL OF DUTY / ACTIVISION ===
DOMAIN_CATEGORIES["Call of Duty / Activision"]="
activision.com
www.activision.com
callofduty.com
www.callofduty.com
sledgehammergames.com
infinityward.com
treyarch.com
activisionblizzard.com
"

# === ELECTRONIC ARTS ===
DOMAIN_CATEGORIES["Electronic Arts"]="
ea.com
www.ea.com
easports.com
www.easports.com
eamobile.com
swtor.com
tnt-ea.com
origin.com
eaplay.com
"

# === UBISOFT ===
DOMAIN_CATEGORIES["Ubisoft"]="
ubisoft.com
www.ubisoft.com
uplay.com
ubisoftconnect.com
ubisoftstore.com
"

# === EPIC GAMES ===
DOMAIN_CATEGORIES["Epic Games"]="
epicgames.com
www.epicgames.com
unrealengine.com
fortnite.com
"

# === ROCKSTAR ===
DOMAIN_CATEGORIES["Rockstar"]="
rockstargames.com
www.rockstargames.com
socialclub.rockstargames.com
"

# === BLIZZARD ===
DOMAIN_CATEGORIES["Blizzard"]="
blizzard.com
www.blizzard.com
battle.net
www.battle.net
"

# === RIOT GAMES ===
DOMAIN_CATEGORIES["Riot Games"]="
riotgames.com
www.riotgames.com
leagueoflegends.com
valorant.com
"

# === SQUARE ENIX ===
DOMAIN_CATEGORIES["Square Enix"]="
square-enix.com
www.square-enix.com
square-enix-games.com
"

# === BETHESDA ===
DOMAIN_CATEGORIES["Bethesda"]="
bethesda.net
www.bethesda.net
bethesda.com
www.bethesda.com
"

# === CD PROJEKT ===
DOMAIN_CATEGORIES["CD Projekt"]="
cdprojekt.com
www.cdprojekt.com
gog.com
www.gog.com
"

# Domains that should NOT be in hosts file (must resolve to real IPs)
EXCLUDED_DOMAINS=(
    "teredo.ipv6.microsoft.com"
    "2k.com"
    "2ksports.com"
    "take2games.com"
    "a978.i6g1.akamai.net"
    "cod-assets.cdn.callofduty.com"
    "prod.cdni.callofduty.com"
    "ingest.datax.activision.com"
    "demonware.net"
    "genesis.stun.eu.demonware.net"
    "genesis.stun.us.demonware.net"
    "user-consent.prod.demonware.net"
)

echo "Checking all domains by category..."
echo ""

for category in "${!DOMAIN_CATEGORIES[@]}"; do
    echo -e "${BLUE}=== $category ===${NC}"
    CATEGORY_MISSING=0
    CATEGORY_PRESENT=0
    
    # Read domains from the category (skip empty lines)
    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        
        TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
        
        # Check if domain is in hosts file (as an IP entry, not comment)
        if grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
            echo -e "  ${GREEN}✅ $domain${NC}"
            PRESENT_DOMAINS=$((PRESENT_DOMAINS + 1))
            CATEGORY_PRESENT=$((CATEGORY_PRESENT + 1))
        else
            echo -e "  ${RED}❌ $domain MISSING${NC}"
            MISSING_DOMAINS=$((MISSING_DOMAINS + 1))
            CATEGORY_MISSING=$((CATEGORY_MISSING + 1))
        fi
    done <<< "${DOMAIN_CATEGORIES[$category]}"
    
    if [ $CATEGORY_MISSING -eq 0 ]; then
        echo -e "  ${GREEN}✅ All domains present ($CATEGORY_PRESENT/$CATEGORY_PRESENT)${NC}"
    else
        echo -e "  ${RED}❌ Missing $CATEGORY_MISSING domain(s)${NC}"
    fi
    echo ""
done

# Check excluded domains (should NOT be present)
echo -e "${BLUE}=== Excluded Domains (Should NOT be in hosts file) ===${NC}"
EXCLUDED_FOUND=0
for domain in "${EXCLUDED_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
        echo -e "  ${RED}❌ $domain (should be removed - must resolve to real IP)${NC}"
        EXCLUDED_FOUND=$((EXCLUDED_FOUND + 1))
        MISSING_DOMAINS=$((MISSING_DOMAINS + 1))
    else
        echo -e "  ${GREEN}✅ $domain (correctly excluded)${NC}"
    fi
done
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""
echo "Total domains checked: $TOTAL_DOMAINS"
echo -e "Present: ${GREEN}$PRESENT_DOMAINS${NC}"
echo -e "Missing: ${RED}$MISSING_DOMAINS${NC}"
echo ""

if [ $MISSING_DOMAINS -eq 0 ] && [ $EXCLUDED_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ All domains are correctly configured!${NC}"
    echo ""
    echo "All Xbox and game domains are present in the hosts file."
    echo "Excluded domains (CDN/matchmaking) are correctly removed."
    echo ""
else
    echo -e "${RED}❌ Issues found:${NC}"
    echo ""
    if [ $MISSING_DOMAINS -gt 0 ]; then
        echo "  • $MISSING_DOMAINS domain(s) missing from hosts file"
        echo "    Run: bash scripts/maintenance/regenerate-hosts.sh"
    fi
    if [ $EXCLUDED_FOUND -gt 0 ]; then
        echo "  • $EXCLUDED_FOUND excluded domain(s) found in hosts file"
        echo "    These must be removed (CDN/matchmaking domains)"
    fi
    echo ""
fi

# Check for domains in CoreDNS logs that might be missing
echo "================================================"
echo "Checking CoreDNS Logs for Missing Domains"
echo "================================================"
echo ""

echo "Recent queries that might indicate missing domains:"
RECENT_QUERIES=$(docker logs coredns-smartdns --tail 200 2>&1 | grep -oE "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | sort -u | head -20)

if [ -n "$RECENT_QUERIES" ]; then
    echo "Domains queried recently:"
    while IFS= read -r query_domain; do
        # Skip if it's in hosts file
        if grep -q "^[0-9].*$query_domain" "$HOSTS_FILE" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $query_domain (in hosts file)${NC}"
        else
            # Check if it's an excluded domain
            EXCLUDED=false
            for excluded in "${EXCLUDED_DOMAINS[@]}"; do
                if [[ "$query_domain" == *"$excluded"* ]] || [[ "$excluded" == *"$query_domain"* ]]; then
                    EXCLUDED=true
                    break
                fi
            done
            
            if [ "$EXCLUDED" = true ]; then
                echo -e "  ${YELLOW}⚠️  $query_domain (excluded - should resolve to real IP)${NC}"
            else
                echo -e "  ${YELLOW}⚠️  $query_domain (not in hosts file - may need to be added)${NC}"
            fi
        fi
    done <<< "$RECENT_QUERIES"
else
    echo "  No recent queries found in logs"
fi

echo ""
echo "================================================"
echo ""


#!/bin/bash

# Add common game publisher domains proactively
# This adds Activision, EA, Ubisoft, Epic Games, and other major publishers

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

cd /root/doh

echo "================================================"
echo "Adding Game Publisher Domains"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi

# Define publisher domains
declare -A PUBLISHERS=(
    ["Activision"]="activision.com callofduty.com sledgehammergames.com infinityward.com treyarch.com activisionblizzard.com"
    ["Electronic Arts"]="ea.com easports.com eamobile.com swtor.com tnt-ea.com origin.com eaplay.com"
    ["Ubisoft"]="ubisoft.com uplay.com ubisoftconnect.com ubisoftstore.com"
    ["Epic Games"]="epicgames.com unrealengine.com fortnite.com"
    ["Rockstar"]="rockstargames.com socialclub.rockstargames.com"
    ["2K Games"]="2k.com 2ksports.com take2games.com"
    ["Blizzard"]="blizzard.com battle.net"
    ["Riot Games"]="riotgames.com leagueoflegends.com valorant.com"
    ["Square Enix"]="square-enix.com square-enix-games.com"
    ["Bethesda"]="bethesda.net bethesda.com"
    ["CD Projekt"]="cdprojekt.com gog.com"
)

TOTAL_ADDED=0
TOTAL_SKIPPED=0

for PUBLISHER in "${!PUBLISHERS[@]}"; do
    DOMAINS="${PUBLISHERS[$PUBLISHER]}"
    
    echo -e "${BLUE}Adding $PUBLISHER domains...${NC}"
    
    for DOMAIN in $DOMAINS; do
        BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
        
        # Check if already exists in xbox-hosts
        if grep -q "^$VPS_IP.*$BASE_DOMAIN" coredns/xbox-hosts 2>/dev/null; then
            echo -e "  ${YELLOW}⚠ $BASE_DOMAIN already exists${NC}"
            ((TOTAL_SKIPPED++))
        else
            # Add to xbox-hosts
            echo "$VPS_IP $BASE_DOMAIN" >> coredns/xbox-hosts
            echo "$VPS_IP www.$BASE_DOMAIN" >> coredns/xbox-hosts
            echo -e "  ${GREEN}✅ Added $BASE_DOMAIN${NC}"
            ((TOTAL_ADDED++))
        fi
    done
    echo ""
done

# Add SNIProxy rules
echo -e "${YELLOW}Adding SNIProxy rules...${NC}"

SNIPROXY_CONF="/etc/sniproxy.conf"
if [ ! -f "$SNIPROXY_CONF" ]; then
    echo -e "${RED}❌ SNIProxy config not found${NC}"
    exit 1
fi

# Backup
cp "$SNIPROXY_CONF" "${SNIPROXY_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

# Collect all domains for SNIProxy
ALL_DOMAINS=""
for DOMAINS in "${PUBLISHERS[@]}"; do
    ALL_DOMAINS="$ALL_DOMAINS $DOMAINS"
done

SNI_ADDED=0
for DOMAIN in $ALL_DOMAINS; do
    BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
    ESCAPED_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's/\./\\./g')
    
    # Check if rule already exists
    if ! grep -q ".*\\.$ESCAPED_DOMAIN\\$" "$SNIPROXY_CONF" 2>/dev/null; then
        # Add before closing brace
        sed -i "/^}$/i\    .*\\.$ESCAPED_DOMAIN\\$ *" "$SNIPROXY_CONF"
        ((SNI_ADDED++))
    fi
done

if [ "$SNI_ADDED" -gt 0 ]; then
    echo -e "  ${GREEN}✅ Added $SNI_ADDED SNIProxy rules${NC}"
    
    # Restart SNIProxy
    systemctl restart sniproxy
    sleep 1
    
    if systemctl is-active --quiet sniproxy; then
        echo -e "  ${GREEN}✅ SNIProxy restarted${NC}"
    else
        echo -e "  ${RED}❌ SNIProxy failed to restart${NC}"
        echo "Check: journalctl -u sniproxy -n 20"
    fi
else
    echo -e "  ${YELLOW}⚠ All SNIProxy rules already exist${NC}"
fi

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"

if command -v docker &> /dev/null; then
    if docker ps | grep -q coredns-smartdns; then
        docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns
        sleep 2
        
        if docker ps | grep -q coredns-smartdns; then
            echo -e "  ${GREEN}✅ CoreDNS restarted${NC}"
        else
            echo -e "  ${RED}❌ CoreDNS failed to restart${NC}"
            exit 1
        fi
    fi
fi

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo -e "Domains added: ${GREEN}$TOTAL_ADDED${NC}"
echo -e "Domains skipped (already exist): ${YELLOW}$TOTAL_SKIPPED${NC}"
echo -e "SNIProxy rules added: ${GREEN}$SNI_ADDED${NC}"
echo ""
echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "Added publishers:"
for PUBLISHER in "${!PUBLISHERS[@]}"; do
    echo "  • $PUBLISHER"
done
echo ""
echo "These games should now work:"
echo "  • Call of Duty (Activision)"
echo "  • Battlefield (EA)"
echo "  • Assassin's Creed (Ubisoft)"
echo "  • Fortnite (Epic Games)"
echo "  • GTA Online (Rockstar)"
echo "  • And many more!"
echo ""


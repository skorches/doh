#!/bin/bash

# Regenerate xbox-hosts file with all domains

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

echo "================================================"
echo "Regenerating xbox-hosts File"
echo "================================================"
echo ""

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "./doh" ]; then
    DOH_DIR="./doh"
elif [ -d "." ] && [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    echo "Please run this script from the doh directory or provide the path"
    exit 1
fi

echo -e "${BLUE}Using directory: $DOH_DIR${NC}"
cd "$DOH_DIR"

# Get VPS IP (IPv4 only)
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP (IPv4): " VPS_IP
    if [ -z "$VPS_IP" ]; then
        echo -e "${RED}❌ VPS IP is required${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Backup existing file
HOSTS_FILE="coredns/xbox-hosts"
if [ -f "$HOSTS_FILE" ]; then
    cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"
    echo -e "${GREEN}✅ Backed up existing file${NC}"
fi

# Generate new hosts file
echo -e "${YELLOW}Generating new hosts file...${NC}"

cat > "$HOSTS_FILE" << EOFHOSTS
# Essential Xbox Smart DNS Hosts
# VPS IP: $VPS_IP
# Generated: $(date)

# === XBOX CORE ===
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP xnotify.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP settings.xboxlive.com
$VPS_IP profile.xboxlive.com

# === XBOX AUTHENTICATION ===
$VPS_IP login.live.com
$VPS_IP account.microsoft.com
$VPS_IP login.microsoftonline.com
$VPS_IP auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com

# === XBOX SERVICES ===
$VPS_IP xboxservices.com
$VPS_IP www.xboxservices.com
$VPS_IP xbox.com
$VPS_IP www.xbox.com
$VPS_IP live.com
$VPS_IP www.live.com
$VPS_IP microsoft.com
$VPS_IP www.microsoft.com
$VPS_IP microsoftonline.com
$VPS_IP msftncsi.com
$VPS_IP msftconnecttest.com
$VPS_IP windows.com
$VPS_IP msn.com
$VPS_IP gamepass.com
$VPS_IP www.gamepass.com

# === DISCORD ===
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP status.discord.com
$VPS_IP api.discord.com
$VPS_IP gateway.discord.com
$VPS_IP cdn.discord.com
$VPS_IP images-ext-1.discordapp.net
$VPS_IP images-ext-2.discordapp.net
$VPS_IP media.discordapp.com

# === ACTIVISION (Call of Duty, Warzone) ===
$VPS_IP activision.com
$VPS_IP www.activision.com
$VPS_IP callofduty.com
$VPS_IP www.callofduty.com
$VPS_IP sledgehammergames.com
$VPS_IP infinityward.com
$VPS_IP treyarch.com
$VPS_IP activisionblizzard.com
$VPS_IP profile.callofduty.com
$VPS_IP s2s.callofduty.com
$VPS_IP profile.activision.com
$VPS_IP accounts.callofduty.com
$VPS_IP atvi.com
$VPS_IP www.atvi.com

# === ELECTRONIC ARTS (Battlefield, FIFA, etc.) ===
$VPS_IP ea.com
$VPS_IP www.ea.com
$VPS_IP easports.com
$VPS_IP www.easports.com
$VPS_IP eamobile.com
$VPS_IP swtor.com
$VPS_IP tnt-ea.com
$VPS_IP origin.com
$VPS_IP www.origin.com
$VPS_IP eaplay.com

# === UBISOFT ===
$VPS_IP ubisoft.com
$VPS_IP www.ubisoft.com
$VPS_IP uplay.com
$VPS_IP ubisoftconnect.com
$VPS_IP ubisoftstore.com

# === EPIC GAMES (Fortnite) ===
$VPS_IP epicgames.com
$VPS_IP www.epicgames.com
$VPS_IP unrealengine.com
$VPS_IP fortnite.com

# === ROCKSTAR (GTA Online) ===
$VPS_IP rockstargames.com
$VPS_IP www.rockstargames.com
$VPS_IP socialclub.rockstargames.com

# === 2K GAMES ===
$VPS_IP 2k.com
$VPS_IP www.2k.com
$VPS_IP 2ksports.com
$VPS_IP www.2ksports.com
$VPS_IP take2games.com

# === BLIZZARD ===
$VPS_IP blizzard.com
$VPS_IP www.blizzard.com
$VPS_IP battle.net
$VPS_IP www.battle.net

# === RIOT GAMES ===
$VPS_IP riotgames.com
$VPS_IP www.riotgames.com
$VPS_IP leagueoflegends.com
$VPS_IP valorant.com

# === SQUARE ENIX ===
$VPS_IP square-enix.com
$VPS_IP www.square-enix.com
$VPS_IP square-enix-games.com

# === BETHESDA ===
$VPS_IP bethesda.net
$VPS_IP www.bethesda.net
$VPS_IP bethesda.com
$VPS_IP www.bethesda.com

# === CD PROJEKT ===
$VPS_IP cdprojekt.com
$VPS_IP www.cdprojekt.com
$VPS_IP gog.com
$VPS_IP www.gog.com
EOFHOSTS

echo -e "${GREEN}✅ Hosts file generated${NC}"
echo ""

# Restart CoreDNS
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart via docker-compose, trying direct restart...${NC}"
    docker restart coredns-smartdns 2>/dev/null || echo -e "${RED}❌ Could not restart CoreDNS${NC}"
}
sleep 3

# Verify DNS resolution
echo ""
echo -e "${YELLOW}Verifying DNS resolution...${NC}"
DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
ACTIVISION_DNS=$(timeout 3 dig @127.0.0.1 activision.com +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS"
echo "  activision.com → $ACTIVISION_DNS"

if [ "$DISCORD_DNS" == "$VPS_IP" ] && [ "$ACTIVISION_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolution working correctly!${NC}"
else
    echo -e "${YELLOW}⚠ DNS may need a moment to update${NC}"
    echo "   Try: dig @127.0.0.1 discord.com"
fi

echo ""
echo "================================================"
echo "✅ Hosts file regenerated!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Test DNS: dig @127.0.0.1 discord.com"
echo "2. Restart your router to clear DNS cache"
echo "3. Test Discord and Activision games"
echo ""





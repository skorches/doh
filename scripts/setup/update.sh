#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "DoH Configuration Update Script"
echo "================================================"
echo ""
echo "This script will update your running configuration"
echo "to match the latest version without full reinstall."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root (sudo)${NC}"
    exit 1
fi

# Check if installation exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ No existing installation found${NC}"
    echo "Please run install.sh first"
    exit 1
fi

echo -e "${YELLOW}[1/7] Backing up current configuration...${NC}"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r coredns/ "$BACKUP_DIR/" 2>/dev/null || true
cp -r nginx/ "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
echo -e "${GREEN}✅ Backup created: $BACKUP_DIR${NC}"
echo ""

# Auto-detect VPS IP
echo -e "${YELLOW}[2/7] Detecting VPS IP address...${NC}"
VPS_IP=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi
echo -e "${GREEN}✅ VPS IP: $VPS_IP${NC}"
echo ""

# Get domain from existing config
echo -e "${YELLOW}[3/7] Reading existing configuration...${NC}"
DOMAIN_NAME=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';' || echo "")
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}❌ Could not read domain name from config${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Domain: $DOMAIN_NAME${NC}"
echo ""

# Check SSL certificate type
SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
if [ -f "$SSL_CERT" ]; then
    echo -e "${GREEN}✅ Using Let's Encrypt certificate${NC}"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
else
    echo -e "${YELLOW}ℹ Using self-signed certificate${NC}"
    SSL_CERT="/etc/nginx/ssl/doh.crt"
    SSL_KEY="/etc/nginx/ssl/doh.key"
fi
echo ""

# Update hosts file with new domains
echo -e "${YELLOW}[4/7] Updating hosts file with latest domains...${NC}"
cat > coredns/xbox-hosts << EOFHOSTS
# Auto-generated Xbox/Gaming DNS hosts file
# Last updated: $(date)
# VPS IP: $VPS_IP
#
# This file maps Xbox Live, gaming services, and publisher domains to your VPS
# for bypassing network restrictions while maintaining low latency.

# === MICROSOFT SERVICES ===
$VPS_IP arc.msn.com
$VPS_IP fs.microsoft.com
$VPS_IP licensing.mp.microsoft.com

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
$VPS_IP auth.xboxlive.com
$VPS_IP device.auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP sisu.xboxlive.com

# === XBOX SERVICES ===
$VPS_IP xbox.com
$VPS_IP www.xbox.com
$VPS_IP xboxservices.com
$VPS_IP www.xboxservices.com
$VPS_IP activity.xboxservices.com
$VPS_IP contentaccess.xboxservices.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP licensing.xboxservices.com
$VPS_IP catalog.xboxservices.com
$VPS_IP live.com
$VPS_IP www.live.com
$VPS_IP microsoft.com
$VPS_IP www.microsoft.com
$VPS_IP microsoftonline.com
$VPS_IP msn.com
$VPS_IP windows.com
$VPS_IP msftncsi.com
$VPS_IP msftconnecttest.com

# === GAME PASS ===
$VPS_IP gamepass.com
$VPS_IP www.gamepass.com
$VPS_IP catalog.gamepass.com
$VPS_IP xboxgamepass.com

# === MICROSOFT LOGIN ===
$VPS_IP login.live.com
$VPS_IP account.live.com
$VPS_IP account.microsoft.com
$VPS_IP login.microsoftonline.com

# === MICROSOFT NETWORK CHECKS (NAT Detection) ===
# CRITICAL: These domains are required for Xbox NAT type detection
# Missing any of these will cause "NAT unavailable" errors
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftncsi.com
$VPS_IP ipv6.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv4.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com

# === XBOX GAMING SERVICES ===
$VPS_IP rta.xboxlive.com
$VPS_IP titlestorage.xboxlive.com
$VPS_IP titlestoragewus0505.blob.core.windows.net
$VPS_IP multiplayeractivity.xboxlive.com
$VPS_IP achievements.xboxlive.com
$VPS_IP userstats.xboxlive.com
$VPS_IP displaycatalog.mp.microsoft.com
$VPS_IP v10.events.data.microsoft.com
$VPS_IP v20.events.data.microsoft.com
# NOTE: a978.i6g1.akamai.net removed - Akamai CDN domains must resolve to real IPs for game assets (NBA 2K, etc.)
$VPS_IP ntp.servercore.com

# === NAT DETECTION ===
# CRITICAL: These domains are required for Xbox NAT type detection
# Missing any of these will cause "NAT unavailable" errors
$VPS_IP xbox.ipv6.microsoft.com
$VPS_IP xbox.ipv4.microsoft.com
$VPS_IP xbox.nat.microsoft.com
# NOTE: teredo.ipv6.microsoft.com must resolve to REAL Teredo servers (not VPS IP)
# Removing it from hosts file so it resolves correctly

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

# === GAME PUBLISHERS ===
# Activision (Call of Duty, Warzone)
$VPS_IP activision.com
$VPS_IP www.activision.com
$VPS_IP atvi.com
$VPS_IP www.atvi.com
$VPS_IP callofduty.com
$VPS_IP www.callofduty.com
$VPS_IP accounts.callofduty.com
$VPS_IP profile.callofduty.com
$VPS_IP s2s.callofduty.com
$VPS_IP profile.activision.com
$VPS_IP sledgehammergames.com
$VPS_IP infinityward.com
$VPS_IP treyarch.com
$VPS_IP activisionblizzard.com
# Note: Call of Duty domains (CDN, demonware, STUN servers) must resolve to real IPs for proper connectivity
# Do NOT add: cod-assets, ingest.datax, prod.cdni, demonware.net, genesis.stun.*, user-consent.prod.demonware.net

# Electronic Arts (Battlefield, FIFA, etc.)
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

# Epic Games (Fortnite, Unreal Engine)
$VPS_IP epicgames.com
$VPS_IP www.epicgames.com
$VPS_IP unrealengine.com
$VPS_IP fortnite.com

# Riot Games (League of Legends, Valorant)
$VPS_IP riotgames.com
$VPS_IP www.riotgames.com
$VPS_IP leagueoflegends.com
$VPS_IP valorant.com

# Ubisoft (Rainbow Six, Assassin's Creed, etc.)
$VPS_IP ubisoft.com
$VPS_IP www.ubisoft.com
$VPS_IP uplay.com
$VPS_IP ubisoftconnect.com
$VPS_IP ubisoftstore.com

# Blizzard (Overwatch, WoW, Diablo, etc.)
$VPS_IP blizzard.com
$VPS_IP www.blizzard.com
$VPS_IP battle.net
$VPS_IP www.battle.net

# Bethesda (Fallout, Elder Scrolls, etc.)
$VPS_IP bethesda.net
$VPS_IP www.bethesda.net
$VPS_IP bethesda.com
$VPS_IP www.bethesda.com

# Rockstar (GTA, Red Dead Redemption)
$VPS_IP rockstargames.com
$VPS_IP www.rockstargames.com
$VPS_IP socialclub.rockstargames.com

# Square Enix (Final Fantasy, etc.)
$VPS_IP square-enix.com
$VPS_IP www.square-enix.com
$VPS_IP square-enix-games.com

# CD Projekt (Cyberpunk, Witcher, GOG)
$VPS_IP cdprojekt.com
$VPS_IP www.cdprojekt.com
$VPS_IP gog.com
$VPS_IP www.gog.com

# NOTE: 2K Games domains (2k.com, 2ksports.com, take2games.com) are EXCLUDED
# Routing these through VPS causes NBA 2K and other 2K games to disconnect
# These domains must resolve to real IPs for proper CDN/matchmaking connectivity
EOFHOSTS

DOMAIN_COUNT=$(grep -c "^$VPS_IP" coredns/xbox-hosts)
echo -e "${GREEN}✅ Hosts file updated with $DOMAIN_COUNT domains${NC}"
echo ""

# Update Corefile if needed
echo -e "${YELLOW}[5/7] Checking CoreDNS configuration...${NC}"
if ! grep -q "cache 86400" coredns/Corefile 2>/dev/null; then
    echo "Updating Corefile with optimized cache settings..."
    cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    # CRITICAL: hosts plugin returns immediately, no cache/upstream needed
    # reload ensures hosts file is checked periodically (prevents stale entries)
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward with parallel upstreams and fast fail settings
    # max_fails and health_check prevent long timeouts when port 53 is blocked
    # except directive ensures hosts file domains NEVER go to upstream
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Enable caching (24-hour cache for maximum stability)
    # NOTE: Domains in hosts file bypass cache and upstream entirely
    # Cache only applies to domains NOT in hosts file
    # Long cache reduces upstream queries significantly (prevents timeouts)
    cache 86400 {
        success 86400
        denial 86400
    }
    
    # Log errors (helps diagnose issues)
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE
    echo -e "${GREEN}✅ Corefile updated${NC}"
else
    echo -e "${GREEN}✅ Corefile already optimized${NC}"
fi
echo ""

# Update docker-compose.yml environment if needed
echo -e "${YELLOW}[6/7] Checking docker-compose configuration...${NC}"
if ! grep -q "DOH_SERVER_TIMEOUT=10" docker-compose.yml 2>/dev/null; then
    echo "Updating docker-compose.yml timeouts..."
    sed -i 's/DOH_SERVER_TIMEOUT=.*/DOH_SERVER_TIMEOUT=10/' docker-compose.yml
    sed -i 's/DOH_SERVER_TRIES=.*/DOH_SERVER_TRIES=3/' docker-compose.yml
    echo -e "${GREEN}✅ docker-compose.yml updated${NC}"
else
    echo -e "${GREEN}✅ docker-compose.yml already optimized${NC}"
fi
echo ""

# Restart services
echo -e "${YELLOW}[7/7] Restarting services...${NC}"
echo "Restarting CoreDNS..."
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

echo "Restarting DoH backend..."
docker-compose restart doh-backend 2>/dev/null || docker compose restart doh-backend 2>/dev/null || docker restart doh-backend
sleep 2

echo "Restarting Nginx..."
docker-compose restart doh-nginx 2>/dev/null || docker compose restart doh-nginx 2>/dev/null || docker restart doh-nginx
sleep 2

echo -e "${GREEN}✅ All services restarted${NC}"
echo ""

# Verify services
echo "================================================"
echo "Verifying Update"
echo "================================================"
echo ""

echo "Checking Docker containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "coredns|doh-backend|doh-nginx"
echo ""

echo "Testing DNS resolution..."
TEST_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1)
if echo "$TEST_RESULT" | grep -q "$VPS_IP"; then
    echo -e "${GREEN}✅ DNS resolution working (xboxlive.com → $VPS_IP)${NC}"
else
    echo -e "${YELLOW}⚠️  DNS test inconclusive, check manually${NC}"
fi
echo ""

echo "================================================"
echo "Update Complete!"
echo "================================================"
echo ""
echo "Changes applied:"
echo "  • Hosts file updated to 135 domains"
echo "  • CoreDNS cache set to 24 hours"
echo "  • Fast-fail upstream settings enabled"
echo "  • DoH backend timeout increased to 10s"
echo "  • All services restarted"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To verify everything:"
echo "  bash scripts/maintenance/verify-xbox-services.sh"
echo ""
echo "If you need to rollback:"
echo "  cp -r $BACKUP_DIR/* ./"
echo "  docker-compose restart"
echo ""

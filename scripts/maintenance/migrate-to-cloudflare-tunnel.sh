#!/bin/bash

# Migrate DNS configuration to support Cloudflare Tunnel

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
echo "Migrating DNS Configuration for Cloudflare Tunnel"
echo "================================================"
echo ""
echo "This will update your DNS configuration so Xbox"
echo "domains resolve to Cloudflare Tunnel IPs instead"
echo "of your VPS IP."
echo ""

read -p "Enter your Cloudflare tunnel subdomain (e.g., xbox-proxy.440.info): " TUNNEL_DOMAIN
if [ -z "$TUNNEL_DOMAIN" ]; then
    echo -e "${RED}❌ Tunnel domain is required${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Backing up current configuration...${NC}"

# Backup files
BACKUP_DIR="/root/doh-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp coredns/xbox-hosts "$BACKUP_DIR/xbox-hosts.backup"
cp coredns/Corefile "$BACKUP_DIR/Corefile.backup"
echo -e "${GREEN}✅ Backups created in $BACKUP_DIR${NC}"

echo ""
echo -e "${YELLOW}Updating DNS configuration...${NC}"

# Get current VPS IP (for reference)
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "unknown")
echo -e "${BLUE}Current VPS IP: $VPS_IP${NC}"
echo ""

# Create new xbox-hosts file - remove Xbox domains, keep Discord and game publishers
# Xbox domains will now resolve through Cloudflare DNS to tunnel IPs
cat > coredns/xbox-hosts << EOFHOSTS
# DNS Configuration for Cloudflare Tunnel
# Generated: $(date)
# 
# NOTE: Xbox domains are removed from this file.
# They will resolve through Cloudflare DNS (1.1.1.1) which
# has CNAME records pointing to: $TUNNEL_DOMAIN
#
# This allows Xbox to connect to Cloudflare Tunnel IPs
# instead of the Russian VPS IP.

# === DISCORD (Keep using VPS IP - not blocked) ===
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media

# === GAME PUBLISHERS (Keep using VPS IP) ===
# Activision (Call of Duty, Warzone)
$VPS_IP activision.com
$VPS_IP www.activision.com
$VPS_IP callofduty.com
$VPS_IP www.callofduty.com
$VPS_IP sledgehammergames.com
$VPS_IP infinityward.com
$VPS_IP treyarch.com
$VPS_IP activisionblizzard.com

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

# Ubisoft (Assassin's Creed, etc.)
$VPS_IP ubisoft.com
$VPS_IP www.ubisoft.com
$VPS_IP uplay.com
$VPS_IP ubisoftconnect.com
$VPS_IP ubisoftstore.com

# Epic Games (Fortnite)
$VPS_IP epicgames.com
$VPS_IP www.epicgames.com
$VPS_IP unrealengine.com
$VPS_IP fortnite.com

# Rockstar
$VPS_IP rockstargames.com
$VPS_IP www.rockstargames.com
$VPS_IP socialclub.rockstargames.com

# 2K Games
$VPS_IP 2k.com
$VPS_IP www.2k.com
$VPS_IP 2ksports.com
$VPS_IP take2games.com

# Blizzard
$VPS_IP blizzard.com
$VPS_IP www.blizzard.com
$VPS_IP battle.net

# Riot Games
$VPS_IP riotgames.com
$VPS_IP www.riotgames.com
$VPS_IP leagueoflegends.com
$VPS_IP valorant.com

# Square Enix
$VPS_IP square-enix.com
$VPS_IP www.square-enix.com
$VPS_IP square-enix-games.com

# Bethesda
$VPS_IP bethesda.net
$VPS_IP www.bethesda.net
$VPS_IP bethesda.com
$VPS_IP www.bethesda.com

# CD Projekt
$VPS_IP cdprojekt.com
$VPS_IP www.cdprojekt.com
$VPS_IP gog.com
$VPS_IP www.gog.com
EOFHOSTS

echo -e "${GREEN}✅ Updated coredns/xbox-hosts${NC}"
echo ""

# Update Corefile to ensure forwarding works correctly
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Discord and game publishers
    # (Xbox domains removed - they resolve through Cloudflare DNS)
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to Cloudflare DNS
    # Xbox domains will resolve to Cloudflare Tunnel IPs via CNAME records
    forward . 1.1.1.1 1.0.0.1 {
        except discord.com discordapp.com discord.gg discord.media
        except activision.com callofduty.com ea.com easports.com
        except ubisoft.com epicgames.com rockstargames.com
        except 2k.com blizzard.com riotgames.com
        except square-enix.com bethesda.net cdprojekt.com gog.com
    }
    
    # Enable caching
    cache 300
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

echo -e "${GREEN}✅ Updated coredns/Corefile${NC}"
echo ""

# Restart CoreDNS
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
cd /root/doh
docker-compose restart coredns-smartdns || docker compose restart coredns-smartdns
sleep 2

# Check if CoreDNS is running
if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS restarted${NC}"
else
    echo -e "${RED}❌ CoreDNS failed to restart${NC}"
    echo "Restoring backups..."
    cp "$BACKUP_DIR/xbox-hosts.backup" coredns/xbox-hosts
    cp "$BACKUP_DIR/Corefile.backup" coredns/Corefile
    docker-compose restart coredns-smartdns || docker compose restart coredns-smartdns
    exit 1
fi

echo ""
echo "================================================"
echo "DNS Migration Complete"
echo "================================================"
echo ""
echo -e "${GREEN}✅ Configuration updated${NC}"
echo ""
echo "WHAT CHANGED:"
echo "─────────────"
echo "• Removed Xbox domains from xbox-hosts"
echo "• Xbox domains now resolve through Cloudflare DNS"
echo "• Cloudflare DNS has CNAME records → $TUNNEL_DOMAIN"
echo "• Discord and game publishers still use VPS IP"
echo ""
echo "NEXT STEPS:"
echo "───────────"
echo "1. Ensure Cloudflare Tunnel is configured:"
echo "   • Tunnel created in Cloudflare dashboard"
echo "   • Public hostname: $TUNNEL_DOMAIN → TCP → 127.0.0.1:443"
echo ""
echo "2. Ensure DNS records in Cloudflare:"
echo "   • xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
echo "   • notify.xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
echo "   • xccs.xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
echo "   • etc. for all Xbox domains"
echo ""
echo "3. Test DNS resolution:"
echo "   nslookup xboxlive.com"
echo "   # Should return Cloudflare IPs, not VPS IP"
echo ""
echo "4. Restart Xbox and test connection"
echo ""
echo -e "${YELLOW}Backups saved in: $BACKUP_DIR${NC}"
echo ""


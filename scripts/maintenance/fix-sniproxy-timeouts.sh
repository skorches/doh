#!/bin/bash

# Fix SNIProxy timeouts to fail faster when Xbox hangs connections

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
echo "Fixing SNIProxy Timeout Settings"
echo "================================================"
echo ""

SNIPROXY_CONF="/etc/sniproxy.conf"

if [ ! -f "$SNIPROXY_CONF" ]; then
    echo -e "${RED}❌ SNIProxy config not found: $SNIPROXY_CONF${NC}"
    exit 1
fi

echo -e "${YELLOW}Current SNIProxy config has no timeout settings${NC}"
echo -e "${YELLOW}Adding timeout settings to fail faster...${NC}"
echo ""

# Backup original config
cp "$SNIPROXY_CONF" "${SNIPROXY_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}✅ Backed up config${NC}"

# Check if timeout settings already exist
if grep -q "timeout" "$SNIPROXY_CONF"; then
    echo -e "${YELLOW}⚠ Timeout settings already exist${NC}"
    echo "Current timeout settings:"
    grep -i timeout "$SNIPROXY_CONF" || echo "None found"
    read -p "Overwrite? (y/n): " REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

# Read domain from config (needed for DoH routing)
DOMAIN_NAME=$(grep -oP '\$[^$]+\$' "$SNIPROXY_CONF" | head -1 | sed 's/\$//g' | sed 's/\\\././g' || echo "")
if [ -z "$DOMAIN_NAME" ]; then
    # Try to extract from table entry
    DOMAIN_NAME=$(grep -oP '127\.0\.0\.1:8443' "$SNIPROXY_CONF" -B 1 | grep -oP '[a-zA-Z0-9.-]+' | head -1 || echo "")
fi

DOMAIN_ESCAPED=$(echo "$DOMAIN_NAME" | sed 's/\./\\./g' 2>/dev/null || echo "")

echo -e "${BLUE}Detected domain: ${DOMAIN_NAME:-"unknown"}${NC}"
echo ""

# Create new config with timeout settings
cat > "$SNIPROXY_CONF" << EOFSNI
user daemon

pidfile /var/run/sniproxy.pid

# Timeout settings to fail faster when Xbox hangs connections
# Default is 30 seconds, but we'll set shorter for faster failure
resolver {
    nameserver 8.8.8.8
    mode ipv4_only
}

# Connection timeouts (in milliseconds)
# 10000 = 10 seconds - fail fast if Xbox hangs
timeout connect 10000
timeout client 30000
timeout server 30000

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

table https_hosts {
    # DoH server - route to local nginx
EOFSNI

# Add domain entry if found
if [ -n "$DOMAIN_ESCAPED" ]; then
    echo "    $DOMAIN_ESCAPED\$ 127.0.0.1:8443" >> "$SNIPROXY_CONF"
else
    echo "    # Add your DoH domain here" >> "$SNIPROXY_CONF"
fi

# Add all the domain patterns from backup
cat >> "$SNIPROXY_CONF" << 'EOFSNI'
    
    # Xbox domains - route to real servers
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
    
    # Game Publisher domains
    # Activision
    .*\.activision\.com$ *
    .*\.callofduty\.com$ *
    .*\.sledgehammergames\.com$ *
    .*\.infinityward\.com$ *
    .*\.treyarch\.com$ *
    .*\.activisionblizzard\.com$ *
    
    # Electronic Arts
    .*\.ea\.com$ *
    .*\.easports\.com$ *
    .*\.eamobile\.com$ *
    .*\.swtor\.com$ *
    .*\.tnt-ea\.com$ *
    .*\.origin\.com$ *
    .*\.eaplay\.com$ *
    
    # Ubisoft
    .*\.ubisoft\.com$ *
    .*\.uplay\.com$ *
    .*\.ubisoftconnect\.com$ *
    .*\.ubisoftstore\.com$ *
    
    # Epic Games
    .*\.epicgames\.com$ *
    .*\.unrealengine\.com$ *
    .*\.fortnite\.com$ *
    
    # Rockstar
    .*\.rockstargames\.com$ *
    .*\.socialclub\.rockstargames\.com$ *
    
    # 2K Games
    .*\.2k\.com$ *
    .*\.2ksports\.com$ *
    .*\.take2games\.com$ *
    
    # Blizzard
    .*\.blizzard\.com$ *
    .*\.battle\.net$ *
    
    # Riot Games
    .*\.riotgames\.com$ *
    .*\.leagueoflegends\.com$ *
    .*\.valorant\.com$ *
    
    # Square Enix
    .*\.square-enix\.com$ *
    .*\.square-enix-games\.com$ *
    
    # Bethesda
    .*\.bethesda\.net$ *
    .*\.bethesda\.com$ *
    
    # CD Projekt
    .*\.cdprojekt\.com$ *
    .*\.gog\.com$ *
}
EOFSNI

echo -e "${GREEN}✅ Updated SNIProxy config with timeout settings${NC}"
echo ""

# Validate config
echo -e "${YELLOW}Validating SNIProxy config...${NC}"
if sniproxy -c "$SNIPROXY_CONF" -t 2>&1 | grep -q "configuration file is valid"; then
    echo -e "${GREEN}✅ Config is valid${NC}"
else
    echo -e "${RED}❌ Config validation failed${NC}"
    echo "Restoring backup..."
    mv "${SNIPROXY_CONF}.backup."* "$SNIPROXY_CONF" 2>/dev/null || true
    exit 1
fi

# Restart SNIProxy
echo ""
echo -e "${YELLOW}Restarting SNIProxy...${NC}"
systemctl restart sniproxy
sleep 2

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy restarted successfully${NC}"
    echo ""
    echo "================================================"
    echo "Timeout Settings Applied"
    echo "================================================"
    echo ""
    echo "New timeout settings:"
    echo "  • Connect timeout: 10 seconds"
    echo "  • Client timeout: 30 seconds"
    echo "  • Server timeout: 30 seconds"
    echo ""
    echo "This will make connections fail faster when"
    echo "Xbox hangs them (instead of waiting 6-8 minutes)."
    echo ""
    echo -e "${YELLOW}NOTE: This won't fix Xbox blocking Russian IPs.${NC}"
    echo "If Xbox is blocking your VPS IP, you may need:"
    echo "  • Non-Russian VPS (Germany, Netherlands, US)"
    echo "  • Or different approach (VPN instead of proxy)"
else
    echo -e "${RED}❌ SNIProxy failed to start${NC}"
    echo "Restoring backup..."
    mv "${SNIPROXY_CONF}.backup."* "$SNIPROXY_CONF" 2>/dev/null || true
    systemctl restart sniproxy
    exit 1
fi


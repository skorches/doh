#!/bin/bash

# Fix Discord and Activision connectivity issues

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
echo "Fixing Discord & Activision Connectivity"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP: " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Check DNS resolution
echo -e "${YELLOW}[1/6] Checking DNS resolution...${NC}"

DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
ACTIVISION_DNS=$(timeout 3 dig @127.0.0.1 activision.com +short 2>/dev/null | head -1 || echo "FAILED")
CALL_OF_DUTY_DNS=$(timeout 3 dig @127.0.0.1 callofduty.com +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS"
echo "  activision.com → $ACTIVISION_DNS"
echo "  callofduty.com → $CALL_OF_DUTY_DNS"

if [ "$DISCORD_DNS" != "$VPS_IP" ] || [ "$ACTIVISION_DNS" != "$VPS_IP" ] || [ "$CALL_OF_DUTY_DNS" != "$VPS_IP" ]; then
    echo -e "${RED}❌ DNS not resolving to VPS IP${NC}"
    echo -e "${YELLOW}Updating DNS configuration...${NC}"
    
    # Check if CoreDNS is running
    if ! docker ps | grep -q coredns-smartdns; then
        echo -e "${RED}❌ CoreDNS not running${NC}"
        echo "Starting CoreDNS..."
        cd /root/doh 2>/dev/null || cd ~/doh 2>/dev/null || cd /opt/doh 2>/dev/null || {
            echo -e "${RED}❌ Could not find doh directory${NC}"
            exit 1
        }
        docker-compose up -d coredns-smartdns || docker compose up -d coredns-smartdns
        sleep 3
    fi
    
    # Update xbox-hosts file with more Discord and Activision subdomains
    HOSTS_FILE=""
    if [ -f "/root/doh/coredns/xbox-hosts" ]; then
        HOSTS_FILE="/root/doh/coredns/xbox-hosts"
    elif [ -f "~/doh/coredns/xbox-hosts" ]; then
        HOSTS_FILE="~/doh/coredns/xbox-hosts"
    elif [ -f "./coredns/xbox-hosts" ]; then
        HOSTS_FILE="./coredns/xbox-hosts"
    else
        echo -e "${RED}❌ Could not find xbox-hosts file${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Found hosts file: $HOSTS_FILE${NC}"
    
    # Backup
    cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"
    
    # Check if Discord and Activision are already in the file
    if ! grep -q "^$VPS_IP.*discord" "$HOSTS_FILE"; then
        echo -e "${YELLOW}Adding Discord domains...${NC}"
        cat >> "$HOSTS_FILE" << EOFDISCORD

# === DISCORD (Added by fix script) ===
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
EOFDISCORD
    fi
    
    if ! grep -q "^$VPS_IP.*activision" "$HOSTS_FILE"; then
        echo -e "${YELLOW}Adding Activision domains...${NC}"
        cat >> "$HOSTS_FILE" << EOFACTIVISION

# === ACTIVISION (Added by fix script) ===
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
EOFACTIVISION
    fi
    
    # Restart CoreDNS
    echo -e "${YELLOW}Restarting CoreDNS...${NC}"
    cd "$(dirname "$HOSTS_FILE")/.."
    docker-compose restart coredns-smartdns || docker compose restart coredns-smartdns
    sleep 3
    
    echo -e "${GREEN}✅ DNS configuration updated${NC}"
else
    echo -e "${GREEN}✅ DNS resolving correctly${NC}"
fi

# Step 2: Check SNIProxy configuration
echo ""
echo -e "${YELLOW}[2/6] Checking SNIProxy configuration...${NC}"

if [ ! -f /etc/sniproxy.conf ]; then
    echo -e "${RED}❌ SNIProxy config not found${NC}"
    exit 1
fi

# Check if Discord and Activision are in SNIProxy config
if ! grep -q "discord" /etc/sniproxy.conf; then
    echo -e "${RED}❌ Discord not in SNIProxy config${NC}"
    echo -e "${YELLOW}Updating SNIProxy config...${NC}"
    
    # Backup
    cp /etc/sniproxy.conf /etc/sniproxy.conf.backup.$(date +%s)
    
    # Add Discord and Activision rules before the closing brace
    sed -i '/^}$/i\
    # Discord domains\
    .*\.discord\.com$ *\
    .*\.discordapp\.com$ *\
    .*\.discordapp\.net$ *\
    .*\.discord\.gg$ *\
    .*\.discord\.media$ *\
    \
    # Activision domains\
    .*\.activision\.com$ *\
    .*\.callofduty\.com$ *\
    .*\.sledgehammergames\.com$ *\
    .*\.infinityward\.com$ *\
    .*\.treyarch\.com$ *\
    .*\.activisionblizzard\.com$ *\
    .*\.atvi\.com$ *\
' /etc/sniproxy.conf
    
    # Restart SNIProxy
    systemctl restart sniproxy
    sleep 2
    
    echo -e "${GREEN}✅ SNIProxy config updated${NC}"
else
    echo -e "${GREEN}✅ SNIProxy config looks good${NC}"
fi

# Step 3: Check SNIProxy status
echo ""
echo -e "${YELLOW}[3/6] Checking SNIProxy status...${NC}"

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "${RED}❌ SNIProxy not listening on port 443${NC}"
        echo "Restarting SNIProxy..."
        systemctl restart sniproxy
        sleep 2
    fi
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
    echo "Starting SNIProxy..."
    systemctl start sniproxy
    sleep 2
fi

# Step 4: Test connectivity
echo ""
echo -e "${YELLOW}[4/6] Testing connectivity...${NC}"

# Test Discord
echo "Testing Discord connectivity..."
DISCORD_TEST=$(timeout 5 curl -s -I --resolve discord.com:443:$VPS_IP https://discord.com 2>&1 | head -1 || echo "FAILED")
if echo "$DISCORD_TEST" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ Discord reachable${NC}"
else
    echo -e "${YELLOW}⚠ Discord test: $DISCORD_TEST${NC}"
fi

# Test Activision
echo "Testing Activision connectivity..."
ACTIVISION_TEST=$(timeout 5 curl -s -I --resolve activision.com:443:$VPS_IP https://activision.com 2>&1 | head -1 || echo "FAILED")
if echo "$ACTIVISION_TEST" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ Activision reachable${NC}"
else
    echo -e "${YELLOW}⚠ Activision test: $ACTIVISION_TEST${NC}"
fi

# Step 5: Check for missing subdomains
echo ""
echo -e "${YELLOW}[5/6] Checking for common missing subdomains...${NC}"

# Discord common subdomains
DISCORD_SUBDOMAINS=(
    "gateway.discord.gg"
    "cdn.discordapp.com"
    "media.discordapp.net"
    "api.discord.com"
    "status.discord.com"
)

for domain in "${DISCORD_SUBDOMAINS[@]}"; do
    DNS_RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DNS_RESULT" != "$VPS_IP" ] && [ "$DNS_RESULT" != "FAILED" ]; then
        echo -e "${YELLOW}⚠ $domain resolves to $DNS_RESULT (not VPS IP)${NC}"
    elif [ "$DNS_RESULT" == "FAILED" ]; then
        echo -e "${RED}❌ $domain DNS resolution failed${NC}"
    else
        echo -e "${GREEN}✅ $domain → $DNS_RESULT${NC}"
    fi
done

# Activision common subdomains
ACTIVISION_SUBDOMAINS=(
    "profile.callofduty.com"
    "s2s.callofduty.com"
    "accounts.callofduty.com"
    "profile.activision.com"
)

for domain in "${ACTIVISION_SUBDOMAINS[@]}"; do
    DNS_RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DNS_RESULT" != "$VPS_IP" ] && [ "$DNS_RESULT" != "FAILED" ]; then
        echo -e "${YELLOW}⚠ $domain resolves to $DNS_RESULT (not VPS IP)${NC}"
    elif [ "$DNS_RESULT" == "FAILED" ]; then
        echo -e "${RED}❌ $domain DNS resolution failed${NC}"
    else
        echo -e "${GREEN}✅ $domain → $DNS_RESULT${NC}"
    fi
done

# Step 6: Check logs
echo ""
echo -e "${YELLOW}[6/6] Checking recent logs for errors...${NC}"

if [ -f /var/log/sniproxy/https_access.log ]; then
    RECENT_ERRORS=$(tail -50 /var/log/sniproxy/https_access.log | grep -iE "discord|activision|callofduty" | tail -5 || echo "")
    if [ -n "$RECENT_ERRORS" ]; then
        echo -e "${BLUE}Recent Discord/Activision connections:${NC}"
        echo "$RECENT_ERRORS"
    else
        echo -e "${YELLOW}⚠ No recent Discord/Activision connections in logs${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SNIProxy log file not found${NC}"
fi

echo ""
echo "================================================"
echo "Diagnosis Complete"
echo "================================================"
echo ""
echo "NEXT STEPS:"
echo "───────────"
echo "1. Test DNS resolution:"
echo "   dig @127.0.0.1 discord.com"
echo "   dig @127.0.0.1 activision.com"
echo ""
echo "2. Monitor logs in real-time:"
echo "   ./scripts/maintenance/monitor-logs.sh"
echo ""
echo "3. Check SNIProxy logs:"
echo "   tail -f /var/log/sniproxy/https_access.log"
echo ""
echo "4. If still not working, check if your router is:"
echo "   - Using the DoH endpoint correctly"
echo "   - Not caching old DNS responses"
echo "   - Allowing connections to Discord/Activision servers"
echo ""


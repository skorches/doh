#!/bin/bash

# Diagnose Discord connectivity issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Discord Connectivity Diagnosis"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    VPS_IP="94.154.131.92"  # From hosts file
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Check DNS resolution
echo -e "${YELLOW}[1/6] Checking DNS resolution...${NC}"
DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
DISCORDAPP_DNS=$(timeout 3 dig @127.0.0.1 discordapp.com +short 2>/dev/null | head -1 || echo "FAILED")
GATEWAY_DNS=$(timeout 3 dig @127.0.0.1 gateway.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS"
echo "  discordapp.com → $DISCORDAPP_DNS"
echo "  gateway.discord.gg → $GATEWAY_DNS"

if [ "$DISCORD_DNS" == "$VPS_IP" ] && [ "$DISCORDAPP_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolving to VPS IP${NC}"
else
    echo -e "${RED}❌ DNS not resolving to VPS IP${NC}"
    echo "   Expected: $VPS_IP"
fi

# Step 2: Check SNIProxy status
echo ""
echo -e "${YELLOW}[2/6] Checking SNIProxy status...${NC}"
if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "${RED}❌ SNIProxy not listening on port 443${NC}"
    fi
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
fi

# Step 3: Check SNIProxy config for Discord
echo ""
echo -e "${YELLOW}[3/6] Checking SNIProxy configuration...${NC}"
if grep -q "discord" /etc/sniproxy.conf; then
    echo -e "${GREEN}✅ Discord rules found in SNIProxy config${NC}"
    echo "  Rules:"
    grep -i discord /etc/sniproxy.conf | sed 's/^/    /'
else
    echo -e "${RED}❌ No Discord rules in SNIProxy config${NC}"
fi

# Step 4: Test HTTPS connectivity
echo ""
echo -e "${YELLOW}[4/6] Testing HTTPS connectivity...${NC}"
echo "Testing discord.com through VPS..."
DISCORD_HTTPS=$(timeout 5 curl -s -I --resolve discord.com:443:$VPS_IP https://discord.com 2>&1 | head -1 || echo "FAILED")
if echo "$DISCORD_HTTPS" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
    echo -e "${GREEN}✅ Discord HTTPS reachable${NC}"
else
    echo -e "${YELLOW}⚠ Discord HTTPS test: $DISCORD_HTTPS${NC}"
fi

# Step 5: Check SNIProxy logs for Discord
echo ""
echo -e "${YELLOW}[5/6] Checking SNIProxy logs for Discord connections...${NC}"
if [ -f /var/log/sniproxy/https_access.log ]; then
    RECENT_DISCORD=$(tail -50 /var/log/sniproxy/https_access.log | grep -i discord | tail -5 || echo "")
    if [ -n "$RECENT_DISCORD" ]; then
        echo -e "${BLUE}Recent Discord connections:${NC}"
        echo "$RECENT_DISCORD" | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ No recent Discord connections in logs${NC}"
        echo "  This might mean Discord isn't connecting through SNIProxy"
    fi
else
    echo -e "${YELLOW}⚠ SNIProxy log file not found${NC}"
fi

# Step 6: Check for missing Discord subdomains
echo ""
echo -e "${YELLOW}[6/6] Checking for missing Discord subdomains...${NC}"
DISCORD_SUBDOMAINS=(
    "gateway.discord.gg"
    "cdn.discordapp.com"
    "media.discordapp.net"
    "api.discord.com"
    "status.discord.com"
    "gateway.discord.com"
    "images-ext-1.discordapp.net"
    "images-ext-2.discordapp.net"
    "media.discordapp.com"
    "voice.discord.gg"
    "voice-us-east.discord.gg"
    "voice-us-west.discord.gg"
    "voice-eu.discord.gg"
    "voice-asia.discord.gg"
)

MISSING_COUNT=0
for domain in "${DISCORD_SUBDOMAINS[@]}"; do
    DNS_RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DNS_RESULT" != "$VPS_IP" ] && [ "$DNS_RESULT" != "FAILED" ]; then
        echo -e "${YELLOW}⚠ $domain → $DNS_RESULT (not VPS IP)${NC}"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ $MISSING_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All checked Discord subdomains resolve to VPS IP${NC}"
else
    echo -e "${YELLOW}⚠ Found $MISSING_COUNT subdomains not resolving to VPS IP${NC}"
fi

echo ""
echo "================================================"
echo "Diagnosis Complete"
echo "================================================"
echo ""
echo "COMMON DISCORD ISSUES:"
echo "──────────────────────"
echo "1. Discord uses WebSocket (ws://) connections that bypass SNIProxy"
echo "2. Discord voice uses UDP (not TCP/443) - SNIProxy only handles TCP"
echo "3. Missing subdomains in hosts file"
echo "4. Discord client might be detecting proxy"
echo ""
echo "SOLUTIONS:"
echo "──────────"
echo "1. Add missing Discord subdomains to hosts file"
echo "2. Check if Discord needs WebSocket proxy (separate setup)"
echo "3. Check SNIProxy logs: tail -f /var/log/sniproxy/https_access.log"
echo "4. Test Discord web app: https://discord.com/app"
echo ""


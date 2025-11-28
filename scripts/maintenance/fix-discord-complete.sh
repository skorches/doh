#!/bin/bash

# Complete fix for Discord connectivity

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
echo "Complete Discord Fix"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    VPS_IP="94.154.131.92"  # From hosts file
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Start SNIProxy
echo -e "${YELLOW}[1/4] Starting SNIProxy...${NC}"
if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is already running${NC}"
else
    systemctl start sniproxy
    sleep 2
    
    if systemctl is-active --quiet sniproxy; then
        echo -e "${GREEN}✅ SNIProxy started${NC}"
    else
        echo -e "${RED}❌ Failed to start SNIProxy${NC}"
        echo "Checking logs..."
        journalctl -u sniproxy -n 10 --no-pager
        exit 1
    fi
fi

# Verify SNIProxy is listening
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
else
    echo -e "${YELLOW}⚠ SNIProxy running but not listening on 443${NC}"
fi

# Step 2: Add missing Discord voice subdomains
echo ""
echo -e "${YELLOW}[2/4] Adding missing Discord voice subdomains...${NC}"

HOSTS_FILE="/root/doh/coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    exit 1
fi

# Backup
cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"
echo -e "${GREEN}✅ Backed up hosts file${NC}"

# Check if voice subdomains already exist
if grep -q "voice.discord.gg" "$HOSTS_FILE"; then
    echo -e "${GREEN}✅ Discord voice subdomains already in hosts file${NC}"
else
    echo -e "${YELLOW}Adding Discord voice subdomains...${NC}"
    cat >> "$HOSTS_FILE" << EOFVOICE

# === DISCORD VOICE (Added by fix script) ===
$VPS_IP voice.discord.gg
$VPS_IP voice-us-east.discord.gg
$VPS_IP voice-us-west.discord.gg
$VPS_IP voice-eu.discord.gg
$VPS_IP voice-asia.discord.gg
$VPS_IP voice-us-central.discord.gg
$VPS_IP voice-us-south.discord.gg
$VPS_IP voice-eu-west.discord.gg
$VPS_IP voice-eu-central.discord.gg
$VPS_IP voice-singapore.discord.gg
$VPS_IP voice-sydney.discord.gg
$VPS_IP voice-amsterdam.discord.gg
$VPS_IP voice-frankfurt.discord.gg
$VPS_IP voice-london.discord.gg
$VPS_IP voice-russia.discord.gg
$VPS_IP voice-brazil.discord.gg
$VPS_IP voice-hongkong.discord.gg
$VPS_IP voice-japan.discord.gg
$VPS_IP voice-southafrica.discord.gg
$VPS_IP voice-india.discord.gg
EOFVOICE
    echo -e "${GREEN}✅ Added Discord voice subdomains${NC}"
fi

# Step 3: Restart CoreDNS
echo ""
echo -e "${YELLOW}[3/4] Restarting CoreDNS...${NC}"
cd /root/doh
docker compose restart coredns-smartdns 2>/dev/null || docker-compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS restarted${NC}"
else
    echo -e "${RED}❌ CoreDNS failed to restart${NC}"
    exit 1
fi

# Step 4: Verify DNS resolution
echo ""
echo -e "${YELLOW}[4/4] Verifying DNS resolution...${NC}"
sleep 2

DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
VOICE_DNS=$(timeout 3 dig @127.0.0.1 voice.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")
GATEWAY_DNS=$(timeout 3 dig @127.0.0.1 gateway.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS"
echo "  voice.discord.gg → $VOICE_DNS"
echo "  gateway.discord.gg → $GATEWAY_DNS"

if [ "$DISCORD_DNS" == "$VPS_IP" ] && [ "$VOICE_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolving correctly!${NC}"
else
    echo -e "${YELLOW}⚠ Some domains may need a moment to update${NC}"
fi

echo ""
echo "================================================"
echo "✅ Discord Fix Complete!"
echo "================================================"
echo ""
echo "WHAT WAS FIXED:"
echo "───────────────"
echo "✅ SNIProxy started"
echo "✅ Added Discord voice subdomains to hosts file"
echo "✅ CoreDNS restarted"
echo ""
echo "NEXT STEPS:"
echo "───────────"
echo "1. Restart your router to clear DNS cache"
echo "2. Restart Discord client"
echo "3. Test Discord connection"
echo ""
echo "NOTE: Discord voice uses UDP, which SNIProxy doesn't handle."
echo "      If voice still doesn't work, you may need a UDP proxy."
echo ""


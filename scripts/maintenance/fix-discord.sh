#!/bin/bash

# Comprehensive Discord connectivity fix and diagnosis

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP: " VPS_IP
fi

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

HOSTS_FILE="$DOH_DIR/coredns/xbox-hosts"

echo "================================================"
echo "Discord Connectivity Fix & Diagnosis"
echo "================================================"
echo ""
echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Step 1: Diagnose
echo -e "${CYAN}[1/5] Diagnosing Discord connectivity...${NC}"
echo ""

DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
DISCORDAPP_DNS=$(timeout 3 dig @127.0.0.1 discordapp.com +short 2>/dev/null | head -1 || echo "FAILED")
GATEWAY_DNS=$(timeout 3 dig @127.0.0.1 gateway.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")

echo "DNS Resolution:"
echo "  discord.com → $DISCORD_DNS"
echo "  discordapp.com → $DISCORDAPP_DNS"
echo "  gateway.discord.gg → $GATEWAY_DNS"

if [ "$DISCORD_DNS" == "$VPS_IP" ] && [ "$DISCORDAPP_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolving correctly${NC}"
else
    echo -e "${RED}❌ DNS not resolving to VPS IP${NC}"
fi

# Check SNIProxy
echo ""
if ps aux | grep -q "[s]niproxy"; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    fi
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
fi

# Check CoreDNS
if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS is running${NC}"
else
    echo -e "${RED}❌ CoreDNS is NOT running${NC}"
fi

# Step 2: Fix SNIProxy if needed
echo ""
echo -e "${CYAN}[2/5] Checking SNIProxy...${NC}"
if ! ps aux | grep -q "[s]niproxy"; then
    echo -e "${YELLOW}Starting SNIProxy...${NC}"
    systemctl start sniproxy
    sleep 2
fi

# Fix systemd tracking
if [ ! -f /etc/systemd/system/sniproxy.service.d/override.conf ]; then
    mkdir -p /etc/systemd/system/sniproxy.service.d
    cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOF'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOF
    systemctl daemon-reload
fi

# Step 3: Check and update hosts file
echo ""
echo -e "${CYAN}[3/5] Checking hosts file...${NC}"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ Hosts file not found${NC}"
    exit 1
fi

# Backup
cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"

# Check if Discord domains exist
if ! grep -q "^$VPS_IP.*discord" "$HOSTS_FILE"; then
    echo -e "${YELLOW}Adding Discord domains...${NC}"
    cat >> "$HOSTS_FILE" << EOFDISCORD

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
EOFDISCORD
fi

# Check if voice subdomains exist
if ! grep -q "voice.discord.gg" "$HOSTS_FILE"; then
    echo -e "${YELLOW}Adding Discord voice subdomains...${NC}"
    cat >> "$HOSTS_FILE" << EOFVOICE

# === DISCORD VOICE ===
$VPS_IP voice.discord.gg
$VPS_IP voice-us-east.discord.gg
$VPS_IP voice-us-west.discord.gg
$VPS_IP voice-eu.discord.gg
$VPS_IP voice-asia.discord.gg
EOFVOICE
fi

# Step 4: Restart CoreDNS
echo ""
echo -e "${CYAN}[4/5] Restarting CoreDNS...${NC}"
cd "$DOH_DIR"
docker compose restart coredns-smartdns 2>/dev/null || docker-compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

# Step 5: Verify
echo ""
echo -e "${CYAN}[5/5] Verifying fix...${NC}"
sleep 2

DISCORD_DNS_NEW=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
VOICE_DNS=$(timeout 3 dig @127.0.0.1 voice.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")

echo "  discord.com → $DISCORD_DNS_NEW"
echo "  voice.discord.gg → $VOICE_DNS"

if [ "$DISCORD_DNS_NEW" == "$VPS_IP" ] && [ "$VOICE_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolving correctly!${NC}"
else
    echo -e "${YELLOW}⚠ DNS may need a moment to update${NC}"
fi

echo ""
echo "================================================"
echo "✅ Discord Fix Complete"
echo "================================================"
echo ""
echo "IMPORTANT:"
echo "──────────"
echo "✅ Text chat: Works via SNIProxy (automatic)"
echo "❌ Voice chat: Requires UDP proxy (see docs/XBOX_DISCORD_VOICE.md)"
echo ""
echo "For voice chat on PC/Phone:"
echo "  Configure Discord → Settings → Connections → Proxy"
echo "  Proxy: $VPS_IP:1080 (if 3proxy is set up)"
echo "  Type: SOCKS5"
echo ""



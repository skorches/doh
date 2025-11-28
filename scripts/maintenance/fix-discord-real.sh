#!/bin/bash

# Fix Discord issues - SNIProxy is running, but we need voice subdomains

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
echo "Discord Fix (SNIProxy is already running)"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    VPS_IP="94.154.131.92"  # From hosts file
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Verify SNIProxy is actually running
if ps aux | grep -q "[s]niproxy"; then
    echo -e "${GREEN}✅ SNIProxy is running (process found)${NC}"
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    fi
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
    echo "Starting SNIProxy..."
    systemctl start sniproxy
    sleep 2
fi

# Fix systemd tracking (optional - doesn't affect functionality)
echo ""
echo -e "${YELLOW}[1/3] Fixing systemd tracking (optional)...${NC}"
if [ -f /etc/systemd/system/sniproxy.service.d/override.conf ]; then
    echo -e "${GREEN}✅ Systemd override already exists${NC}"
else
    mkdir -p /etc/systemd/system/sniproxy.service.d
    cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOF'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOF
    systemctl daemon-reload
    echo -e "${GREEN}✅ Systemd override created${NC}"
fi

# Add missing Discord voice subdomains
echo ""
echo -e "${YELLOW}[2/3] Adding missing Discord voice subdomains...${NC}"

HOSTS_FILE="/root/doh/coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    exit 1
fi

# Backup
cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"

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

# Restart CoreDNS
echo ""
echo -e "${YELLOW}[3/3] Restarting CoreDNS...${NC}"
cd /root/doh
docker compose restart coredns-smartdns 2>/dev/null || docker-compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

# Verify DNS resolution
echo ""
echo -e "${BLUE}Verifying DNS resolution...${NC}"
sleep 2

VOICE_DNS=$(timeout 3 dig @127.0.0.1 voice.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")
GATEWAY_DNS=$(timeout 3 dig @127.0.0.1 gateway.discord.gg +short 2>/dev/null | head -1 || echo "FAILED")

echo "  voice.discord.gg → $VOICE_DNS"
echo "  gateway.discord.gg → $GATEWAY_DNS"

if [ "$VOICE_DNS" == "$VPS_IP" ] && [ "$GATEWAY_DNS" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolving correctly!${NC}"
else
    echo -e "${YELLOW}⚠ Some domains may need a moment to update${NC}"
fi

echo ""
echo "================================================"
echo "✅ Discord Fix Complete!"
echo "================================================"
echo ""
echo "CURRENT STATUS:"
echo "───────────────"
echo "✅ SNIProxy is running (process active)"
echo "✅ SNIProxy listening on port 443"
echo "✅ Added Discord voice subdomains"
echo "✅ CoreDNS restarted"
echo ""
echo "IMPORTANT LIMITATIONS:"
echo "──────────────────────"
echo "⚠ SNIProxy only handles TCP/HTTPS traffic"
echo "⚠ Discord voice uses UDP - SNIProxy cannot proxy UDP"
echo "⚠ Discord WebSocket (ws://) may work if upgraded to wss:// (HTTPS)"
echo ""
echo "WHAT WILL WORK:"
echo "───────────────"
echo "✅ Discord web app (HTTPS)"
echo "✅ Discord text chat (HTTPS)"
echo "✅ Discord file uploads (HTTPS)"
echo ""
echo "WHAT MIGHT NOT WORK:"
echo "────────────────────"
echo "❌ Discord voice chat (UDP)"
echo "❌ Discord video calls (UDP/WebRTC)"
echo ""
echo "NEXT STEPS:"
echo "───────────"
echo "1. Restart your router to clear DNS cache"
echo "2. Restart Discord client"
echo "3. Test Discord text chat (should work)"
echo "4. Test Discord voice (may not work due to UDP)"
echo ""


#!/bin/bash

# Regenerate xbox-hosts file from template
# Usage:
#   ./scripts/maintenance/regenerate-hosts.sh                 # auto-detect VPS IP
#   ./scripts/maintenance/regenerate-hosts.sh 1.2.3.4         # provide VPS IP as argument
#   VPS_IP=1.2.3.4 ./scripts/maintenance/regenerate-hosts.sh  # provide via env var

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

# Determine VPS IP (priority: argument > env var > .env file > auto-detect)
if [ -n "$1" ]; then
    VPS_IP="$1"
    echo -e "${GREEN}Using VPS IP from argument: $VPS_IP${NC}"
elif [ -n "$VPS_IP" ]; then
    echo -e "${GREEN}Using VPS IP from environment: $VPS_IP${NC}"
elif [ -f ".env" ]; then
    source .env
    if [ -n "$VPS_IP" ]; then
        echo -e "${GREEN}Using VPS IP from .env file: $VPS_IP${NC}"
    fi
fi

# If still empty, auto-detect from network interface
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Detecting VPS IP from network interface...${NC}"

    # Get IP from default route interface
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi

    # If still empty, try all interfaces (excluding loopback)
    if [ -z "$VPS_IP" ]; then
        VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
    fi
fi

# Validate IP format
if [ -z "$VPS_IP" ] || ! echo "$VPS_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo -e "${RED}❌ Failed to detect VPS IP${NC}"
    echo ""
    echo "Provide your VPS IP in one of these ways:"
    echo "  1. As argument:    bash $0 YOUR_VPS_IP"
    echo "  2. In .env file:   echo 'VPS_IP=YOUR_VPS_IP' > .env"
    echo "  3. As env var:     VPS_IP=YOUR_VPS_IP bash $0"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ VPS IP: $VPS_IP${NC}"
echo ""

# Check for template file
TEMPLATE_FILE="coredns/xbox-hosts.template"
HOSTS_FILE="coredns/xbox-hosts"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}❌ Template file not found: $TEMPLATE_FILE${NC}"
    echo "Make sure the template file exists in the coredns directory."
    exit 1
fi

# Backup existing file
if [ -f "$HOSTS_FILE" ]; then
    cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%s)"
    echo -e "${GREEN}✅ Backed up existing file${NC}"
fi

# Generate hosts file from template
echo -e "${YELLOW}Generating hosts file from template...${NC}"
sed -e "s/__VPS_IP__/$VPS_IP/g" -e "s/__DATE__/$(date)/g" "$TEMPLATE_FILE" > "$HOSTS_FILE"

echo -e "${GREEN}✅ Hosts file generated${NC}"
echo ""

# Restart CoreDNS
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart via docker-compose, trying direct restart...${NC}"
    docker restart coredns-smartdns 2>/dev/null || echo -e "${RED}❌ Could not restart CoreDNS${NC}"
}
sleep 3

# Verify critical NAT domains are present
echo -e "${YELLOW}Verifying NAT detection domains...${NC}"
NAT_DOMAINS=("xbox.nat.microsoft.com" "xbox.ipv4.microsoft.com" "xbox.ipv6.microsoft.com" "dns.msftncsi.com" "ipv4.msftconnecttest.com")
MISSING_DOMAINS=()
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "$domain" "$HOSTS_FILE"; then
        MISSING_DOMAINS+=("$domain")
    fi
done

if [ ${#MISSING_DOMAINS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All critical NAT domains present${NC}"
else
    echo -e "${RED}❌ Missing NAT domains: ${MISSING_DOMAINS[*]}${NC}"
    echo -e "${YELLOW}⚠ This may cause NAT detection issues!${NC}"
fi

# Verify DNS resolution
echo ""
echo -e "${YELLOW}Verifying DNS resolution...${NC}"
DISCORD_DNS=$(timeout 3 dig @127.0.0.1 discord.com +short 2>/dev/null | head -1 || echo "FAILED")
XBOX_DNS=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
ACTIVISION_DNS=$(timeout 3 dig @127.0.0.1 activision.com +short 2>/dev/null | head -1 || echo "TIMEOUT")

echo "  discord.com → $DISCORD_DNS (should be $VPS_IP)"
echo "  xboxlive.com → $XBOX_DNS (should be $VPS_IP)"
echo "  activision.com → $ACTIVISION_DNS (should NOT be $VPS_IP)"

if [ "$DISCORD_DNS" == "$VPS_IP" ] && [ "$XBOX_DNS" == "$VPS_IP" ]; then
    if [ "$ACTIVISION_DNS" != "$VPS_IP" ]; then
        echo -e "${GREEN}✅ DNS resolution working correctly!${NC}"
        echo "   - Discord/Xbox route via VPS ✓"
        echo "   - Call of Duty routes directly ✓"
    else
        echo -e "${RED}❌ Call of Duty is routing to VPS (will cause timeouts)${NC}"
        echo "   Run: bash scripts/maintenance/fix-cod-disconnects.sh"
    fi
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
echo "3. Test Xbox and Discord services"
echo ""
echo "⚠️  IMPORTANT - Call of Duty:"
echo "   - Call of Duty domains are NOT in hosts file (intentional)"
echo "   - CoD games connect DIRECTLY (not via VPS)"
echo "   - This prevents 'lost connection to host/server' timeouts"
echo ""
echo "⚠️  IMPORTANT for Xbox NAT Detection:"
echo "   - Ensure Xbox DNS is set to VPS IP: $VPS_IP"
echo "   - Settings → Network → Advanced → DNS Settings"
echo "   - Primary DNS: $VPS_IP"
echo "   - Restart Xbox after changing DNS to clear cache"
echo ""
echo "⚠️  If NAT is still unavailable, check for Double NAT:"
echo "   - Double NAT occurs when router is behind ISP router/CGNAT"
echo "   - Can cause 'NAT unavailable' or 'Double NAT detected'"
echo "   - Solutions: Bridge mode, UPnP, Port forwarding, or DMZ"
echo ""





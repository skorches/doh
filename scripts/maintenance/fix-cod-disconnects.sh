#!/bin/bash

################################################
# Fix Call of Duty Disconnections
# Removes CoD domains from hosts file (they need direct connections)
################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

HOSTS_FILE="coredns/xbox-hosts"

# Detect project root
if [ -f "$HOSTS_FILE" ]; then
    PROJECT_ROOT="."
elif [ -f "../../$HOSTS_FILE" ]; then
    PROJECT_ROOT="../.."
    cd "$PROJECT_ROOT"
else
    echo -e "${RED}❌ Cannot find $HOSTS_FILE${NC}"
    echo "Please run this script from the project root or scripts/maintenance directory"
    exit 1
fi

echo "================================================"
echo "Fixing Call of Duty Disconnections"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "UNKNOWN")
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/4] Backing up hosts file..."
cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.cod-$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}✅ Backup created${NC}"
echo ""

echo "[2/4] Removing Call of Duty domains from hosts file..."
echo "       (CoD needs direct connections for matchmaking/game servers)"
echo ""

# Remove all Call of Duty / Activision domains
sed -i '/^[0-9].*activision\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*www\.activision\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*callofduty\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*www\.callofduty\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*profile\.callofduty\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*s2s\.callofduty\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*accounts\.callofduty\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*profile\.activision\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*sledgehammergames\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*infinityward\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*treyarch\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*activisionblizzard\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*atvi\.com/d' "$HOSTS_FILE"
sed -i '/^[0-9].*www\.atvi\.com/d' "$HOSTS_FILE"

# Also remove from SNIProxy if installed
if [ -f "/etc/sniproxy.conf" ]; then
    echo "       Updating SNIProxy configuration..."
    sed -i '/activision\.com/d' /etc/sniproxy.conf
    sed -i '/callofduty\.com/d' /etc/sniproxy.conf
    sed -i '/sledgehammergames\.com/d' /etc/sniproxy.conf
    sed -i '/infinityward\.com/d' /etc/sniproxy.conf
    sed -i '/treyarch\.com/d' /etc/sniproxy.conf
    sed -i '/activisionblizzard\.com/d' /etc/sniproxy.conf
    sed -i '/atvi\.com/d' /etc/sniproxy.conf
fi

echo -e "${GREEN}✅ Call of Duty domains removed${NC}"
echo ""

echo "[3/4] Restarting services..."
if command -v docker &> /dev/null; then
    docker restart coredns-smartdns 2>/dev/null || true
    echo -e "${GREEN}✅ CoreDNS restarted${NC}"
fi

if command -v systemctl &> /dev/null && systemctl is-active --quiet sniproxy; then
    systemctl restart sniproxy 2>/dev/null || true
    echo -e "${GREEN}✅ SNIProxy restarted${NC}"
fi
echo ""

echo "[4/4] Verifying domains are removed..."
COD_DOMAINS=(
    "activision.com"
    "callofduty.com"
    "profile.callofduty.com"
    "accounts.callofduty.com"
)

ALL_REMOVED=true
for domain in "${COD_DOMAINS[@]}"; do
    if grep -q "^[0-9].*${domain}$" "$HOSTS_FILE"; then
        echo -e "  ${RED}❌ $domain still in hosts file${NC}"
        ALL_REMOVED=false
    else
        echo -e "  ${GREEN}✅ $domain removed (will resolve to real IPs)${NC}"
    fi
done
echo ""

if [ "$ALL_REMOVED" = true ]; then
    echo "================================================"
    echo -e "${GREEN}✅ Call of Duty domains successfully removed!${NC}"
    echo "================================================"
    echo ""
    echo "Call of Duty will now connect DIRECTLY to:"
    echo "  • Matchmaking servers (low latency)"
    echo "  • Game servers (no timeouts)"
    echo "  • Demonware services (for multiplayer)"
    echo ""
    echo "This should fix:"
    echo "  ✅ 'Lost connection to host/server' errors"
    echo "  ✅ Connection timeouts"
    echo "  ✅ Matchmaking issues"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "1. Clear DNS cache on your router/Xbox"
    echo "2. Restart Call of Duty"
    echo "3. Test multiplayer connection"
    echo ""
    echo "If you still have issues, check:"
    echo "  • NAT type (should be Open or Moderate)"
    echo "  • Port 3074 UDP forwarded to Xbox"
    echo "  • UPnP enabled on router"
else
    echo "================================================"
    echo -e "${RED}⚠️  Some domains still present${NC}"
    echo "================================================"
    echo "Manual check required:"
    echo "  cat $HOSTS_FILE | grep -iE 'activision|callofduty'"
fi
echo ""

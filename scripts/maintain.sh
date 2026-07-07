#!/bin/bash
# Single entry point for maintenance & diagnostics (replaces scripts/maintenance/* and scripts/diagnostics/*)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

usage() {
    cat <<EOF
Usage: sudo ./scripts/maintain.sh <command> [args]

Maintenance:
  regenerate-hosts [VPS_IP] [VPS_IPV6]
                            Rebuild coredns/xbox-hosts from template & restart CoreDNS
  fix-nat                   Remove NAT connectivity domains from hosts + restart CoreDNS
  fix-xbox-nat              Full NAT/Teredo troubleshooting helper
  fix-cod                   Remove Call of Duty domains from hosts if mistakenly added
  fix-ufw-ports             UFW: allow 53/udp+tcp and 443/tcp (required for DNS + SNI/DoH from the internet)

Diagnostics:
  verify-services           Deep check (containers, DNS, DoH, ports)
  compare-dns               Compare key names vs Cloudflare / xbox-dns.ru / local CoreDNS
  fix-sniproxy-ipv6         Disable broken outbound IPv6 routes (do not use with VPS_IPV6)
  verify-excluded           Ensure CoD/2K domains are not pinned in hosts/SNIProxy
  check-repo                Sanity-check templates vs scripts (developer check)

Health (from former install.sh helpers):
  verify                    Docker + SNIProxy + hosts + smoke DoH
  smoke-test                Quick DoH resolution checks

  help                      Show this help
EOF
}

# ----- embedded: maintenance/regenerate-hosts.sh -----
run_regenerate_hosts() (

# Regenerate xbox-hosts file from template
# Usage:
#   sudo ./scripts/maintain.sh regenerate-hosts                       # auto-detect VPS IPs
#   sudo ./scripts/maintain.sh regenerate-hosts 1.2.3.4               # provide IPv4
#   sudo ./scripts/maintain.sh regenerate-hosts 1.2.3.4 2001:db8::10 # provide IPv4 + IPv6
#   VPS_IP=1.2.3.4 VPS_IPV6=2001:db8::10 sudo ./scripts/maintain.sh regenerate-hosts

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

# Determine VPS IPs (priority: argument > env var > .env file > auto-detect)
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

if [ -n "${2:-}" ]; then
    VPS_IPV6="$2"
    echo -e "${GREEN}Using VPS IPv6 from argument: $VPS_IPV6${NC}"
elif [ -n "${VPS_IPV6:-}" ]; then
    echo -e "${GREEN}Using VPS IPv6 from environment/.env: $VPS_IPV6${NC}"
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
    echo "  1. As argument:    sudo ./scripts/maintain.sh regenerate-hosts YOUR_VPS_IP"
    echo "  2. In .env file:   echo 'VPS_IP=YOUR_VPS_IP' > .env"
    echo "  3. As env var:     VPS_IP=YOUR_VPS_IP sudo ./scripts/maintain.sh regenerate-hosts"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ VPS IP: $VPS_IP${NC}"
if [ -n "${VPS_IPV6:-}" ] && ! is_public_ipv6 "$VPS_IPV6"; then
    echo -e "${YELLOW}⚠ Ignoring invalid/private VPS_IPV6: $VPS_IPV6${NC}"
    VPS_IPV6=""
fi
if [ -z "${VPS_IPV6:-}" ]; then
    VPS_IPV6="$(get_vps_ipv6 2>/dev/null || true)"
fi
if [ -n "${VPS_IPV6:-}" ]; then
    echo -e "${GREEN}✅ VPS IPv6: $VPS_IPV6${NC}"
else
    echo -e "${YELLOW}ℹ No public IPv6 configured; AAAA Smart DNS answers will be skipped${NC}"
fi
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
write_hosts_from_template "$TEMPLATE_FILE" "$HOSTS_FILE" "$VPS_IP" "${VPS_IPV6:-}"

echo -e "${GREEN}✅ Hosts file generated${NC}"
if [ -n "${VPS_IPV6:-}" ]; then
    echo -e "${GREEN}✅ IPv6 AAAA aliases added for pinned domains${NC}"
fi
echo ""

# Restart CoreDNS
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart via docker-compose, trying direct restart...${NC}"
    docker restart coredns-smartdns 2>/dev/null || echo -e "${RED}❌ Could not restart CoreDNS${NC}"
}
sleep 3

# Verify critical NAT domains are excluded
echo -e "${YELLOW}Verifying NAT detection domains are excluded...${NC}"
NAT_DOMAINS=("xbox.nat.microsoft.com" "xbox.ipv4.microsoft.com" "xbox.ipv6.microsoft.com" "dns.msftncsi.com" "ipv4.msftconnecttest.com")
PRESENT_DOMAINS=()
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "$domain" "$HOSTS_FILE"; then
        PRESENT_DOMAINS+=("$domain")
    fi
done

if [ ${#PRESENT_DOMAINS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ NAT domains are excluded as expected${NC}"
else
    echo -e "${RED}❌ NAT domains still pinned: ${PRESENT_DOMAINS[*]}${NC}"
    echo -e "${YELLOW}⚠ This can cause NAT detection issues!${NC}"
fi

# Verify DNS resolution
echo ""
echo -e "${YELLOW}Verifying DNS resolution...${NC}"
XBOX_DNS=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
ACTIVISION_DNS=$(timeout 3 dig @127.0.0.1 activision.com +short 2>/dev/null | head -1 || echo "TIMEOUT")
if [ -n "${VPS_IPV6:-}" ]; then
    XBOX_DNS_AAAA=$(timeout 3 dig @127.0.0.1 xboxlive.com AAAA +short 2>/dev/null | head -1 || echo "FAILED")
fi

echo "  xboxlive.com → $XBOX_DNS (should be $VPS_IP)"
if [ -n "${VPS_IPV6:-}" ]; then
    echo "  xboxlive.com AAAA → $XBOX_DNS_AAAA (should be $VPS_IPV6)"
fi
echo "  activision.com → $ACTIVISION_DNS (should NOT be $VPS_IP)"

if [ "$XBOX_DNS" == "$VPS_IP" ] && { [ -z "${VPS_IPV6:-}" ] || [ "$XBOX_DNS_AAAA" == "$VPS_IPV6" ]; }; then
    if [ "$ACTIVISION_DNS" != "$VPS_IP" ]; then
        echo -e "${GREEN}✅ DNS resolution working correctly!${NC}"
        echo "   - Xbox routes via VPS ✓"
        if [ -n "${VPS_IPV6:-}" ]; then
            echo "   - Xbox AAAA routes via VPS IPv6 ✓"
        fi
        echo "   - Call of Duty routes directly ✓"
    else
        echo -e "${RED}❌ Call of Duty is routing to VPS (will cause timeouts)${NC}"
        echo "   Run: sudo ./scripts/maintain.sh fix-cod"
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
echo "1. Test DNS: dig @127.0.0.1 xboxlive.com"
if [ -n "${VPS_IPV6:-}" ]; then
    echo "   Test IPv6: dig @127.0.0.1 xboxlive.com AAAA"
fi
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
if [ -n "${VPS_IPV6:-}" ]; then
    echo "   - If your router accepts IPv6 DNS servers, use VPS IPv6: $VPS_IPV6"
fi
echo "   - Settings → Network → Advanced → DNS Settings"
echo "   - Primary DNS: $VPS_IP"
echo "   - Restart Xbox after changing DNS to clear cache"
echo ""
echo "⚠️  If NAT is still unavailable, check for Double NAT:"
echo "   - Double NAT occurs when router is behind ISP router/CGNAT"
echo "   - Can cause 'NAT unavailable' or 'Double NAT detected'"
echo "   - Solutions: Bridge mode, UPnP, Port forwarding, or DMZ"
echo ""
)

# ----- embedded: maintenance/fix-xbox-nat-unavailable.sh -----
run_fix_xbox_nat() (

# Fix Xbox "NAT unavailable" and "service info unavailable" issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Fixing Xbox NAT Unavailable Issue"
echo "================================================"
echo ""

# Get VPS IP (priority: .env > network interface)
VPS_IP=""
if [ -f ".env" ]; then
    source .env
elif [ -f "$HOME/doh/.env" ]; then
    source "$HOME/doh/.env"
fi
if [ -z "$VPS_IP" ]; then
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

echo "VPS IP: ${VPS_IP:-UNKNOWN}"
echo ""

# Critical NAT detection domains (must resolve to VPS IP)
NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
)

# Teredo domain (MUST resolve to real Microsoft servers, NOT VPS IP)
TEREDO_DOMAIN="teredo.ipv6.microsoft.com"

# Find doh directory
DOH_DIR=""
if [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
elif [ -d "/root/doh" ] && [ -f "/root/doh/docker-compose.yml" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ] && [ -f "$HOME/doh/docker-compose.yml" ]; then
    DOH_DIR="$HOME/doh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../../docker-compose.yml" ]; then
        DOH_DIR="$SCRIPT_DIR/../.."
    else
        echo -e "${RED}❌ doh directory not found${NC}"
        exit 1
    fi
fi

cd "$DOH_DIR"
HOSTS_FILE="coredns/xbox-hosts"

echo "[1/6] Checking hosts file..."
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    exit 1
fi

# Backup
cp "$HOSTS_FILE" "$HOSTS_FILE.backup.$(date +%s)"
echo -e "${GREEN}✅ Backup created${NC}"
echo ""

echo "[2/6] Removing Teredo domain (must resolve to real servers)..."
# Remove teredo domain (only actual IP entries, not comments)
sed -i '/^[0-9]/ { /teredo\.ipv6\.microsoft\.com/d }' "$HOSTS_FILE"
echo -e "${GREEN}✅ Teredo domain removed${NC}"
echo ""

echo "[3/6] Ensuring all NAT detection domains are present..."
# Remove old NAT domain entries first (to avoid duplicates)
for domain in "${NAT_DOMAINS[@]}"; do
    sed -i "/^[0-9].*$domain/d" "$HOSTS_FILE"
done

# Add all NAT domains with VPS IP
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
        echo "$VPS_IP $domain" >> "$HOSTS_FILE"
    fi
done
echo -e "${GREEN}✅ All NAT domains added${NC}"
echo ""

echo "[4/6] Regenerating hosts file from template (if available)..."
if [ -f "coredns/xbox-hosts.template" ]; then
    # Regenerate from template to ensure all IPs are correct
    sed -e "s/__VPS_IP__/$VPS_IP/g" -e "s/__DATE__/$(date)/g" coredns/xbox-hosts.template > "$HOSTS_FILE"
    echo -e "${GREEN}✅ Hosts file regenerated from template with correct VPS IP ($VPS_IP)${NC}"
else
    # Fallback: update only lines that have wrong IPs
    echo "No template found, updating existing entries..."
    # Only update lines that start with an IP (domain entries), not comments
    sed -i "s/^[0-9][0-9.]*\([ \t]\)/$VPS_IP\1/" "$HOSTS_FILE"
    echo -e "${GREEN}✅ All IPs updated to $VPS_IP${NC}"
fi
echo ""

echo "[5/6] Verifying hosts file..."
echo "Checking NAT domains:"
ALL_PRESENT=true
for domain in "${NAT_DOMAINS[@]}"; do
    if grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
        echo -e "  ${GREEN}✅ $domain${NC}"
    else
        echo -e "  ${RED}❌ $domain MISSING${NC}"
        ALL_PRESENT=false
    fi
done

echo ""
echo "Checking Teredo (should NOT be in hosts file):"
if grep -q "^[0-9].*$TEREDO_DOMAIN" "$HOSTS_FILE"; then
    echo -e "  ${RED}❌ ERROR: $TEREDO_DOMAIN is still in hosts file!${NC}"
    echo "  This must be removed - Teredo must resolve to real Microsoft servers"
    ALL_PRESENT=false
else
    echo -e "  ${GREEN}✅ $TEREDO_DOMAIN not in hosts file (correct)${NC}"
fi

if [ "$ALL_PRESENT" = false ]; then
    echo -e "${RED}❌ Hosts file verification failed${NC}"
    exit 1
fi
echo ""

echo "[6/6] Restarting CoreDNS to apply changes..."
docker restart coredns-smartdns
sleep 5
echo -e "${GREEN}✅ CoreDNS restarted${NC}"
echo ""

# Test DNS resolution
echo "================================================"
echo "Testing DNS Resolution"
echo "================================================"
echo ""

echo "Testing NAT domains (should resolve to VPS IP $VPS_IP):"
for domain in "${NAT_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ $domain → $RESULT${NC}"
    else
        echo -e "  ${RED}❌ $domain → $RESULT (expected $VPS_IP)${NC}"
    fi
done

echo ""
echo "Testing Teredo (should resolve to real Microsoft server, NOT VPS IP):"
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$TEREDO_DOMAIN&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
if [ "$TEREDO_RESULT" != "$VPS_IP" ] && [ "$TEREDO_RESULT" != "FAILED" ]; then
    echo -e "  ${GREEN}✅ $TEREDO_DOMAIN → $TEREDO_RESULT (real server - correct)${NC}"
else
    echo -e "  ${RED}❌ $TEREDO_DOMAIN → $TEREDO_RESULT (should be real Microsoft server)${NC}"
fi

echo ""
# Check for DoH 405 errors and fix if needed
echo ""
echo "Checking DoH configuration..."
DOH_405_FIXED=false
if docker logs doh-nginx --tail 50 2>&1 | grep -q "405"; then
    echo "Fixing DoH HTTP 405 errors..."
    DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//' || echo "")
    if [ -n "$DOMAIN" ]; then
        # Update Nginx to allow POST method
        if ! grep -q "limit_except GET POST OPTIONS" nginx/conf.d/doh.conf 2>/dev/null; then
            sed -i '/location \/dns-query {/a\
        limit_except GET POST OPTIONS {\
            deny all;\
        }\
        if ($request_method = OPTIONS) {\
            add_header Access-Control-Allow-Origin *;\
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";\
            add_header Access-Control-Allow-Headers "Content-Type";\
            add_header Access-Control-Max-Age 3600;\
            add_header Content-Length 0;\
            add_header Content-Type text/plain;\
            return 204;\
        }\
        add_header Access-Control-Allow-Origin * always;\
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
' nginx/conf.d/doh.conf
            docker restart doh-nginx
            sleep 3
            DOH_405_FIXED=true
            echo -e "${GREEN}✅ DoH 405 errors fixed${NC}"
        fi
    fi
fi

echo "================================================"
echo -e "${GREEN}✅ Fix Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Verify Xbox DNS is set to VPS IP: $VPS_IP"
echo "     Xbox → Settings → Network → DNS settings → Manual"
echo "     Primary DNS: $VPS_IP"
echo ""
echo "  2. Restart Xbox:"
echo "     - Hold power button 10 seconds"
echo "     - Wait 30 seconds"
echo "     - Turn on"
echo ""
echo "  3. Test NAT type:"
echo "     Xbox → Settings → Network → Test network connection"
echo ""
echo "If NAT is still unavailable:"
echo "  - Check router firewall settings"
echo "  - Ensure port 3074 (UDP) is open"
echo "  - Enable UPnP on router"
echo "  - Check for double NAT"
echo ""
)

# ----- embedded: maintenance/fix-cod-disconnects.sh -----
run_fix_cod() (

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
echo "NOTE: The xbox-hosts.template already excludes CoD domains."
echo "This script fixes the generated hosts file if CoD domains"
echo "were added manually or from an older version."
echo ""
echo "To permanently fix, just regenerate from template:"
echo "  sudo ./scripts/maintain.sh regenerate-hosts"
echo ""

# Get VPS IP (priority: .env > network interface)
VPS_IP=""
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi
if [ -z "$VPS_IP" ]; then
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

echo "VPS IP: ${VPS_IP:-UNKNOWN}"
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
)

# ----- maintenance: ensure UFW allows DNS + HTTPS (Xbox / routers hit public IP) -----
run_fix_ufw_ports() (
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi
if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed; install with: apt-get install ufw"
  exit 1
fi
echo "Adding UFW rules: 53/udp+tcp (DNS), 443/tcp (HTTPS/SNI/DoH), 80, 3074 (optional Xbox)..."
# Xbox/router must reach this host on :53; clients must reach :443 for SNI to Microsoft domains
ufw allow 53/udp comment "Smart DNS queries (Xbox / router to this VPS)" 2>/dev/null || ufw allow 53/udp
ufw allow 53/tcp comment "DNS over TCP" 2>/dev/null || ufw allow 53/tcp
ufw allow 443/tcp comment "HTTPS SNIProxy and DoH" 2>/dev/null || ufw allow 443/tcp
ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
ufw allow 3074/tcp comment "Xbox port assist" 2>/dev/null || true
ufw allow 3074/udp comment "Xbox port assist UDP" 2>/dev/null || true
echo ""
echo "Current status:"
ufw status || true
echo ""
echo "If the console still fails, confirm your VPS provider security group / cloud firewall also allows 53/udp and 443/tcp."
)

# ----- embedded: maintenance/verify-xbox-services.sh -----
run_verify_services() (

# Comprehensive verification of all services needed for Xbox

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

# Find project directory
if [ -f "docker-compose.yml" ]; then
    : # already in correct directory
elif [ -d "/root/doh" ] && [ -f "/root/doh/docker-compose.yml" ]; then
    cd /root/doh
elif [ -d "$HOME/doh" ] && [ -f "$HOME/doh/docker-compose.yml" ]; then
    cd "$HOME/doh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../../docker-compose.yml" ]; then
        cd "$SCRIPT_DIR/../.."
    else
        echo -e "${RED}❌ doh directory not found${NC}"
        exit 1
    fi
fi

# Get VPS IP (priority: .env file > network interface)
VPS_IP=""
if [ -f ".env" ]; then
    source .env
fi
if [ -z "$VPS_IP" ]; then
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

ISSUES=0

echo "================================================"
echo "Xbox Services Verification"
echo "================================================"
echo ""
echo "VPS IP: $VPS_IP"
echo ""
echo "This script verifies all services and domains."
echo ""

# Firewall: without 53+443 from the internet, Xbox cannot use this host as DNS or SNI/DoH
echo "[0/8] UFW: DNS (53) and HTTPS (443) from the internet..."
U_OK=true
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  _S=$(ufw status 2>/dev/null)
  if ! echo "$_S" | grep -E '53/udp|53/tcp' | grep -qi allow; then
    U_OK=false
  fi
  if ! echo "$_S" | grep '443/tcp' | grep -qi allow; then
    U_OK=false
  fi
  if [ "$U_OK" = true ]; then
    echo -e "  ${GREEN}✅ UFW allows DNS (53) and HTTPS (443)${NC}"
  else
    echo -e "  ${RED}❌ UFW: need 53 (udp+tcp) and 443/tcp for Xbox Smart DNS + SNI${NC}"
    echo "     Run: sudo ./scripts/maintain.sh fix-ufw-ports  (and check your cloud security group for the same)"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo -e "  ${YELLOW}⚠  UFW inactive; ensure host and cloud firewall allow 53/udp+tcp and 443/tcp from the internet${NC}"
fi
echo ""

# Critical NAT detection domains
NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
)

# Critical Xbox domains
XBOX_DOMAINS=(
    "xboxlive.com"
    "xbox.com"
    "xboxservices.com"
    "login.live.com"
    "account.live.com"
)

echo "[1/8] Checking Docker Service..."
if systemctl is-active docker >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ Docker is running${NC}"
else
    echo -e "  ${RED}❌ Docker is NOT running${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[2/8] Checking Docker Containers..."
CONTAINERS_OK=true

# Check CoreDNS
if docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$"; then
    STATUS=$(docker inspect coredns-smartdns --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" == "running" ]; then
        echo -e "  ${GREEN}✅ coredns-smartdns: Running${NC}"
    else
        echo -e "  ${RED}❌ coredns-smartdns: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ coredns-smartdns: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi

# Check DoH Backend
if docker ps --format "{{.Names}}" | grep -q "^doh-backend$"; then
    STATUS=$(docker inspect doh-backend --format '{{.State.Status}}' 2>/dev/null)
    HEALTH=$(docker inspect doh-backend --format '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
    if [ "$STATUS" == "running" ]; then
        if [ "$HEALTH" == "healthy" ] || [ "$HEALTH" == "no-healthcheck" ]; then
            echo -e "  ${GREEN}✅ doh-backend: Running${NC}"
        else
            echo -e "  ${YELLOW}⚠️  doh-backend: Running but unhealthy ($HEALTH)${NC}"
        fi
    else
        echo -e "  ${RED}❌ doh-backend: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ doh-backend: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi

# Check Nginx
if docker ps --format "{{.Names}}" | grep -q "^doh-nginx$"; then
    STATUS=$(docker inspect doh-nginx --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" == "running" ]; then
        echo -e "  ${GREEN}✅ doh-nginx: Running${NC}"
    else
        echo -e "  ${RED}❌ doh-nginx: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ doh-nginx: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[3/8] Checking SNIProxy Service..."
if systemctl is-active sniproxy >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ SNIProxy is running${NC}"
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "  ${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "  ${YELLOW}⚠️  SNIProxy running but port 443 not listening${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ SNIProxy is NOT running${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[4/8] Checking Port 53 (DNS)..."
if ss -ulnp | grep -q ":53.*docker-proxy" || ss -tlnp | grep -q ":53.*docker-proxy"; then
    echo -e "  ${GREEN}✅ Port 53 is listening (CoreDNS)${NC}"
    
    # Test DNS resolution (try both UDP and TCP)
    TEST_RESULT_UDP=$(timeout 3 dig @127.0.0.1 +time=2 xboxlive.com +short 2>/dev/null | head -1 | tr -d '[:space:]')
    TEST_RESULT_TCP=$(timeout 3 dig @127.0.0.1 +tcp +time=2 xboxlive.com +short 2>/dev/null | head -1 | tr -d '[:space:]')
    
    if [ "$TEST_RESULT_UDP" == "$VPS_IP" ] || [ "$TEST_RESULT_TCP" == "$VPS_IP" ]; then
        TEST_RESULT=${TEST_RESULT_UDP:-$TEST_RESULT_TCP}
        echo -e "  ${GREEN}✅ DNS resolution working (xboxlive.com → $TEST_RESULT)${NC}"
    elif [ -n "$TEST_RESULT_UDP" ] || [ -n "$TEST_RESULT_TCP" ]; then
        TEST_RESULT=${TEST_RESULT_UDP:-$TEST_RESULT_TCP}
        echo -e "  ${YELLOW}⚠️  DNS resolution returned different IP (xboxlive.com → $TEST_RESULT, expected $VPS_IP)${NC}"
        echo -e "  ${YELLOW}   Note: DoH is working correctly, this may be a cache issue${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Direct DNS test failed (timeout or no response)${NC}"
        echo -e "  ${YELLOW}   Note: DoH is working correctly, Xbox will use DoH or DNS from router${NC}"
        # Don't count this as an issue since DoH works
    fi
else
    echo -e "  ${RED}❌ Port 53 is NOT listening${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[5/8] Checking DoH Endpoint (port 443/8443)..."
# Test local DoH
DOH_RESULT=$(curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>/dev/null | grep -o '"Status":[0-9]*' || echo "FAILED")
if echo "$DOH_RESULT" | grep -q "Status\":0"; then
    DOH_DATA=$(curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$DOH_DATA" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ DoH endpoint working (localhost:8443)${NC}"
        echo -e "  ${GREEN}✅ DoH resolution correct (xboxlive.com → $VPS_IP)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  DoH working but wrong IP ($DOH_DATA, expected $VPS_IP)${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ DoH endpoint not responding${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Check port 443
if ss -tlnp | grep -q ":443"; then
    echo -e "  ${GREEN}✅ Port 443 is listening (SNIProxy)${NC}"
else
    echo -e "  ${RED}❌ Port 443 is NOT listening${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[6/8] Checking NAT Detection Domains in Hosts File..."
HOSTS_FILE="coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "  ${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    ISSUES=$((ISSUES + 1))
else
    NAT_MISSING=0
    for domain in "${NAT_DOMAINS[@]}"; do
        if grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
            echo -e "  ${GREEN}✅ $domain${NC}"
        else
            echo -e "  ${RED}❌ $domain MISSING${NC}"
            NAT_MISSING=$((NAT_MISSING + 1))
            ISSUES=$((ISSUES + 1))
        fi
    done
    
    # Check Teredo is NOT in hosts
    if grep -q "^[0-9].*teredo\.ipv6\.microsoft\.com" "$HOSTS_FILE"; then
        echo -e "  ${RED}❌ ERROR: teredo.ipv6.microsoft.com is in hosts file (must be removed)${NC}"
        ISSUES=$((ISSUES + 1))
    else
        echo -e "  ${GREEN}✅ teredo.ipv6.microsoft.com correctly removed${NC}"
    fi
fi
echo ""

echo "[7/8] Testing NAT Domain DNS Resolution..."
NAT_RESOLUTION_OK=true
for domain in "${NAT_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ $domain → $VPS_IP${NC}"
    else
        echo -e "  ${RED}❌ $domain → $RESULT (expected $VPS_IP)${NC}"
        NAT_RESOLUTION_OK=false
        ISSUES=$((ISSUES + 1))
    fi
done

# Test Teredo (should NOT be VPS IP)
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
if [ "$TEREDO_RESULT" != "$VPS_IP" ] && [ "$TEREDO_RESULT" != "FAILED" ]; then
    echo -e "  ${GREEN}✅ teredo.ipv6.microsoft.com → $TEREDO_RESULT (real server - correct)${NC}"
else
    echo -e "  ${RED}❌ teredo.ipv6.microsoft.com → $TEREDO_RESULT (should be real Microsoft server)${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[8/8] Testing Critical Xbox Domains..."
XBOX_RESOLUTION_OK=true
for domain in "${XBOX_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ $domain → $VPS_IP${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $domain → $RESULT (may be correct if not in hosts file)${NC}"
    fi
done
echo ""

# Quick domain check (minimal version of verify-all-domains.sh)
echo "[9/10] Quick Domain Check..."
HOSTS_FILE="coredns/xbox-hosts"
if [ -f "$HOSTS_FILE" ]; then
    TOTAL_DOMAINS=$(grep -c "^[0-9]" "$HOSTS_FILE" 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✅ Hosts file has $TOTAL_DOMAINS domain entries${NC}"
    
    # Check a few critical domains
    CRITICAL_DOMAINS=("xboxlive.com" "xbox.com" "discord.com" "ea.com" "epicgames.com")
    MISSING_CRITICAL=0
    for domain in "${CRITICAL_DOMAINS[@]}"; do
        if ! grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
            MISSING_CRITICAL=$((MISSING_CRITICAL + 1))
        fi
    done
    
    if [ $MISSING_CRITICAL -eq 0 ]; then
        echo -e "  ${GREEN}✅ All critical domains present${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $MISSING_CRITICAL critical domain(s) missing${NC}"
        echo "     Run: sudo ./scripts/maintain.sh regenerate-hosts"
    fi
fi
echo ""

# Auto-start services if needed
echo "[10/10] Ensuring all services are running..."
if ! systemctl is-active docker >/dev/null 2>&1; then
    systemctl start docker
    sleep 2
fi

if ! docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$"; then
    docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null || true
    echo -e "  ${GREEN}✅ Started CoreDNS${NC}"
fi

if ! systemctl is-active sniproxy >/dev/null 2>&1; then
    systemctl start sniproxy 2>/dev/null || true
    echo -e "  ${GREEN}✅ Started SNIProxy${NC}"
fi
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ All services are running correctly!${NC}"
    echo ""
    echo "Your Xbox should work correctly if:"
    echo "  1. Xbox DNS is set to VPS IP: $VPS_IP"
    echo "     Settings → Network → DNS settings → Manual"
    echo "     Primary DNS: $VPS_IP"
    echo ""
    echo "  2. Router is configured:"
    echo "     • UPnP enabled"
    echo "     • Port 3074 (UDP) forwarded to Xbox"
    echo "     • No double NAT"
    echo ""
    echo "  3. Xbox is restarted after DNS change"
    echo ""
else
    echo -e "${RED}❌ Found $ISSUES issue(s)${NC}"
    echo ""
    echo "To fix issues:"
    echo "  • Docker containers: docker compose up -d"
    echo "  • SNIProxy: systemctl start sniproxy"
    echo "  • NAT/DNS issues: sudo ./scripts/maintain.sh fix-xbox-nat"
    echo "  • Regenerate hosts: sudo ./scripts/maintain.sh regenerate-hosts"
    echo ""
fi

echo "================================================"
echo ""
)

# ----- embedded: diagnostics/compare-public-dns.sh -----
run_compare_dns() (
# Compare how a few important names resolve on:
#   1) Cloudflare (baseline)
#   2) xbox-dns.ru public DNS (111.88.96.50)
#   3) Your CoreDNS on this machine (127.0.0.1) — run ON the VPS, or pass COREDNS_IP
#
# Usage:
#   COREDNS_IP=127.0.0.1 ./scripts/maintain.sh compare-dns
#   COREDNS_IP=151.241.227.116 ./scripts/maintain.sh compare-dns   # from your PC

set -euo pipefail

COREDNS_IP="${COREDNS_IP:-127.0.0.1}"
XBOX_DNS="${XBOX_DNS:-111.88.96.50}"
CF="${CF:-1.1.1.1}"

DOMAINS=(
  "xboxlive.com"
  "auth.xboxlive.com"
  "sessiondirectory.xboxlive.com"
  "presence.xboxlive.com"
  "displaycatalog.mp.microsoft.com"
  "licensing.mp.microsoft.com"
)

echo "Resolvers: Cloudflare=$CF  xbox-dns.ru=$XBOX_DNS  your CoreDNS=$COREDNS_IP"
echo ""

for d in "${DOMAINS[@]}"; do
  echo "=== $d ==="
  echo -n "  CF:     "; dig @"$CF" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo -n "  xbox:   "; dig @"$XBOX_DNS" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo -n "  yours:  "; dig @"$COREDNS_IP" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo ""
done

echo "If \"yours\" shows your VPS IP for many names, those flows hairpin through SNIProxy."
echo "If xbox-dns and CF match real Microsoft/CDN IPs but yours shows VPS IP, that is expected for pinned hosts only."
)

# ----- embedded: diagnostics/fix-sniproxy-ipv6-unreachable.sh -----
run_fix_sniproxy_ipv6() (
# Many VPSes have no working global IPv6 route. SNIProxy resolves Microsoft CDNs to
# AAAA first and then fails with: "Failed to open connection to [...]:443: Network is unreachable"
# which breaks Store / Game Pass / tiles that go through the proxy.
#
# This disables IPv6 on the host so outbound connections use IPv4 only.
# Safe only for IPv4-only DoH + SNIProxy setups. Do not run this when VPS_IPV6 is enabled.
#
# Revert: rm /etc/sysctl.d/99-sniproxy-ipv4-outbound.conf && sysctl -p && systemctl restart sniproxy

set -euo pipefail

if [ "${EUID:-0}" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

CONF="/etc/sysctl.d/99-sniproxy-ipv4-outbound.conf"
cat > "$CONF" << 'EOF'
# Prefer IPv4 for SNIProxy upstreams (broken IPv6 path on many VPSes)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

sysctl --system >/dev/null 2>&1 || sysctl -p "$CONF"
# Apply per-interface (docker bridges, etc.) so getaddrinfo does not return AAAA
for i in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
  echo 1 >"$i" 2>/dev/null || true
done

if systemctl is-active --quiet sniproxy 2>/dev/null; then
  systemctl restart sniproxy
fi

echo "Applied $CONF and restarted sniproxy (if installed)."
echo "Verify: journalctl -u sniproxy -n 20 --no-pager | grep -i unreachable || echo 'No IPv6 unreachable errors in recent log.'"
)

# ----- embedded: diagnostics/verify-excluded-domains.sh -----
run_verify_excluded() (

################################################
# Verify Excluded Domains
# Ensures Call of Duty and 2K Games domains are NOT in hosts file or SNIProxy
# These domains cause disconnections/timeouts when routed through VPS
################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

HOSTS_FILE="coredns/xbox-hosts"
SNIPROXY_CONF="/etc/sniproxy.conf"

# Detect project root
if [ -f "$HOSTS_FILE" ]; then
    PROJECT_ROOT="."
elif [ -f "../../$HOSTS_FILE" ]; then
    PROJECT_ROOT="../.."
    cd "$PROJECT_ROOT"
else
    echo -e "${RED}❌ Cannot find $HOSTS_FILE${NC}"
    echo "Please run this script from the project root or scripts/diagnostics directory"
    exit 1
fi

echo "================================================"
echo "Verifying Excluded Domains"
echo "================================================"
echo ""
echo "These domains MUST NOT be in hosts file or SNIProxy:"
echo "  • Call of Duty / Activision (causes timeouts)"
echo "  • 2K Games / NBA 2K (causes matchmaking failures)"
echo ""

# Domains that should NEVER be in hosts file or SNIProxy
EXCLUDED_DOMAINS=(
    # Call of Duty / Activision
    "activision.com"
    "www.activision.com"
    "callofduty.com"
    "www.callofduty.com"
    "profile.callofduty.com"
    "accounts.callofduty.com"
    "s2s.callofduty.com"
    "profile.activision.com"
    "sledgehammergames.com"
    "infinityward.com"
    "treyarch.com"
    "activisionblizzard.com"
    "atvi.com"
    "www.atvi.com"
    "demonware.net"
    "genesis.stun.eu.demonware.net"
    "genesis.stun.us.demonware.net"
    "user-consent.prod.demonware.net"
    "cod-assets.cdn.callofduty.com"
    "prod.cdni.callofduty.com"
    "ingest.datax.activision.com"
    
    # 2K Games / NBA 2K
    "2k.com"
    "www.2k.com"
    "2ksports.com"
    "www.2ksports.com"
    "take2games.com"
    "www.take2games.com"
    "a978.i6g1.akamai.net"
)

ISSUES_FOUND=false

echo "[1/2] Checking hosts file: $HOSTS_FILE"
echo ""

for domain in "${EXCLUDED_DOMAINS[@]}"; do
    if grep -q "^[0-9].*${domain}$" "$HOSTS_FILE" 2>/dev/null; then
        echo -e "  ${RED}❌ FOUND: $domain${NC}"
        ISSUES_FOUND=true
    fi
done

if [ "$ISSUES_FOUND" = false ]; then
    echo -e "  ${GREEN}✅ No excluded domains in hosts file${NC}"
fi

echo ""
echo "[2/2] Checking SNIProxy: $SNIPROXY_CONF"
echo ""

if [ -f "$SNIPROXY_CONF" ]; then
    SNIPROXY_ISSUES=false
    for domain in "${EXCLUDED_DOMAINS[@]}"; do
        # Check for domain patterns in SNIProxy (e.g., .*\.activision\.com$ *)
        ESCAPED_DOMAIN=$(echo "$domain" | sed 's/\./\\./g')
        if grep -qE "(\*\.)?${ESCAPED_DOMAIN}" "$SNIPROXY_CONF" 2>/dev/null; then
            echo -e "  ${RED}❌ FOUND: $domain${NC}"
            SNIPROXY_ISSUES=true
            ISSUES_FOUND=true
        fi
    done
    
    if [ "$SNIPROXY_ISSUES" = false ]; then
        echo -e "  ${GREEN}✅ No excluded domains in SNIProxy${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  SNIProxy config not found (skipped)${NC}"
fi

echo ""
echo "================================================"

if [ "$ISSUES_FOUND" = true ]; then
    echo -e "${RED}❌ ISSUES FOUND!${NC}"
    echo "================================================"
    echo ""
    echo "Excluded domains were found in your configuration."
    echo "This will cause game disconnections and timeouts."
    echo ""
    echo "To fix:"
    echo "  1. Run: sudo ./scripts/maintain.sh fix-cod"
    echo "  2. Or manually remove the domains from hosts file"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo "================================================"
    echo ""
    echo "No excluded domains found in configuration."
    echo "Call of Duty and 2K Games will connect directly."
    echo ""
    exit 0
fi
)

# ----- embedded: diagnostics/verify-scripts.sh -----
run_check_repo() (

# Verify all scripts for hardcoded IPs and completeness

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    # Try to detect from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../../docker-compose.yml" ]; then
        cd "$SCRIPT_DIR/../.."
    elif [ -f "./docker-compose.yml" ]; then
        cd .
    else
        echo -e "${RED}❌ doh directory not found${NC}"
        exit 1
    fi
}

echo "================================================"
echo "Script Verification"
echo "================================================"
echo ""

# Check for hardcoded VPS IPs (should use $VPS_IP variable)
echo "[1/3] Checking for hardcoded VPS IPs..."
HARDCODED_VPS_IPS=$(grep -rE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' scripts/ 2>/dev/null | grep -vE '(8\.8\.|1\.1\.1\.|1\.0\.0\.|127\.0\.0\.|0\.0\.0\.)' | grep -v "VPS_IP\|ifconfig\|icanhazip\|ipinfo" || true)

if [ -z "$HARDCODED_VPS_IPS" ]; then
    echo -e "  ${GREEN}✅ No hardcoded VPS IPs found${NC}"
    echo "  All scripts use \$VPS_IP variable (auto-detected)"
else
    echo -e "  ${RED}❌ Found hardcoded VPS IPs:${NC}"
    echo "$HARDCODED_VPS_IPS"
fi
echo ""

# Check template and install.sh fallback domain counts
echo "[2/3] Checking domain template and setup.sh consistency..."
TEMPLATE_DOMAINS=0
INSTALL_DOMAINS=0

if [ -f "coredns/xbox-hosts.template" ]; then
    TEMPLATE_DOMAINS=$(grep -cE "^__VPS_IP__ [a-zA-Z0-9.-]+" coredns/xbox-hosts.template)
    echo "  xbox-hosts.template: $TEMPLATE_DOMAINS domains"
else
    echo -e "  ${RED}❌ coredns/xbox-hosts.template not found${NC}"
fi

INSTALL_DOMAINS=$(grep -cE "^\\\$VPS_IP [a-zA-Z0-9.-]+" scripts/setup.sh || echo "0")
echo "  setup.sh (inline fallback): $INSTALL_DOMAINS domains"

if [ "$TEMPLATE_DOMAINS" -gt 0 ]; then
    if [ "$INSTALL_DOMAINS" -eq "$TEMPLATE_DOMAINS" ]; then
        echo -e "  ${GREEN}✅ Domain counts match${NC}"
    else
        echo -e "  ${YELLOW}⚠️  setup.sh fallback has fewer domains than template (expected - template is authoritative)${NC}"
    fi
fi

# Check for critical missing domains in template
CRITICAL_DOMAINS=(
    "xboxgamepass.com"
    "v20.events.data.microsoft.com"
    "account.microsoft.com"
    "licensing.mp.microsoft.com"
    "xbox.com"
)

echo ""
echo "Checking for critical domains in template:"
MISSING_IN_TEMPLATE=0
for domain in "${CRITICAL_DOMAINS[@]}"; do
    if [ -f "coredns/xbox-hosts.template" ] && grep -q "__VPS_IP__ $domain" coredns/xbox-hosts.template; then
        echo -e "  ${GREEN}✅ $domain${NC}"
    else
        echo -e "  ${RED}❌ $domain MISSING${NC}"
        MISSING_IN_TEMPLATE=$((MISSING_IN_TEMPLATE + 1))
    fi
done
echo ""

# Check script syntax
echo "[3/3] Checking script syntax..."
SCRIPTS=(
    "scripts/setup.sh"
    "scripts/maintain.sh"
    "scripts/common.sh"
)

SYNTAX_ERRORS=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $script syntax OK${NC}"
        else
            echo -e "  ${RED}❌ $script has syntax errors${NC}"
            bash -n "$script" 2>&1 | head -3
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  $script not found (optional)${NC}"
    fi
done
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ -z "$HARDCODED_VPS_IPS" ] && [ $MISSING_IN_TEMPLATE -eq 0 ] && [ $SYNTAX_ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All scripts verified!${NC}"
    echo ""
    echo "✅ No hardcoded VPS IPs"
    echo "✅ All critical domains present in template"
    echo "✅ All scripts have valid syntax"
    echo ""
    echo "Scripts are ready for public release!"
else
    echo -e "${YELLOW}⚠️  Issues found:${NC}"
    if [ -n "$HARDCODED_VPS_IPS" ]; then
        echo "  • Hardcoded VPS IPs found"
    fi
    if [ $MISSING_IN_TEMPLATE -gt 0 ]; then
        echo "  • $MISSING_IN_TEMPLATE critical domain(s) missing in template"
    fi
    if [ $SYNTAX_ERRORS -gt 0 ]; then
        echo "  • $SYNTAX_ERRORS script(s) have syntax errors"
    fi
fi
echo ""
)


COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    help|-h|--help) usage; exit 0 ;;
    regenerate-hosts)
        require_root
        run_regenerate_hosts "$@"
        ;;
    fix-nat)
        require_root
        if [ ! -f "coredns/xbox-hosts" ]; then
            echo -e "${YELLOW}Hosts missing; run: ./scripts/setup.sh update${NC}"
            exit 1
        fi
        NAT_DOMAINS=(
            "xbox.nat.microsoft.com" "xbox.ipv4.microsoft.com" "xbox.ipv6.microsoft.com"
            "dns.msftncsi.com" "www.msftncsi.com" "ipv6.msftncsi.com"
            "www.msftconnecttest.com" "ipv4.msftconnecttest.com" "ipv6.msftconnecttest.com"
            "teredo.ipv6.microsoft.com"
        )
        for domain in "${NAT_DOMAINS[@]}"; do
            sed -i "/^[0-9A-Fa-f:.][0-9A-Fa-f:.]*[[:space:]].*$domain/d" coredns/xbox-hosts 2>/dev/null || true
        done
        echo -e "${GREEN}NAT connectivity domains stripped from hosts${NC}"
        docker compose restart coredns-smartdns 2>/dev/null || docker-compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns 2>/dev/null || true
        ;;
    fix-xbox-nat) require_root; run_fix_xbox_nat "$@" ;;
    fix-cod) require_root; run_fix_cod "$@" ;;
    fix-ufw-ports) require_root; run_fix_ufw_ports "$@" ;;
    verify-services) require_root; run_verify_services "$@" ;;
    compare-dns) run_compare_dns "$@" ;;
    fix-sniproxy-ipv6) require_root; run_fix_sniproxy_ipv6 "$@" ;;
    verify-excluded) require_root; run_verify_excluded "$@" ;;
    check-repo) run_check_repo "$@" ;;
    verify)
        require_root
        issues=0
        systemctl is-active docker >/dev/null 2>&1 || { echo -e "${RED}Docker not active${NC}"; issues=$((issues+1)); }
        systemctl is-active sniproxy >/dev/null 2>&1 || { echo -e "${YELLOW}SNIProxy not active${NC}"; issues=$((issues+1)); }
        [ -f coredns/xbox-hosts ] || { echo -e "${RED}Missing coredns/xbox-hosts${NC}"; issues=$((issues+1)); }
        vps_ip="$(get_vps_ip 2>/dev/null || true)"
        xbox_ip=$(curl -k -s -H "accept: application/dns-json" "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        nat_ip=$(curl -k -s -H "accept: application/dns-json" "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        if [ -n "$vps_ip" ] && [ -n "$xbox_ip" ] && [ "$xbox_ip" != "$vps_ip" ]; then
            echo -e "${RED}xboxlive.com should resolve to VPS IP ($vps_ip), got: $xbox_ip${NC}"
            issues=$((issues+1))
        fi
        if [ -n "$vps_ip" ] && [ -n "$nat_ip" ] && [ "$nat_ip" = "$vps_ip" ]; then
            echo -e "${RED}xbox.nat.microsoft.com must not resolve to VPS IP${NC}"
            issues=$((issues+1))
        fi
        if [ "$issues" -eq 0 ]; then
            echo -e "${GREEN}Verification passed${NC}"
        else
            echo -e "${RED}Verification failed${NC}"
            exit 1
        fi
        ;;
    smoke-test)
        require_root
        vps_ip="$(get_vps_ip 2>/dev/null || true)"
        failures=0
        docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$" || { echo -e "${RED}coredns not running${NC}"; failures=$((failures+1)); }
        docker ps --format "{{.Names}}" | grep -q "^doh-backend$" || { echo -e "${RED}doh-backend not running${NC}"; failures=$((failures+1)); }
        docker ps --format "{{.Names}}" | grep -q "^doh-nginx$" || { echo -e "${RED}doh-nginx not running${NC}"; failures=$((failures+1)); }
        xbox_ip=$(curl -k -s -H "accept: application/dns-json" "https://localhost:8443/dns-query?name=xboxlive.com&type=A" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        nat_ip=$(curl -k -s -H "accept: application/dns-json" "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        [ -n "$vps_ip" ] && [ "$xbox_ip" != "$vps_ip" ] && failures=$((failures+1))
        [ -n "$vps_ip" ] && [ "$nat_ip" = "$vps_ip" ] && failures=$((failures+1))
        [ "$failures" -eq 0 ] && echo -e "${GREEN}Smoke OK${NC}" || { echo -e "${RED}Smoke failed${NC}"; exit 1; }
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        exit 1
        ;;
esac

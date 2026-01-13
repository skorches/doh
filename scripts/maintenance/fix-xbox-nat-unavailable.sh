#!/bin/bash

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

# Get VPS IP from local network interface
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
VPS_IP=""
if [ -n "$DEFAULT_IF" ]; then
    VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
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
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "." ] && [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
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

echo "[4/6] Updating all IPs in hosts file to current VPS IP..."
# Update all IP addresses to current VPS IP
sed -i "s/^[0-9][0-9.]*/$VPS_IP/" "$HOSTS_FILE"
echo -e "${GREEN}✅ All IPs updated to $VPS_IP${NC}"
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


#!/bin/bash

# Analyze CoreDNS logs and add missing domains to xbox-hosts

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Adding Missing Domains from Logs"
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
    exit 1
fi

cd "$DOH_DIR"

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP (IPv4): " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Extract missing domains from CoreDNS logs
echo -e "${YELLOW}[1/3] Analyzing CoreDNS logs for missing domains...${NC}"

MISSING_DOMAINS=$(docker logs coredns-smartdns --tail 500 2>&1 | \
    grep -iE "error|timeout|servfail" | \
    grep -oE "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | \
    sort -u | \
    grep -vE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | \
    grep -vE "^[a-f0-9:]+$" | \
    head -50)

if [ -z "$MISSING_DOMAINS" ]; then
    echo -e "${GREEN}✅ No missing domains found in logs${NC}"
    exit 0
fi

DOMAIN_COUNT=$(echo "$MISSING_DOMAINS" | wc -l)
echo -e "${BLUE}Found $DOMAIN_COUNT missing domains${NC}"
echo ""

# Show domains that will be added
echo -e "${YELLOW}Domains to add:${NC}"
echo "$MISSING_DOMAINS" | head -20
if [ "$DOMAIN_COUNT" -gt 20 ]; then
    echo "... and $((DOMAIN_COUNT - 20)) more"
fi
echo ""

# Check which domains are already in hosts file
echo -e "${YELLOW}[2/3] Checking existing domains...${NC}"

if [ ! -f "coredns/xbox-hosts" ]; then
    echo -e "${YELLOW}⚠ xbox-hosts file not found, creating...${NC}"
    mkdir -p coredns
    touch coredns/xbox-hosts
fi

NEW_DOMAINS=()
ALREADY_EXISTS=0

while IFS= read -r domain; do
    if [ -z "$domain" ]; then
        continue
    fi
    
    # Skip if domain already exists
    if grep -q "$domain" coredns/xbox-hosts 2>/dev/null; then
        ALREADY_EXISTS=$((ALREADY_EXISTS + 1))
    else
        NEW_DOMAINS+=("$domain")
    fi
done <<< "$MISSING_DOMAINS"

NEW_COUNT=${#NEW_DOMAINS[@]}

if [ "$NEW_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ All domains already in hosts file${NC}"
    exit 0
fi

echo -e "${BLUE}New domains to add: $NEW_COUNT${NC}"
echo -e "${BLUE}Already exists: $ALREADY_EXISTS${NC}"
echo ""

# Add missing domains
echo -e "${YELLOW}[3/3] Adding missing domains to xbox-hosts...${NC}"

# Backup existing file
if [ -f "coredns/xbox-hosts" ] && [ -s "coredns/xbox-hosts" ]; then
    cp coredns/xbox-hosts "coredns/xbox-hosts.backup.$(date +%s)"
fi

# Add new domains
for domain in "${NEW_DOMAINS[@]}"; do
    echo "$VPS_IP $domain" >> coredns/xbox-hosts
done

echo -e "${GREEN}✅ Added $NEW_COUNT domains${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not restart CoreDNS${NC}"
}
sleep 3

# Verify
echo ""
echo -e "${YELLOW}Verifying...${NC}"
TOTAL_DOMAINS=$(grep -c "^$VPS_IP" coredns/xbox-hosts 2>/dev/null || echo "0")
echo -e "${GREEN}✅ Total domains in hosts file: $TOTAL_DOMAINS${NC}"

echo ""
echo "================================================"
echo "✅ Done"
echo "================================================"
echo ""
echo "Added domains from CoreDNS error logs."
echo "This should reduce SERVFAIL errors and improve stability."
echo ""


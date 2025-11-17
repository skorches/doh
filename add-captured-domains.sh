#!/bin/bash

# Add captured Xbox domains to xbox-hosts file

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
echo "Add Captured Xbox Domains"
echo "================================================"
echo ""

cd /root/doh

# Find the most recent capture directory
CAPTURE_DIR=$(ls -td /root/doh/xbox-capture-* 2>/dev/null | head -1)

if [ -z "$CAPTURE_DIR" ]; then
    echo -e "${RED}No capture directory found!${NC}"
    echo "Run capture-xbox-traffic.sh first"
    exit 1
fi

echo -e "${GREEN}Using capture: $CAPTURE_DIR${NC}"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)

# Extract domains from capture files
echo -e "${YELLOW}Extracting domains...${NC}"

# Get unique domains from DNS queries
DOMAINS=$(cat "$CAPTURE_DIR/unique-domains.txt" "$CAPTURE_DIR/connected-domains.txt" 2>/dev/null | \
    grep -v "^$" | \
    grep -v "bypass.440.info" | \
    grep -v "91.235.234.92" | \
    sort -u)

if [ -z "$DOMAINS" ]; then
    echo -e "${RED}No domains found in capture files!${NC}"
    exit 1
fi

DOMAIN_COUNT=$(echo "$DOMAINS" | wc -l)
echo -e "${GREEN}Found $DOMAIN_COUNT unique domains${NC}"
echo ""

# Show domains that will be added
echo "Domains to add:"
echo "$DOMAINS" | head -20
if [ "$DOMAIN_COUNT" -gt 20 ]; then
    echo "... and $((DOMAIN_COUNT - 20)) more"
fi
echo ""

# Ask for confirmation
read -p "Add these domains to xbox-hosts? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Backup current file
cp coredns/xbox-hosts "coredns/xbox-hosts.backup-$(date +%s)"

# Add domains
echo ""
echo -e "${YELLOW}Adding domains to xbox-hosts...${NC}"

# Add header
echo "" >> coredns/xbox-hosts
echo "# === CAPTURED XBOX DOMAINS ===" >> coredns/xbox-hosts
echo "# Added from capture: $CAPTURE_DIR" >> coredns/xbox-hosts
echo "# Date: $(date)" >> coredns/xbox-hosts

# Add each domain
while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
    fi
done <<< "$DOMAINS"

echo -e "${GREEN}✅ Added $DOMAIN_COUNT domains${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns
sleep 3

if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS restarted${NC}"
else
    echo -e "${RED}❌ CoreDNS failed to restart${NC}"
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Domains Added!${NC}"
echo "================================================"
echo ""
echo "Total domains in xbox-hosts: $(wc -l < coredns/xbox-hosts)"
echo ""
echo "Test Xbox again - it should work better now!"
echo ""
echo "================================================"


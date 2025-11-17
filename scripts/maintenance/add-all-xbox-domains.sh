#!/bin/bash

# Add all Xbox domains from Wireshark analysis to Smart DNS

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
echo "Add All Xbox Domains from Wireshark"
echo "================================================"
echo ""

cd /root/doh

# Check if wireshark analysis exists
ANALYSIS_DIR=$(ls -td /root/doh/wireshark-analysis-* 2>/dev/null | head -1)

if [ -z "$ANALYSIS_DIR" ] || [ ! -f "$ANALYSIS_DIR/xbox-domains.txt" ]; then
    echo -e "${RED}Wireshark analysis not found!${NC}"
    echo ""
    echo "Please run:"
    echo "  ./scripts/analysis/analyze-wireshark.sh your-capture.pcap"
    exit 1
fi

echo -e "${GREEN}Using analysis: $ANALYSIS_DIR${NC}"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)

# Read domains and filter
DOMAINS=$(cat "$ANALYSIS_DIR/xbox-domains.txt" | \
    grep -v "^$" | \
    grep -v "fe80::" | \
    grep -v "\.local$" | \
    grep -v "^res\." | \
    sort -u)

DOMAIN_COUNT=$(echo "$DOMAINS" | wc -l)
echo -e "${GREEN}Found $DOMAIN_COUNT domains${NC}"
echo ""

# Check existing
EXISTING=$(cat coredns/xbox-hosts 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{print $2}' | sort -u)

NEW_DOMAINS=""
while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        if ! echo "$EXISTING" | grep -q "^${domain}$"; then
            NEW_DOMAINS="${NEW_DOMAINS}${domain}\n"
        fi
    fi
done <<< "$DOMAINS"

NEW_COUNT=$(echo -e "$NEW_DOMAINS" | grep -v "^$" | wc -l)

if [ "$NEW_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}All domains already added!${NC}"
    exit 0
fi

echo -e "${GREEN}$NEW_COUNT new domains to add${NC}"
echo ""

# Backup
cp coredns/xbox-hosts "coredns/xbox-hosts.backup-$(date +%s)"

# Add domains
echo -e "${YELLOW}Adding domains...${NC}"

echo "" >> coredns/xbox-hosts
echo "# === DOMAINS FROM WIRESHARK ANALYSIS ===" >> coredns/xbox-hosts
echo "# Added: $(date)" >> coredns/xbox-hosts

while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        if ! echo "$EXISTING" | grep -q "^${domain}$"; then
            echo "$VPS_IP $domain" >> coredns/xbox-hosts
        fi
    fi
done <<< "$DOMAINS"

echo -e "${GREEN}✅ Added $NEW_COUNT domains${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}Restarting CoreDNS...${NC}"
docker-compose restart coredns-smartdns
sleep 3

if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS restarted${NC}"
else
    echo -e "${RED}❌ CoreDNS failed${NC}"
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Complete!${NC}"
echo "================================================"
echo ""
echo "Total domains: $(wc -l < coredns/xbox-hosts)"
echo ""
echo "Test Xbox again!"
echo ""
echo "================================================"


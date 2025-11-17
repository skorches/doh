#!/bin/bash

# Add domains from Wireshark analysis to xbox-hosts

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <domains-file.txt>"
    echo ""
    echo "Example: $0 wireshark-analysis-*/xbox-domains.txt"
    exit 1
fi

DOMAINS_FILE="$1"

if [ ! -f "$DOMAINS_FILE" ]; then
    echo -e "${RED}File not found: $DOMAINS_FILE${NC}"
    exit 1
fi

echo "================================================"
echo "Add Wireshark Domains to Smart DNS"
echo "================================================"
echo ""

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)

# Read domains
DOMAINS=$(cat "$DOMAINS_FILE" | grep -v "^$" | sort -u)
DOMAIN_COUNT=$(echo "$DOMAINS" | wc -l)

if [ "$DOMAIN_COUNT" -eq 0 ]; then
    echo -e "${RED}No domains found in file!${NC}"
    exit 1
fi

echo -e "${GREEN}Found $DOMAIN_COUNT domains${NC}"
echo ""
echo "Sample domains:"
echo "$DOMAINS" | head -10
if [ "$DOMAIN_COUNT" -gt 10 ]; then
    echo "... and $((DOMAIN_COUNT - 10)) more"
fi
echo ""

# Check which domains are already in xbox-hosts
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
    echo -e "${YELLOW}All domains already in xbox-hosts!${NC}"
    exit 0
fi

echo -e "${GREEN}$NEW_COUNT new domains to add${NC}"
echo ""
echo "New domains:"
echo -e "$NEW_DOMAINS" | grep -v "^$" | head -20
if [ "$NEW_COUNT" -gt 20 ]; then
    echo "... and $((NEW_COUNT - 20)) more"
fi
echo ""

# Ask for confirmation
read -p "Add these domains to xbox-hosts? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Backup
cp coredns/xbox-hosts "coredns/xbox-hosts.backup-$(date +%s)"

# Add domains
echo ""
echo -e "${YELLOW}Adding domains...${NC}"

echo "" >> coredns/xbox-hosts
echo "# === DOMAINS FROM WIRESHARK ANALYSIS ===" >> coredns/xbox-hosts
echo "# Added from: $DOMAINS_FILE" >> coredns/xbox-hosts
echo "# Date: $(date)" >> coredns/xbox-hosts

while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        if ! echo "$EXISTING" | grep -q "^${domain}$"; then
            echo "$VPS_IP $domain" >> coredns/xbox-hosts
        fi
    fi
done <<< "$DOMAINS"

echo -e "${GREEN}✅ Added $NEW_COUNT new domains${NC}"

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
echo "Total domains in xbox-hosts: $(wc -l < coredns/xbox-hosts)"
echo ""
echo "Test Xbox again!"
echo ""
echo "================================================"


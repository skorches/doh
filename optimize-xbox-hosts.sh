#!/bin/bash

# Optimize xbox-hosts file - remove duplicates, invalid entries, and organize

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
echo "Optimize Xbox Hosts File"
echo "================================================"
echo ""

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me)

# Backup
cp coredns/xbox-hosts "coredns/xbox-hosts.backup-$(date +%s)"
ORIGINAL_COUNT=$(wc -l < coredns/xbox-hosts)

echo -e "${YELLOW}Original file: $ORIGINAL_COUNT lines${NC}"
echo ""

# Extract all valid domains
echo -e "${YELLOW}[1/4] Extracting and cleaning domains...${NC}"

# Get all domains, remove comments, empty lines, and invalid entries
DOMAINS=$(cat coredns/xbox-hosts | \
    grep -v "^#" | \
    grep -v "^$" | \
    awk '{print $2}' | \
    grep -v "^$" | \
    grep -v "fe80::" | \
    grep -v "\.local$" | \
    grep -v "^res\." | \
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" | \
    sort -u)

DOMAIN_COUNT=$(echo "$DOMAINS" | wc -l)
echo -e "${GREEN}Found $DOMAIN_COUNT unique valid domains${NC}"

# Categorize domains
echo ""
echo -e "${YELLOW}[2/4] Categorizing domains...${NC}"

XBOX_DOMAINS=""
MICROSOFT_DOMAINS=""
DISCORD_DOMAINS=""
OTHER_DOMAINS=""

while IFS= read -r domain; do
    if [ ! -z "$domain" ]; then
        if echo "$domain" | grep -qiE "xbox|gamepass"; then
            XBOX_DOMAINS="${XBOX_DOMAINS}${domain}\n"
        elif echo "$domain" | grep -qiE "discord"; then
            DISCORD_DOMAINS="${DISCORD_DOMAINS}${domain}\n"
        elif echo "$domain" | grep -qiE "microsoft|live|windows|msft|azure|office|outlook|onedrive|skype|teams"; then
            MICROSOFT_DOMAINS="${MICROSOFT_DOMAINS}${domain}\n"
        else
            OTHER_DOMAINS="${OTHER_DOMAINS}${domain}\n"
        fi
    fi
done <<< "$DOMAINS"

XBOX_COUNT=$(echo -e "$XBOX_DOMAINS" | grep -v "^$" | wc -l)
MS_COUNT=$(echo -e "$MICROSOFT_DOMAINS" | grep -v "^$" | wc -l)
DISCORD_COUNT=$(echo -e "$DISCORD_DOMAINS" | grep -v "^$" | wc -l)
OTHER_COUNT=$(echo -e "$OTHER_DOMAINS" | grep -v "^$" | wc -l)

echo -e "${GREEN}Xbox domains: $XBOX_COUNT${NC}"
echo -e "${GREEN}Microsoft domains: $MS_COUNT${NC}"
echo -e "${GREEN}Discord domains: $DISCORD_COUNT${NC}"
echo -e "${GREEN}Other domains: $OTHER_COUNT${NC}"

# Create optimized file
echo ""
echo -e "${YELLOW}[3/4] Creating optimized hosts file...${NC}"

cat > coredns/xbox-hosts << EOF
# Optimized Xbox Smart DNS Hosts File
# Generated: $(date)
# VPS IP: $VPS_IP
# Total domains: $DOMAIN_COUNT

# === XBOX DOMAINS ===
EOF

echo -e "$XBOX_DOMAINS" | grep -v "^$" | sort | while read domain; do
    echo "$VPS_IP $domain"
done >> coredns/xbox-hosts

echo "" >> coredns/xbox-hosts
echo "# === MICROSOFT DOMAINS ===" >> coredns/xbox-hosts
echo -e "$MICROSOFT_DOMAINS" | grep -v "^$" | sort | while read domain; do
    echo "$VPS_IP $domain"
done >> coredns/xbox-hosts

echo "" >> coredns/xbox-hosts
echo "# === DISCORD DOMAINS ===" >> coredns/xbox-hosts
echo -e "$DISCORD_DOMAINS" | grep -v "^$" | sort | while read domain; do
    echo "$VPS_IP $domain"
done >> coredns/xbox-hosts

if [ "$OTHER_COUNT" -gt 0 ]; then
    echo "" >> coredns/xbox-hosts
    echo "# === OTHER DOMAINS ===" >> coredns/xbox-hosts
    echo -e "$OTHER_DOMAINS" | grep -v "^$" | sort | while read domain; do
        echo "$VPS_IP $domain"
    done >> coredns/xbox-hosts
fi

NEW_COUNT=$(wc -l < coredns/xbox-hosts)
REMOVED=$((ORIGINAL_COUNT - NEW_COUNT))

echo -e "${GREEN}✅ Optimized file created: $NEW_COUNT lines${NC}"
echo -e "${GREEN}Removed $REMOVED duplicate/invalid entries${NC}"

# Restart CoreDNS
echo ""
echo -e "${YELLOW}[4/4] Restarting CoreDNS...${NC}"
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
echo -e "${GREEN}✅ Optimization Complete!${NC}"
echo "================================================"
echo ""
echo "Before: $ORIGINAL_COUNT lines"
echo "After:  $NEW_COUNT lines"
echo "Removed: $REMOVED duplicate/invalid entries"
echo ""
echo "Benefits:"
echo "  ✅ Faster DNS lookups (no duplicates)"
echo "  ✅ Cleaner, organized file"
echo "  ✅ Only valid domains"
echo ""
echo "Test Xbox - it should be faster now!"
echo ""
echo "================================================"


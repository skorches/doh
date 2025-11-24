#!/bin/bash

# Add game-specific domains to Smart DNS setup
# Usage: ./add-game-domain.sh domain.com

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
    echo "Usage: $0 <domain.com> [domain2.com ...]"
    echo ""
    echo "Example: $0 activision.com callofduty.com"
    exit 1
fi

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi

echo "================================================"
echo "Adding Game-Specific Domains"
echo "================================================"
echo ""

# Step 1: Add to xbox-hosts
echo -e "${YELLOW}[1/3] Adding domains to coredns/xbox-hosts...${NC}"

for DOMAIN in "$@"; do
    # Remove www. prefix if present for base domain
    BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
    
    # Check if already exists
    if grep -q "^$VPS_IP.*$BASE_DOMAIN" coredns/xbox-hosts; then
        echo -e "  ${YELLOW}⚠ $BASE_DOMAIN already exists${NC}"
    else
        echo "$VPS_IP $BASE_DOMAIN" >> coredns/xbox-hosts
        echo "$VPS_IP www.$BASE_DOMAIN" >> coredns/xbox-hosts
        echo -e "  ${GREEN}✅ Added $BASE_DOMAIN${NC}"
    fi
done

# Step 2: Add to SNIProxy config
echo ""
echo -e "${YELLOW}[2/3] Adding domains to SNIProxy config...${NC}"

SNIPROXY_CONF="/etc/sniproxy.conf"
BACKUP_CONF="/etc/sniproxy.conf.backup.$(date +%Y%m%d_%H%M%S)"

# Backup config
cp "$SNIPROXY_CONF" "$BACKUP_CONF"

# Check if we need to add domains
NEED_UPDATE=false
for DOMAIN in "$@"; do
    BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
    ESCAPED_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's/\./\\./g')
    
    if ! grep -q ".*\\.$ESCAPED_DOMAIN\\$" "$SNIPROXY_CONF"; then
        NEED_UPDATE=true
        # Add before the closing brace
        sed -i "/^}$/i\    .*\\.$ESCAPED_DOMAIN\\$ *" "$SNIPROXY_CONF"
        echo -e "  ${GREEN}✅ Added SNIProxy rule for $BASE_DOMAIN${NC}"
    else
        echo -e "  ${YELLOW}⚠ SNIProxy rule for $BASE_DOMAIN already exists${NC}"
    fi
done

# Step 3: Restart services
if [ "$NEED_UPDATE" = true ]; then
    echo ""
    echo -e "${YELLOW}[3/3] Restarting services...${NC}"
    
    # Restart CoreDNS
    docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns
    sleep 2
    
    # Restart SNIProxy
    systemctl restart sniproxy
    sleep 1
    
    if systemctl is-active --quiet sniproxy; then
        echo -e "  ${GREEN}✅ SNIProxy restarted${NC}"
    else
        echo -e "  ${RED}❌ SNIProxy failed to restart${NC}"
        echo "Restoring backup config..."
        cp "$BACKUP_CONF" "$SNIPROXY_CONF"
        systemctl restart sniproxy
        exit 1
    fi
    
    if docker ps | grep -q coredns-smartdns; then
        echo -e "  ${GREEN}✅ CoreDNS restarted${NC}"
    else
        echo -e "  ${RED}❌ CoreDNS failed to restart${NC}"
        exit 1
    fi
else
    echo ""
    echo -e "${YELLOW}[3/3] No SNIProxy changes needed${NC}"
    echo -e "  ${YELLOW}Restarting CoreDNS to load new hosts...${NC}"
    docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns
    sleep 2
fi

echo ""
echo -e "${GREEN}✅ Domains added successfully!${NC}"
echo ""
echo "Added domains:"
for DOMAIN in "$@"; do
    BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
    echo "  • $BASE_DOMAIN → $VPS_IP"
done
echo ""
echo "Test DNS resolution:"
echo "  curl -H 'accept: application/dns-json' 'https://YOUR_DOMAIN/dns-query?name=$BASE_DOMAIN&type=A'"
echo ""


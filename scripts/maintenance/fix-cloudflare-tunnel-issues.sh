#!/bin/bash

# Fix Cloudflare Tunnel setup issues

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
echo "Fixing Cloudflare Tunnel Issues"
echo "================================================"
echo ""

cd /root/doh || cd /home/wars09/Cursor/doh || { echo -e "${RED}❌ Could not find doh directory${NC}"; exit 1; }

# Issue 1: CoreDNS not running
echo -e "${YELLOW}[1/3] Fixing CoreDNS...${NC}"

if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS container is running${NC}"
else
    echo -e "${YELLOW}Starting CoreDNS...${NC}"
    docker-compose up -d coredns-smartdns 2>/dev/null || docker compose up -d coredns-smartdns 2>/dev/null || {
        echo -e "${RED}❌ Failed to start CoreDNS${NC}"
        echo "Checking docker-compose.yml..."
    }
    sleep 2
    
    if docker ps | grep -q coredns-smartdns; then
        echo -e "${GREEN}✅ CoreDNS started${NC}"
    else
        echo -e "${RED}❌ CoreDNS failed to start${NC}"
        echo "Check: docker-compose logs coredns-smartdns"
    fi
fi

# Test CoreDNS
echo ""
echo -e "${BLUE}Testing CoreDNS...${NC}"
sleep 1
if dig +short xboxlive.com @127.0.0.1 > /dev/null 2>&1; then
    DNS_RESULT=$(dig +short xboxlive.com @127.0.0.1 | head -1)
    echo -e "${GREEN}✅ CoreDNS responding: $DNS_RESULT${NC}"
else
    echo -e "${RED}❌ CoreDNS still not responding${NC}"
    echo "Check: docker-compose logs coredns-smartdns"
fi

# Issue 2: Check DNS records configuration
echo ""
echo -e "${YELLOW}[2/3] Checking DNS Configuration...${NC}"

read -p "Enter your Cloudflare tunnel domain (e.g., xbox-live.example.com): " TUNNEL_DOMAIN
if [ -z "$TUNNEL_DOMAIN" ]; then
    echo -e "${RED}❌ Tunnel domain required${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Current DNS resolution for xboxlive.com:${NC}"
CURRENT_DNS=$(dig +short xboxlive.com @1.1.1.1 | head -1)
echo "  $CURRENT_DNS"

if echo "$CURRENT_DNS" | grep -qE "^20\.|^13\.|^40\."; then
    echo -e "${RED}❌ PROBLEM: DNS returning Microsoft/Xbox IP${NC}"
    echo ""
    echo "This means Cloudflare DNS records are pointing"
    echo "directly to Xbox servers, not to your tunnel."
    echo ""
    echo "You need to create CNAME records in Cloudflare:"
    echo ""
    echo "  In Cloudflare Dashboard → DNS → Records:"
    echo ""
    echo "  Type: CNAME"
    echo "  Name: xboxlive"
    echo "  Target: $TUNNEL_DOMAIN"
    echo "  Proxy: ON (orange cloud) ✅"
    echo "  TTL: Auto"
    echo ""
    echo "  Click 'Save'"
    echo ""
    echo "Repeat for:"
    echo "  • notify.xboxlive.com"
    echo "  • xccs.xboxlive.com"
    echo "  • auth.xboxlive.com"
    echo "  • etc."
    echo ""
    echo "OR use wildcard:"
    echo "  • *.xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
    echo ""
    read -p "Press Enter after you've created the DNS records..."
else
    echo -e "${GREEN}✅ DNS looks correct${NC}"
fi

# Issue 3: Find tunnel config
echo ""
echo -e "${YELLOW}[3/3] Finding Tunnel Configuration...${NC}"

# Check common locations
TUNNEL_CONFIG=""
for loc in "/etc/cloudflared/config.yml" "/root/.cloudflared/config.yml" "$HOME/.cloudflared/config.yml"; do
    if [ -f "$loc" ]; then
        TUNNEL_CONFIG="$loc"
        echo -e "${GREEN}✅ Found tunnel config: $TUNNEL_CONFIG${NC}"
        break
    fi
done

if [ -z "$TUNNEL_CONFIG" ]; then
    echo -e "${YELLOW}⚠ Tunnel config not found in standard locations${NC}"
    echo "Checking cloudflared service..."
    
    # Check systemd service
    if systemctl list-units | grep -q cloudflared; then
        SERVICE_FILE=$(systemctl show cloudflared-tunnel cloudflared 2>/dev/null | grep FragmentPath | cut -d= -f2 | head -1)
        if [ -n "$SERVICE_FILE" ]; then
            echo -e "${BLUE}Service file: $SERVICE_FILE${NC}"
            grep -E "ExecStart|config" "$SERVICE_FILE" 2>/dev/null | head -3
        fi
    fi
    
    # Check if tunnel is configured via token
    if systemctl cat cloudflared-tunnel 2>/dev/null | grep -q "tunnel run"; then
        echo -e "${GREEN}✅ Tunnel configured via token (no config file needed)${NC}"
    fi
fi

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS is running${NC}"
else
    echo -e "${RED}❌ CoreDNS is NOT running${NC}"
    echo "   Fix: docker-compose up -d coredns-smartdns"
fi

echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "1. Ensure DNS records in Cloudflare point to tunnel:"
echo "   xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
echo ""
echo "2. Wait 5-10 minutes for DNS propagation"
echo ""
echo "3. Test DNS resolution:"
echo "   nslookup xboxlive.com"
echo "   Should return Cloudflare IPs (104.x.x.x, 172.x.x.x, etc.)"
echo ""
echo "4. Restart Xbox to clear DNS cache"
echo ""


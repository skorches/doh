#!/bin/bash

# Diagnose why Xbox isn't connecting to DoH/DNS

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Xbox DoH/DNS Connectivity Diagnosis"
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
DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "unknown")

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo -e "${BLUE}DoH Domain: $DOMAIN${NC}"
echo ""

# 1. Check CoreDNS
echo -e "${YELLOW}[1/6] CoreDNS Status${NC}"
if docker ps | grep -q coredns-smartdns; then
    echo -e "${GREEN}✅ CoreDNS is running${NC}"
    
    # Test DNS
    DNS_TEST=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DNS_TEST" != "FAILED" ] && [ -n "$DNS_TEST" ]; then
        echo -e "${GREEN}✅ DNS resolution working: xboxlive.com → $DNS_TEST${NC}"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
    fi
else
    echo -e "${RED}❌ CoreDNS is not running${NC}"
fi

# 2. Check port 53
echo ""
echo -e "${YELLOW}[2/6] Port 53 (DNS)${NC}"
if ss -tlnp | grep -q ":53" || ss -ulnp | grep -q ":53"; then
    echo -e "${GREEN}✅ Port 53 is listening${NC}"
    echo -e "${BLUE}   Xbox should use DNS: $VPS_IP${NC}"
else
    echo -e "${RED}❌ Port 53 is not listening${NC}"
fi

# 3. Check DoH endpoint
echo ""
echo -e "${YELLOW}[3/6] DoH Endpoint${NC}"
if [ "$DOMAIN" != "unknown" ]; then
    DOH_TEST=$(timeout 5 curl -k -s -H 'accept: application/dns-json' "https://$DOMAIN/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "FAILED")
    
    if [ "$DOH_TEST" == "0" ]; then
        echo -e "${GREEN}✅ DoH endpoint working${NC}"
        echo -e "${BLUE}   DoH URL: https://$DOMAIN/dns-query${NC}"
    else
        echo -e "${YELLOW}⚠ DoH endpoint test: Status $DOH_TEST${NC}"
    fi
else
    echo -e "${YELLOW}⚠ DoH domain not configured${NC}"
fi

# 4. Check SNIProxy
echo ""
echo -e "${YELLOW}[4/6] SNIProxy Status${NC}"
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
else
    echo -e "${RED}❌ SNIProxy not listening on port 443${NC}"
fi

# 5. Check domain DNS
echo ""
echo -e "${YELLOW}[5/6] Domain DNS Configuration${NC}"
if [ "$DOMAIN" != "unknown" ]; then
    DOMAIN_IP=$(dig @1.1.1.1 "$DOMAIN" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$DOMAIN_IP" == "$VPS_IP" ]; then
        echo -e "${GREEN}✅ Domain $DOMAIN points to VPS IP ($VPS_IP)${NC}"
    elif [ "$DOMAIN_IP" != "FAILED" ]; then
        echo -e "${YELLOW}⚠ Domain $DOMAIN points to $DOMAIN_IP (expected: $VPS_IP)${NC}"
    else
        echo -e "${RED}❌ Could not resolve domain $DOMAIN${NC}"
    fi
fi

# 6. Configuration guide
echo ""
echo -e "${YELLOW}[6/6] Configuration Guide${NC}"
echo ""
echo "================================================"
echo "How to Configure Xbox/Router"
echo "================================================"
echo ""
echo -e "${BLUE}Option 1: Configure Router DNS (Recommended)${NC}"
echo "  Set router DNS to: $VPS_IP"
echo "  All devices (including Xbox) will use this DNS"
echo ""
echo -e "${BLUE}Option 2: Configure Router DoH (If supported)${NC}"
echo "  DoH URL: https://$DOMAIN/dns-query"
echo "  Router must support DoH (Keenetic, OpenWrt, etc.)"
echo ""
echo -e "${BLUE}Option 3: Configure Xbox DNS directly${NC}"
echo "  Xbox Settings → Network → Advanced → DNS"
echo "  Primary DNS: $VPS_IP"
echo "  Secondary DNS: 1.1.1.1 (backup)"
echo ""
echo "================================================"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "  • Xbox doesn't use DoH directly - it uses regular DNS (port 53)"
echo "  • DoH is for routers that support it"
echo "  • If router uses DoH, Xbox will automatically use it"
echo "  • If router doesn't support DoH, use Option 1 or 3"
echo ""


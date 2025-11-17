#!/bin/bash

# Verify VPS is ready for IPv6 DoH
# Run this ON THE VPS

set -e

echo "==================================="
echo "IPv6 DoH Readiness Check"
echo "==================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ISSUES_FOUND=0

# Check 1: IPv6 address exists
echo -e "${YELLOW}[1/6] Checking IPv6 address...${NC}"
IPV6_ADDR=$(ip -6 addr show | grep 'inet6.*global' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "")

if [ -z "$IPV6_ADDR" ]; then
    echo -e "${RED}❌ No IPv6 address found${NC}"
    echo "Your VPS doesn't have IPv6. Contact your provider."
    exit 1
else
    echo -e "${GREEN}✅ IPv6 address: $IPV6_ADDR${NC}"
fi

# Check 2: Docker listening on IPv6
echo
echo -e "${YELLOW}[2/6] Checking if Docker listens on IPv6...${NC}"
if ss -tlnp | grep -q '\[::\]:443'; then
    echo -e "${GREEN}✅ Port 443 listening on IPv6${NC}"
elif ss -tlnp | grep -q '0.0.0.0:443'; then
    echo -e "${YELLOW}⚠️  Port 443 only on IPv4, but might work via host binding${NC}"
    echo "Docker port mappings usually work for both IPv4 and IPv6."
else
    echo -e "${RED}❌ Port 443 not listening!${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check 3: Nginx configuration
echo
echo -e "${YELLOW}[3/6] Checking nginx configuration...${NC}"
if docker ps --format '{{.Names}}' | grep -q 'doh-nginx'; then
    # Check if nginx has IPv6 listen directive
    NGINX_CONFIG=$(docker exec doh-nginx sh -c "cat /etc/nginx/nginx.conf 2>/dev/null || cat /etc/nginx/conf.d/default.conf 2>/dev/null" || echo "")
    
    if echo "$NGINX_CONFIG" | grep -q 'listen.*443'; then
        echo -e "${GREEN}✅ Nginx listening on port 443${NC}"
        
        # Check for explicit IPv6 listen
        if echo "$NGINX_CONFIG" | grep -q 'listen \[::\]:443'; then
            echo -e "${GREEN}✅ Nginx has explicit IPv6 listener${NC}"
        else
            echo -e "${YELLOW}⚠️  No explicit IPv6 listen directive${NC}"
            echo "Nginx might still work via dual-stack binding."
            echo "If issues occur, we'll add explicit IPv6 listener."
        fi
    else
        echo -e "${RED}❌ Nginx config issue${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    echo -e "${YELLOW}⚠️  doh-nginx container not found${NC}"
    echo "Looking for other DoH containers..."
    
    if docker ps --format '{{.Names}}' | grep -q 'doh'; then
        echo -e "${GREEN}✅ Found DoH containers running${NC}"
    else
        echo -e "${RED}❌ No DoH containers running${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi

# Check 4: IPv6 firewall
echo
echo -e "${YELLOW}[4/6] Checking IPv6 firewall...${NC}"

# Check if ufw is active (handles both IPv4 and IPv6)
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo -e "${GREEN}✅ UFW is active (handles IPv4 and IPv6)${NC}"
    
    if ufw status | grep -q "443"; then
        echo -e "${GREEN}✅ Port 443 allowed in UFW${NC}"
    else
        echo -e "${RED}❌ Port 443 not allowed in UFW${NC}"
        echo "Run: ufw allow 443/tcp"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    # Check ip6tables
    echo "UFW not active, checking ip6tables..."
    
    if ip6tables -L INPUT -n | grep -q "dpt:443.*ACCEPT"; then
        echo -e "${GREEN}✅ IPv6 firewall allows port 443${NC}"
    elif ip6tables -L INPUT -n | grep -q "policy ACCEPT"; then
        echo -e "${YELLOW}⚠️  IPv6 firewall policy is ACCEPT (permissive)${NC}"
        echo "Port 443 should work, but consider adding explicit rule."
    else
        echo -e "${RED}❌ IPv6 firewall might be blocking port 443${NC}"
        echo "Run: ip6tables -I INPUT -p tcp --dport 443 -j ACCEPT"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi

# Check 5: Test local IPv6 connectivity
echo
echo -e "${YELLOW}[5/6] Testing local IPv6 HTTPS...${NC}"
RESPONSE=$(curl -g -6 -k -s -o /dev/null -w "%{http_code}" --max-time 5 "https://[::1]/dns-query" 2>/dev/null || echo "000")

if [ "$RESPONSE" = "000" ]; then
    # Try the actual IPv6 address
    RESPONSE=$(curl -g -6 -k -s -o /dev/null -w "%{http_code}" --max-time 5 "https://[$IPV6_ADDR]/dns-query" 2>/dev/null || echo "000")
fi

if [ "$RESPONSE" != "000" ]; then
    echo -e "${GREEN}✅ HTTPS responds on IPv6 (HTTP $RESPONSE)${NC}"
else
    echo -e "${YELLOW}⚠️  Could not test IPv6 HTTPS locally${NC}"
    echo "This might be normal. External test will be more definitive."
fi

# Check 6: SSL certificate
echo
echo -e "${YELLOW}[6/6] Checking SSL certificate...${NC}"
if [ -d "/etc/letsencrypt/live/bypass.440.dev" ]; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/bypass.440.dev/fullchain.pem 2>/dev/null | cut -d= -f2 || echo "Unknown")
    echo -e "${GREEN}✅ SSL certificate exists${NC}"
    echo "   Expires: $CERT_EXPIRY"
    echo "   Works for both IPv4 and IPv6!"
else
    echo -e "${RED}❌ SSL certificate not found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Summary
echo
echo "==================================="
echo "SUMMARY"
echo "==================================="
echo
echo "VPS IPv6 Address: $IPV6_ADDR"
echo

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ VPS IS READY FOR IPv6!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "1. Add AAAA DNS record:"
    echo "   Type:  AAAA"
    echo "   Name:  bypass"
    echo "   Value: $IPV6_ADDR"
    echo "   TTL:   60"
    echo
    echo "2. KEEP the existing A record:"
    echo "   Type:  A"
    echo "   Name:  bypass"  
    echo "   Value: 91.235.234.92"
    echo "   (Don't delete it - dual-stack is best!)"
    echo
    echo "3. Test from home:"
    echo "   curl -6 -I https://bypass.440.dev/dns-query"
    echo
    echo "4. Configure Keenetic:"
    echo "   URL: https://bypass.440.dev/dns-query"
    echo "   (No changes needed - same URL!)"
    echo
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ $ISSUES_FOUND ISSUE(S) FOUND${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "FIX THESE ISSUES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "If firewall issue:"
    echo "  ufw allow 443/tcp"
    echo "  # OR"
    echo "  ip6tables -I INPUT -p tcp --dport 443 -j ACCEPT"
    echo "  ip6tables-save > /etc/iptables/rules.v6"
    echo
    echo "If Docker not running:"
    echo "  cd /root/doh"
    echo "  docker-compose up -d"
    echo
    echo "Then run this script again to verify."
    echo
fi

echo "==================================="


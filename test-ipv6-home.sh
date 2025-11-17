#!/bin/bash

# Test IPv6 connectivity from home network
# Run this on your HOME COMPUTER (not VPS)

echo "==================================="
echo "IPv6 Connectivity Test (Home Network)"
echo "==================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VPS_IP="91.235.234.92"
DOMAIN="bypass.440.dev"

# Test 1: Check if you have IPv6
echo -e "${YELLOW}[Test 1/5] Checking if you have IPv6...${NC}"
HOME_IPV6=$(curl -6 -s --max-time 5 https://ifconfig.co 2>/dev/null || echo "")

if [ -z "$HOME_IPV6" ]; then
    echo -e "${RED}❌ No IPv6 connectivity${NC}"
    echo "Your ISP doesn't provide IPv6 or it's disabled."
    echo
    echo "IPv6 bypass won't work. Use alternative:"
    echo "  1. Cloudflare proxy (recommended)"
    echo "  2. Request new IPv4 address from VPS provider"
    echo
    exit 1
else
    echo -e "${GREEN}✅ You have IPv6: $HOME_IPV6${NC}"
fi

# Test 2: Get VPS IPv6 address
echo
echo -e "${YELLOW}[Test 2/5] Getting VPS IPv6 address...${NC}"
VPS_IPV6=$(ssh -o ConnectTimeout=5 root@$VPS_IP "ip -6 addr show | grep 'inet6.*global' | head -1 | awk '{print \$2}' | cut -d'/' -f1" 2>/dev/null || echo "")

if [ -z "$VPS_IPV6" ]; then
    echo -e "${RED}❌ Could not get VPS IPv6 address${NC}"
    echo "Either VPS has no IPv6 or can't connect via IPv4."
    echo
    echo "Try manually on VPS:"
    echo "  ssh root@$VPS_IP"
    echo "  ip -6 addr show | grep global"
    echo
    read -p "Enter VPS IPv6 address manually (or press Enter to skip): " MANUAL_IPV6
    if [ -n "$MANUAL_IPV6" ]; then
        VPS_IPV6="$MANUAL_IPV6"
        echo -e "${GREEN}✅ Using IPv6: $VPS_IPV6${NC}"
    else
        echo "Cannot continue without VPS IPv6 address."
        exit 1
    fi
else
    echo -e "${GREEN}✅ VPS IPv6: $VPS_IPV6${NC}"
fi

# Test 3: Ping VPS via IPv6
echo
echo -e "${YELLOW}[Test 3/5] Testing ping to VPS via IPv6...${NC}"
if ping6 -c 3 $VPS_IPV6 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Can ping VPS via IPv6!${NC}"
else
    echo -e "${RED}❌ Cannot ping VPS via IPv6${NC}"
    echo "This might be normal (some VPS block ICMPv6)."
    echo "Continuing with HTTPS test..."
fi

# Test 4: Try to reach port 443 via IPv6
echo
echo -e "${YELLOW}[Test 4/5] Testing HTTPS on port 443 via IPv6...${NC}"
echo "Trying: curl -g -6 -k -I https://[$VPS_IPV6]/dns-query"
echo

RESPONSE=$(curl -g -6 -k -s -I --max-time 10 "https://[$VPS_IPV6]/dns-query" 2>&1 || echo "FAILED")

if echo "$RESPONSE" | grep -q "HTTP"; then
    echo -e "${GREEN}✅ SUCCESS! VPS responds via IPv6!${NC}"
    echo
    echo "$RESPONSE" | head -5
    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}IPv6 WORKS! This will bypass the block!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    IPV6_WORKS=true
else
    echo -e "${RED}❌ Cannot reach VPS port 443 via IPv6${NC}"
    echo "Error: $RESPONSE"
    echo
    echo "Possible reasons:"
    echo "  - VPS firewall blocking IPv6"
    echo "  - ISP blocking IPv6 to that IP range"
    echo "  - Docker not listening on IPv6"
    IPV6_WORKS=false
fi

# Test 5: Check DNS resolution
echo
echo -e "${YELLOW}[Test 5/5] Checking DNS for $DOMAIN...${NC}"
DNS_IPV6=$(dig +short AAAA $DOMAIN 2>/dev/null | head -1 || echo "")

if [ -z "$DNS_IPV6" ]; then
    echo -e "${YELLOW}⚠️  No AAAA record found for $DOMAIN${NC}"
    echo "You need to add AAAA record in your DNS provider."
else
    echo -e "${GREEN}✅ AAAA record exists: $DNS_IPV6${NC}"
    
    if [ "$DNS_IPV6" = "$VPS_IPV6" ]; then
        echo -e "${GREEN}✅ AAAA record matches VPS IPv6!${NC}"
    else
        echo -e "${RED}❌ AAAA record doesn't match VPS IPv6${NC}"
        echo "Expected: $VPS_IPV6"
        echo "Got:      $DNS_IPV6"
    fi
fi

# Summary
echo
echo "==================================="
echo "SUMMARY"
echo "==================================="
echo
echo "Your IPv6:       $HOME_IPV6"
echo "VPS IPv6:        $VPS_IPV6"
echo "Domain:          $DOMAIN"
echo "DNS AAAA record: ${DNS_IPV6:-Not set}"
echo

if [ "$IPV6_WORKS" = true ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ IPv6 BYPASS WILL WORK!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -z "$DNS_IPV6" ] || [ "$DNS_IPV6" != "$VPS_IPV6" ]; then
        echo
        echo "1. Add/Update AAAA record in DNS:"
        echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   Go to your DNS provider (where you manage 440.dev)"
        echo "   Type:  AAAA"
        echo "   Name:  bypass"
        echo "   Value: $VPS_IPV6"
        echo "   TTL:   60"
        echo
        echo "2. Wait 2-5 minutes for DNS propagation"
        echo
    fi
    
    echo "3. Test DoH via IPv6:"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   curl -6 -I https://$DOMAIN/dns-query"
    echo
    echo "4. Configure Keenetic with DoH URL:"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   https://$DOMAIN/dns-query"
    echo "   (Keenetic will automatically prefer IPv6)"
    echo
    echo "5. Test Xbox!"
    echo
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ IPv6 BYPASS WON'T WORK${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Reasons:"
    echo "  - ISP might be blocking IPv6 to VPS ranges too"
    echo "  - VPS firewall blocking IPv6"
    echo "  - Docker not properly configured for IPv6"
    echo
    echo "ALTERNATIVE SOLUTIONS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Use Cloudflare Proxy (RECOMMENDED)"
    echo "   - Hides your VPS IP"
    echo "   - Hard to block"
    echo "   - Free"
    echo
    echo "2. Request new IPv4 from VPS provider"
    echo "   - Might get unblocked IP"
    echo "   - Usually free"
    echo
    echo "3. Get VPS in different location"
    echo "   - Asia-Pacific region"
    echo "   - Less likely to be blocked"
    echo
fi

echo "==================================="


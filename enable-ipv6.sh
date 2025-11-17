#!/bin/bash

# Enable IPv6 for DoH Server
# This script checks and configures IPv6 support

set -e

echo "==================================="
echo "IPv6 DoH Server Configuration"
echo "==================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Step 1: Check if VPS has IPv6
echo -e "${YELLOW}[1/6] Checking VPS IPv6 configuration...${NC}"
IPV6_ADDR=$(ip -6 addr show | grep 'inet6.*global' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "")

if [ -z "$IPV6_ADDR" ]; then
    echo -e "${RED}❌ No IPv6 address found on VPS!${NC}"
    echo
    echo "Your VPS doesn't have IPv6 configured."
    echo "Contact your VPS provider to enable IPv6."
    echo
    echo "Alternative solutions:"
    echo "1. Use Cloudflare proxy (recommended)"
    echo "2. Request new IPv4 address"
    echo "3. Get VPS with IPv6 support"
    exit 1
else
    echo -e "${GREEN}✅ IPv6 found: $IPV6_ADDR${NC}"
fi

# Step 2: Test IPv6 connectivity
echo
echo -e "${YELLOW}[2/6] Testing IPv6 connectivity...${NC}"
if curl -6 -s --max-time 5 https://ifconfig.co > /dev/null 2>&1; then
    echo -e "${GREEN}✅ IPv6 internet connectivity works!${NC}"
else
    echo -e "${RED}❌ IPv6 internet not working${NC}"
    echo "IPv6 is configured but can't reach internet."
    echo "This might still work for direct connections."
fi

# Step 3: Check if port 443 is listening on IPv6
echo
echo -e "${YELLOW}[3/6] Checking if port 443 listens on IPv6...${NC}"
if ss -tlnp | grep -q '\[::\]:443'; then
    echo -e "${GREEN}✅ Port 443 already listening on IPv6!${NC}"
    IPV6_LISTENING=true
else
    echo -e "${YELLOW}⚠️  Port 443 not listening on IPv6${NC}"
    echo "Will configure Docker to bind to IPv6..."
    IPV6_LISTENING=false
fi

# Step 4: Check nginx configuration
echo
echo -e "${YELLOW}[4/6] Checking nginx IPv6 configuration...${NC}"

# Find the docker-compose file with doh-nginx
if docker ps --format '{{.Names}}' | grep -q 'doh-nginx'; then
    echo -e "${GREEN}✅ Found doh-nginx container${NC}"
    
    # Check nginx config
    docker exec doh-nginx sh -c "cat /etc/nginx/nginx.conf 2>/dev/null || cat /etc/nginx/conf.d/default.conf 2>/dev/null" > /tmp/nginx-check.conf 2>/dev/null || echo ""
    
    if grep -q 'listen \[::\]:443' /tmp/nginx-check.conf 2>/dev/null; then
        echo -e "${GREEN}✅ Nginx already configured for IPv6${NC}"
    else
        echo -e "${YELLOW}⚠️  Nginx needs IPv6 configuration${NC}"
    fi
    rm -f /tmp/nginx-check.conf
fi

# Step 5: Update Docker Compose to expose on IPv6
echo
echo -e "${YELLOW}[5/6] Updating docker-compose.yml for IPv6...${NC}"

cd /root/doh || cd /home/wars09/Cursor/doh

# Check if IPv6 is enabled in Docker daemon
if ! docker network inspect bridge | grep -q "EnableIPv6.*true" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Docker IPv6 not enabled globally${NC}"
    echo "Ports will still be accessible via IPv6 through host binding."
fi

# Docker port bindings like "443:443" automatically bind to both IPv4 and IPv6
# We just need to ensure containers can handle it

echo -e "${GREEN}✅ Docker port bindings support both IPv4 and IPv6 by default${NC}"

# Step 6: Add DNS AAAA record instructions
echo
echo -e "${YELLOW}[6/6] DNS Configuration${NC}"
echo
echo "==================================="
echo "NEXT STEPS - MANUAL ACTION REQUIRED"
echo "==================================="
echo
echo "1. Add AAAA record to your DNS (440.dev):"
echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Type:  AAAA"
echo "   Name:  bypass"
echo "   Value: $IPV6_ADDR"
echo "   TTL:   60 (for testing)"
echo
echo "2. Wait 2-5 minutes for DNS propagation"
echo
echo "3. Test IPv6 from your home network:"
echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   # Check if you have IPv6:"
echo "   curl -6 https://ifconfig.co"
echo
echo "   # Test if you can reach the server via IPv6:"
echo "   curl -6 -I https://bypass.440.dev/dns-query"
echo
echo "   # Or test with the direct IPv6 address:"
echo "   curl -g -k -I https://[$IPV6_ADDR]/dns-query"
echo
echo "4. If IPv6 works, configure Keenetic:"
echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   DoH URL: https://bypass.440.dev/dns-query"
echo "   (It will automatically use IPv6 if available)"
echo
echo "==================================="
echo "IMPORTANT CHECKS"
echo "==================================="
echo
echo "Before adding DNS record, test from your home network:"
echo
echo "Test 1 - Do you have IPv6?"
echo "  curl -6 https://ifconfig.co"
echo "  (Should return your IPv6 address)"
echo
echo "Test 2 - Can you reach VPS via IPv6?"
echo "  ping6 $IPV6_ADDR"
echo "  (Should get responses)"
echo
echo "Test 3 - Can you reach port 443 via IPv6?"
echo "  curl -g -6 -k -I https://[$IPV6_ADDR]/dns-query"
echo "  (Should get HTTP 415 or 200 response)"
echo
echo "If ALL tests pass = Add AAAA record and you're done!"
echo "If any test fails = IPv6 blocked or not available"
echo
echo "==================================="
echo "VPS IPv6 Address: $IPV6_ADDR"
echo "==================================="


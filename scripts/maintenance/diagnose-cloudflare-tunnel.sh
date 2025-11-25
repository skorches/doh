#!/bin/bash

# Diagnose Cloudflare Tunnel setup issues

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
echo "Cloudflare Tunnel Diagnosis"
echo "================================================"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "unknown")
echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Check 1: DNS Resolution
echo -e "${YELLOW}[1/6] Testing DNS Resolution...${NC}"
echo ""

# Test from VPS (should return Cloudflare IP, not VPS IP)
XBOX_DNS=$(dig +short xboxlive.com @1.1.1.1 | head -1 || echo "")
if [ -z "$XBOX_DNS" ]; then
    echo -e "${RED}❌ Could not resolve xboxlive.com${NC}"
else
    echo -e "${BLUE}xboxlive.com resolves to: $XBOX_DNS${NC}"
    
    if echo "$XBOX_DNS" | grep -q "$VPS_IP"; then
        echo -e "${RED}❌ PROBLEM: DNS still returning VPS IP!${NC}"
        echo "   This means DNS records in Cloudflare are not set up correctly."
        echo "   Or CoreDNS is still returning VPS IP."
    elif echo "$XBOX_DNS" | grep -qE "^104\.|^172\.|^198\.|^141\.|^188\."; then
        echo -e "${GREEN}✅ DNS returning Cloudflare IP${NC}"
    else
        echo -e "${YELLOW}⚠ DNS returning: $XBOX_DNS (might be Cloudflare IP)${NC}"
    fi
fi

# Test through local CoreDNS
echo ""
echo -e "${BLUE}Testing through local CoreDNS (what Xbox uses)...${NC}"
LOCAL_DNS=$(dig +short xboxlive.com @127.0.0.1 2>/dev/null | head -1 || echo "")
if [ -z "$LOCAL_DNS" ]; then
    echo -e "${RED}❌ CoreDNS not responding${NC}"
elif echo "$LOCAL_DNS" | grep -q "$VPS_IP"; then
    echo -e "${RED}❌ PROBLEM: CoreDNS still returning VPS IP!${NC}"
    echo "   CoreDNS xbox-hosts file still has VPS IP entries."
    echo "   Run: ./scripts/maintenance/migrate-to-cloudflare-tunnel.sh"
else
    echo -e "${GREEN}✅ CoreDNS returning: $LOCAL_DNS${NC}"
    if echo "$LOCAL_DNS" | grep -qE "^104\.|^172\.|^198\.|^141\.|^188\."; then
        echo -e "${GREEN}   (Looks like Cloudflare IP)${NC}"
    fi
fi

# Check 2: Cloudflare Tunnel Status
echo ""
echo -e "${YELLOW}[2/6] Checking Cloudflare Tunnel Status...${NC}"

if systemctl is-active --quiet cloudflared-tunnel 2>/dev/null || systemctl is-active --quiet cloudflared 2>/dev/null; then
    echo -e "${GREEN}✅ Cloudflare Tunnel service is running${NC}"
    
    # Check tunnel process
    if pgrep -f cloudflared > /dev/null; then
        echo -e "${GREEN}✅ cloudflared process is running${NC}"
    else
        echo -e "${RED}❌ cloudflared process not found${NC}"
    fi
else
    echo -e "${RED}❌ Cloudflare Tunnel service NOT running${NC}"
    echo "   Check: systemctl status cloudflared-tunnel"
    echo "   Or: systemctl status cloudflared"
fi

# Check tunnel logs
if [ -f /var/log/cloudflared.log ] || journalctl -u cloudflared-tunnel -n 5 --no-pager 2>/dev/null | grep -q .; then
    echo ""
    echo -e "${BLUE}Recent tunnel logs:${NC}"
    journalctl -u cloudflared-tunnel -n 5 --no-pager 2>/dev/null || journalctl -u cloudflared -n 5 --no-pager 2>/dev/null || tail -5 /var/log/cloudflared.log 2>/dev/null | head -5
fi

# Check 3: SNIProxy Status
echo ""
echo -e "${YELLOW}[3/6] Checking SNIProxy Status...${NC}"

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    
    # Check if listening on 443
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "${YELLOW}⚠ SNIProxy running but not listening on 443${NC}"
        ss -tlnp | grep ":443" || echo "Nothing on port 443"
    fi
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
    echo "   Start it: systemctl start sniproxy"
fi

# Check 4: Tunnel Configuration
echo ""
echo -e "${YELLOW}[4/6] Checking Tunnel Configuration...${NC}"

TUNNEL_CONFIG="/etc/cloudflared/config.yml"
if [ -f "$TUNNEL_CONFIG" ]; then
    echo -e "${GREEN}✅ Tunnel config found: $TUNNEL_CONFIG${NC}"
    
    # Check if it routes to 127.0.0.1:443
    if grep -q "127.0.0.1:443" "$TUNNEL_CONFIG"; then
        echo -e "${GREEN}✅ Config routes to 127.0.0.1:443${NC}"
    else
        echo -e "${RED}❌ Config does NOT route to 127.0.0.1:443${NC}"
        echo "   Current routing:"
        grep -E "service|url" "$TUNNEL_CONFIG" | head -5
    fi
    
    # Check service type
    if grep -q "tcp://" "$TUNNEL_CONFIG"; then
        echo -e "${GREEN}✅ Using TCP service (correct for SNIProxy)${NC}"
    else
        echo -e "${YELLOW}⚠ Not using TCP service${NC}"
        echo "   SNIProxy requires TCP, not HTTP/HTTPS"
    fi
else
    echo -e "${RED}❌ Tunnel config not found${NC}"
    echo "   Expected: $TUNNEL_CONFIG"
fi

# Check 5: DNS Records in Cloudflare
echo ""
echo -e "${YELLOW}[5/6] Checking DNS Configuration...${NC}"

# Check if xbox-hosts still has VPS IP
if [ -f coredns/xbox-hosts ]; then
    XBOX_IN_HOSTS=$(grep -c "xboxlive.com" coredns/xbox-hosts 2>/dev/null || echo "0")
    XBOX_IN_HOSTS=${XBOX_IN_HOSTS:-0}
    if [ "$XBOX_IN_HOSTS" -gt 0 ]; then
        echo -e "${RED}❌ PROBLEM: xbox-hosts still contains xboxlive.com${NC}"
        echo "   This means CoreDNS will return VPS IP, not Cloudflare IP."
        echo "   Run: ./scripts/maintenance/migrate-to-cloudflare-tunnel.sh"
    else
        echo -e "${GREEN}✅ xbox-hosts does not contain xboxlive.com${NC}"
        echo "   CoreDNS will forward to Cloudflare DNS"
    fi
else
    echo -e "${YELLOW}⚠ xbox-hosts file not found${NC}"
fi

# Check Corefile
if [ -f coredns/Corefile ]; then
    if grep -q "forward.*1.1.1.1" coredns/Corefile; then
        echo -e "${GREEN}✅ Corefile forwards to Cloudflare DNS${NC}"
    else
        echo -e "${YELLOW}⚠ Corefile might not forward to Cloudflare DNS${NC}"
    fi
fi

# Check 6: Test Connection Through Tunnel
echo ""
echo -e "${YELLOW}[6/6] Testing Connection Through Tunnel...${NC}"

# Get tunnel domain from config or ask user
TUNNEL_DOMAIN=$(grep -oP 'hostname:\s*\K[^\s]+' /etc/cloudflared/config.yml 2>/dev/null | head -1 || echo "")

if [ -z "$TUNNEL_DOMAIN" ]; then
    read -p "Enter your Cloudflare tunnel domain (e.g., xbox-proxy.example.com): " TUNNEL_DOMAIN
fi

if [ -n "$TUNNEL_DOMAIN" ]; then
    echo -e "${BLUE}Testing tunnel domain: $TUNNEL_DOMAIN${NC}"
    
    # Resolve tunnel domain
    TUNNEL_IP=$(dig +short "$TUNNEL_DOMAIN" @1.1.1.1 | head -1 || echo "")
    if [ -n "$TUNNEL_IP" ]; then
        echo -e "${GREEN}✅ Tunnel domain resolves to: $TUNNEL_IP${NC}"
        
        if echo "$TUNNEL_IP" | grep -qE "^104\.|^172\.|^198\.|^141\.|^188\."; then
            echo -e "${GREEN}   (Looks like Cloudflare IP)${NC}"
        fi
    else
        echo -e "${RED}❌ Could not resolve tunnel domain${NC}"
    fi
    
    # Test connection
    echo ""
    echo -e "${BLUE}Testing connection through tunnel...${NC}"
    TEST_RESULT=$(timeout 5 curl -k -s -I --resolve "xboxlive.com:443:$TUNNEL_IP" "https://xboxlive.com" 2>&1 | head -3 || echo "TIMEOUT")
    
    if echo "$TEST_RESULT" | grep -qE "HTTP/.*200|HTTP/.*301|HTTP/.*302"; then
        echo -e "${GREEN}✅ Connection through tunnel works${NC}"
    elif echo "$TEST_RESULT" | grep -q "TIMEOUT"; then
        echo -e "${RED}❌ Connection timeout${NC}"
    else
        echo -e "${YELLOW}⚠ Connection result:${NC}"
        echo "$TEST_RESULT" | head -3
    fi
fi

# Summary
echo ""
echo "================================================"
echo "Diagnosis Summary"
echo "================================================"
echo ""

ISSUES=0

# Check for common issues
if echo "$LOCAL_DNS" | grep -q "$VPS_IP" 2>/dev/null; then
    echo -e "${RED}❌ ISSUE: CoreDNS still returning VPS IP${NC}"
    echo "   Fix: Run ./scripts/maintenance/migrate-to-cloudflare-tunnel.sh"
    ISSUES=$((ISSUES + 1))
fi

if ! systemctl is-active --quiet cloudflared-tunnel 2>/dev/null && ! systemctl is-active --quiet cloudflared 2>/dev/null; then
    echo -e "${RED}❌ ISSUE: Cloudflare Tunnel not running${NC}"
    echo "   Fix: systemctl start cloudflared-tunnel"
    ISSUES=$((ISSUES + 1))
fi

if ! systemctl is-active --quiet sniproxy; then
    echo -e "${RED}❌ ISSUE: SNIProxy not running${NC}"
    echo "   Fix: systemctl start sniproxy"
    ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✅ No obvious issues found${NC}"
    echo ""
    echo "If Xbox is still blocked, check:"
    echo "  1. DNS records in Cloudflare dashboard"
    echo "     • xboxlive.com → CNAME → $TUNNEL_DOMAIN (proxied)"
    echo "  2. Xbox DNS cache (restart Xbox)"
    echo "  3. Router DoH configuration"
    echo "  4. Test from Xbox network: nslookup xboxlive.com"
else
    echo ""
    echo -e "${YELLOW}Found $ISSUES issue(s) - fix them first${NC}"
fi

echo ""


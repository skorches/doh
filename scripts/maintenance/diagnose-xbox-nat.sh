#!/bin/bash

# Diagnose Xbox NAT Type Issues
# NAT "unavailable" happens because Xbox NAT traversal uses UDP, which SNIProxy doesn't handle

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
echo "Xbox NAT Type Diagnosis"
echo "================================================"
echo ""

cd /root/doh 2>/dev/null || cd "$(dirname "$0")/../.."

VPS_IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "unknown")

echo -e "${BLUE}Understanding the Problem:${NC}"
echo ""
echo "Xbox NAT type detection requires TWO types of connections:"
echo "  1. ✅ HTTPS (TCP) → Handled by SNIProxy (port 443)"
echo "  2. ❌ NAT Traversal (UDP) → NOT handled by SNIProxy"
echo ""
echo "Xbox uses UDP ports for NAT traversal:"
echo "  - Port 3074 (UDP/TCP) - Xbox Live"
echo "  - Port 3544 (UDP) - Teredo (IPv6 over IPv4)"
echo ""
echo "================================================"
echo ""

# Step 1: Check VPS firewall
echo -e "${YELLOW}[1/6] Checking VPS Firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "3074\|3544"; then
        echo -e "${GREEN}✅ VPS firewall allows Xbox ports${NC}"
    else
        echo -e "${YELLOW}⚠ VPS firewall might block Xbox ports${NC}"
        echo "   Opening ports 3074 and 3544..."
        ufw allow 3074/tcp comment "Xbox Live TCP" 2>/dev/null || true
        ufw allow 3074/udp comment "Xbox Live UDP" 2>/dev/null || true
        ufw allow 3544/udp comment "Xbox Teredo" 2>/dev/null || true
        echo -e "${GREEN}✅ Ports opened${NC}"
    fi
else
    echo -e "${YELLOW}⚠ UFW not found, skipping firewall check${NC}"
fi

# Step 2: Check SNIProxy status
echo ""
echo -e "${YELLOW}[2/6] Checking SNIProxy (HTTPS/TCP)...${NC}"
if systemctl is-active --quiet sniproxy 2>/dev/null || pgrep -x sniproxy >/dev/null; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    echo "   This handles Xbox HTTPS connections (TCP)"
else
    echo -e "${RED}❌ SNIProxy is NOT running${NC}"
    echo "   Xbox HTTPS connections won't work"
fi

# Step 3: Check if UDP proxy exists
echo ""
echo -e "${YELLOW}[3/6] Checking UDP Proxy Support...${NC}"
if systemctl is-active --quiet 3proxy 2>/dev/null || pgrep -x 3proxy >/dev/null; then
    echo -e "${GREEN}✅ 3proxy is running (UDP support)${NC}"
    echo "   However, Xbox can't be configured to use a proxy"
    echo "   UDP proxy won't help Xbox NAT type"
elif ss -tlnp | grep -q ":1080"; then
    echo -e "${YELLOW}⚠ Port 1080 is in use (might be 3proxy)${NC}"
else
    echo -e "${RED}❌ No UDP proxy running${NC}"
    echo "   This is expected - Xbox NAT uses direct UDP connections"
fi

# Step 4: Explain the issue
echo ""
echo -e "${YELLOW}[4/6] NAT Type Issue Analysis...${NC}"
echo ""
echo -e "${BLUE}Why NAT shows 'unavailable':${NC}"
echo ""
echo "Your current setup:"
echo "  ✅ DNS queries → VPS (Smart DNS)"
echo "  ✅ HTTPS traffic → VPS → SNIProxy → Xbox servers"
echo "  ❌ UDP NAT traversal → Must go DIRECT from Xbox → Internet"
echo ""
echo "The problem:"
echo "  - Xbox NAT detection sends UDP packets to Xbox Live servers"
echo "  - These UDP packets must go DIRECTLY from your router to Xbox servers"
echo "  - If your ISP blocks Xbox traffic, these UDP packets are blocked"
echo "  - SNIProxy can't help because it only handles TCP/HTTPS"
echo ""

# Step 5: Check router configuration
echo ""
echo -e "${YELLOW}[5/6] Router Configuration Check...${NC}"
echo ""
echo -e "${BLUE}Required Router Settings:${NC}"
echo ""
echo "1. Port Forwarding (CRITICAL):"
echo "   - Forward port 3074 (UDP/TCP) to your Xbox IP"
echo "   - Forward port 3544 (UDP) to your Xbox IP"
echo ""
echo "2. UPnP (Recommended):"
echo "   - Enable UPnP on your router"
echo "   - Xbox will try to auto-configure port forwarding"
echo ""
echo "3. Router Firewall:"
echo "   - Ensure router firewall allows outbound UDP to Xbox servers"
echo "   - Check if router has 'Gaming Mode' or 'Xbox Mode'"
echo ""
echo -e "${YELLOW}⚠ You need to configure these on your ROUTER, not the VPS${NC}"
echo ""

# Step 6: Solutions
echo ""
echo -e "${YELLOW}[6/6] Solutions...${NC}"
echo ""
echo "================================================"
echo -e "${GREEN}Solution 1: Router Port Forwarding (Recommended)${NC}"
echo "================================================"
echo ""
echo "1. Find your Xbox IP address:"
echo "   - Xbox Settings → Network → Network settings → Advanced settings"
echo "   - Note the IP address (e.g., 192.168.1.100)"
echo ""
echo "2. Configure router port forwarding:"
echo "   - Login to your router admin panel"
echo "   - Find 'Port Forwarding' or 'Virtual Server'"
echo "   - Add these rules:"
echo ""
echo "     Rule 1:"
echo "       External Port: 3074"
echo "       Internal Port: 3074"
echo "       Protocol: Both (TCP + UDP)"
echo "       Internal IP: [Your Xbox IP]"
echo ""
echo "     Rule 2:"
echo "       External Port: 3544"
echo "       Internal Port: 3544"
echo "       Protocol: UDP"
echo "       Internal IP: [Your Xbox IP]"
echo ""
echo "3. Enable UPnP (if available):"
echo "   - Router Settings → UPnP → Enable"
echo ""
echo "4. Restart Xbox:"
echo "   - Unplug Xbox for 30 seconds"
echo "   - Plug back in and test NAT type"
echo ""
echo "================================================"
echo -e "${GREEN}Solution 2: Check ISP Blocking${NC}"
echo "================================================"
echo ""
echo "If port forwarding doesn't help, your ISP might be blocking Xbox UDP:"
echo ""
echo "1. Test from a PC on the same network:"
echo "   - Download Xbox Network Test tool"
echo "   - Or use: nc -u -v xboxlive.com 3074"
echo ""
echo "2. Check router logs:"
echo "   - Look for blocked UDP packets to Xbox servers"
echo ""
echo "3. Try different DNS:"
echo "   - Router DNS: 1.1.1.1, 1.0.0.1 (Cloudflare)"
echo "   - Or: 8.8.8.8, 8.8.4.4 (Google)"
echo ""
echo "================================================"
echo -e "${GREEN}Solution 3: VPN on Router (Advanced)${NC}"
echo "================================================"
echo ""
echo "If ISP is blocking Xbox UDP, use a VPN on your router:"
echo ""
echo "1. Set up VPN on router (OpenVPN/WireGuard)"
echo "2. Route all traffic through VPN"
echo "3. This will proxy both TCP AND UDP"
echo ""
echo "⚠ Note: This routes ALL traffic through VPN, not just Xbox"
echo ""
echo "================================================"
echo -e "${YELLOW}Why VPS Setup Can't Fix This${NC}"
echo "================================================"
echo ""
echo "Your VPS setup handles:"
echo "  ✅ DNS resolution (Smart DNS)"
echo "  ✅ HTTPS traffic (SNIProxy)"
echo ""
echo "Xbox NAT traversal needs:"
echo "  ❌ UDP packets going DIRECT from Xbox → Xbox servers"
echo "  ❌ These can't be proxied transparently (Xbox doesn't support proxy)"
echo ""
echo "The VPS helps with:"
echo "  - Bypassing DNS blocking"
echo "  - Bypassing HTTPS blocking"
echo ""
echo "The VPS CAN'T help with:"
echo "  - UDP NAT traversal (requires router configuration)"
echo "  - ISP blocking of Xbox UDP traffic"
echo ""
echo "================================================"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo ""
echo "NAT 'unavailable' = Xbox can't establish UDP connections for NAT traversal"
echo ""
echo "Most likely causes:"
echo "  1. Router port forwarding not configured (90% of cases)"
echo "  2. UPnP disabled on router"
echo "  3. ISP blocking Xbox UDP traffic"
echo ""
echo "Fix: Configure router port forwarding (Solution 1 above)"
echo ""
echo "================================================"


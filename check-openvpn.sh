#!/bin/bash

# Check Existing OpenVPN Configuration
# This helps identify potential conflicts

echo "================================================"
echo "OpenVPN Configuration Check"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m'

# Check if OpenVPN is running
echo -e "${BLUE}Checking OpenVPN status...${NC}"
if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
    echo -e "${GREEN}✓ OpenVPN is running${NC}"
    OPENVPN_RUNNING=true
else
    echo -e "${YELLOW}⚠ OpenVPN service not detected as running${NC}"
    OPENVPN_RUNNING=false
fi
echo ""

# Check OpenVPN processes
echo -e "${BLUE}Checking OpenVPN processes...${NC}"
if pgrep -x openvpn > /dev/null; then
    echo -e "${GREEN}✓ OpenVPN process found${NC}"
    ps aux | grep [o]penvpn
else
    echo -e "${YELLOW}⚠ No OpenVPN process found${NC}"
fi
echo ""

# Check which ports OpenVPN is using
echo -e "${BLUE}Checking OpenVPN ports...${NC}"
OPENVPN_PORTS=$(netstat -tulpn 2>/dev/null | grep openvpn || ss -tulpn 2>/dev/null | grep openvpn || echo "Unable to detect")
if [ "$OPENVPN_PORTS" != "Unable to detect" ]; then
    echo "$OPENVPN_PORTS"
    
    # Check for specific port conflicts
    if echo "$OPENVPN_PORTS" | grep -q ":443"; then
        echo -e "${RED}⚠ WARNING: OpenVPN is using port 443!${NC}"
        echo "  This will conflict with deploy-doh-443.sh"
        PORT_443_CONFLICT=true
    else
        echo -e "${GREEN}✓ Port 443 is available${NC}"
        PORT_443_CONFLICT=false
    fi
    
    if echo "$OPENVPN_PORTS" | grep -q ":53"; then
        echo -e "${YELLOW}⚠ OpenVPN might be handling DNS on port 53${NC}"
        PORT_53_CONFLICT=true
    else
        echo -e "${GREEN}✓ Port 53 is available${NC}"
        PORT_53_CONFLICT=false
    fi
else
    echo -e "${YELLOW}Unable to detect ports (might need root)${NC}"
fi
echo ""

# Check OpenVPN configuration
echo -e "${BLUE}Checking OpenVPN configuration files...${NC}"
if [ -f /etc/openvpn/server.conf ]; then
    echo -e "${GREEN}✓ Found: /etc/openvpn/server.conf${NC}"
    
    # Extract key settings
    echo ""
    echo "Key settings:"
    echo "  Port: $(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')"
    echo "  Protocol: $(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}')"
    echo "  VPN Network: $(grep "^server " /etc/openvpn/server.conf | awk '{print $2, $3}')"
    
    # Check DNS settings
    echo ""
    echo "  DNS Push Settings:"
    grep "push.*dns" /etc/openvpn/server.conf 2>/dev/null || echo "    None configured"
    
    OPENVPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
    OPENVPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}')
    OPENVPN_NETWORK=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2}')
else
    echo -e "${YELLOW}⚠ No server.conf found in /etc/openvpn/${NC}"
    
    # Check for other config files
    if ls /etc/openvpn/*.conf 1> /dev/null 2>&1; then
        echo "Found other config files:"
        ls -l /etc/openvpn/*.conf
    fi
fi
echo ""

# Check IP forwarding
echo -e "${BLUE}Checking IP forwarding...${NC}"
IP_FORWARD=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
if [ "$IP_FORWARD" == "1" ]; then
    echo -e "${GREEN}✓ IP forwarding is enabled${NC}"
else
    echo -e "${YELLOW}⚠ IP forwarding is disabled${NC}"
fi
echo ""

# Check iptables NAT rules
echo -e "${BLUE}Checking iptables NAT rules...${NC}"
if iptables -t nat -L POSTROUTING -n | grep -q MASQUERADE; then
    echo -e "${GREEN}✓ NAT/MASQUERADE rules found${NC}"
    iptables -t nat -L POSTROUTING -n | grep MASQUERADE
else
    echo -e "${YELLOW}⚠ No MASQUERADE rules found${NC}"
fi
echo ""

# Check routing
echo -e "${BLUE}Checking network interfaces...${NC}"
ip addr show | grep -E "tun|tap" || echo "No VPN interfaces found"
echo ""

# Summary and recommendations
echo "================================================"
echo "Summary & Recommendations"
echo "================================================"
echo ""

if [ "$OPENVPN_RUNNING" = true ]; then
    echo -e "${GREEN}✓ You have OpenVPN running${NC}"
    echo ""
    
    if [ "$PORT_443_CONFLICT" = true ]; then
        echo -e "${RED}CONFLICT: OpenVPN uses port 443${NC}"
        echo ""
        echo "Options:"
        echo "  1) Keep OpenVPN on 443, skip deploy-doh-443.sh"
        echo "     → Just add DoH to existing OpenVPN"
        echo "     → Run: ./integrate-doh-openvpn.sh"
        echo ""
        echo "  2) Move OpenVPN to different port (e.g., 1194)"
        echo "     → Then deploy DoH on 443"
        echo ""
        echo "  3) Use standard DoH deployment (not on 443)"
        echo "     → Run: ./deploy.sh"
        echo "     → OpenVPN clients can use DoH internally"
    else
        echo -e "${GREEN}✓ No port conflicts detected!${NC}"
        echo ""
        echo "You can:"
        echo "  1) Deploy DoH alongside existing OpenVPN"
        echo "     → Run: ./deploy.sh or ./deploy-doh-443.sh"
        echo "     → Both will work together"
        echo ""
        echo "  2) Integrate DoH with OpenVPN"
        echo "     → Run: ./integrate-doh-openvpn.sh"
        echo "     → OpenVPN clients automatically use DoH"
        echo ""
        echo "  3) Just use your existing OpenVPN for Xbox"
        echo "     → See: EXISTING_OPENVPN.md"
        echo "     → No additional setup needed!"
    fi
else
    echo -e "${YELLOW}OpenVPN doesn't seem to be running${NC}"
    echo "You can safely deploy any configuration"
fi

echo ""
echo "================================================"
echo "Your OpenVPN Configuration:"
echo "================================================"
if [ -n "$OPENVPN_PORT" ]; then
    echo "  Port: $OPENVPN_PORT"
    echo "  Protocol: $OPENVPN_PROTO"
    echo "  VPN Network: $OPENVPN_NETWORK"
else
    echo "  Unable to determine (check config files)"
fi
echo ""


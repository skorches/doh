#!/bin/bash

# Simple UDP forwarding for Discord voice using socat
# This is a simpler alternative to 3proxy

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
echo "Simple Discord UDP Forwarding Setup"
echo "================================================"
echo ""
echo "This uses iptables DNAT to forward UDP traffic"
echo "for Discord voice chat (ports 50000-65535)"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP: " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Enable IP forwarding
echo -e "${YELLOW}[1/4] Enabling IP forwarding...${NC}"
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p > /dev/null
    echo -e "${GREEN}✅ IP forwarding enabled${NC}"
else
    echo -e "${GREEN}✅ IP forwarding already enabled${NC}"
fi

# Install iptables-persistent if needed
echo ""
echo -e "${YELLOW}[2/4] Installing iptables-persistent...${NC}"
if ! command -v iptables-save &> /dev/null; then
    apt-get update -qq
    apt-get install -y iptables-persistent
fi

# Note: This approach has limitations
# Discord voice servers have dynamic IPs, so we can't forward to a fixed IP
# Instead, we need to use a transparent proxy or SOCKS5

echo ""
echo -e "${YELLOW}[3/4] Creating UDP forwarding script...${NC}"

cat > /usr/local/bin/discord-udp-forward.sh << 'EOFFORWARD'
#!/bin/bash
# Discord UDP forwarding using socat
# This forwards UDP traffic from VPS to Discord voice servers

# Discord voice typically uses ports 50000-65535
# But we need to know the destination IP, which is dynamic

# This is a placeholder - actual implementation would need:
# 1. Packet inspection to determine destination
# 2. Dynamic forwarding based on Discord voice server IP
# 3. Connection tracking

echo "Discord UDP forwarding requires knowing the destination IP"
echo "which is dynamic. Use 3proxy SOCKS5 instead for better results."
EOFFORWARD

chmod +x /usr/local/bin/discord-udp-forward.sh

echo ""
echo -e "${YELLOW}[4/4] Recommendation...${NC}"
echo ""
echo "================================================"
echo "⚠ Simple UDP Forwarding Limitation"
echo "================================================"
echo ""
echo "Discord voice servers use dynamic IPs, making"
echo "simple UDP forwarding difficult."
echo ""
echo "RECOMMENDED SOLUTION:"
echo "────────────────────"
echo "Use 3proxy SOCKS5 proxy instead:"
echo "  ./scripts/setup/setup-discord-udp-proxy.sh"
echo ""
echo "This provides:"
echo "  ✅ Full TCP + UDP support"
echo "  ✅ Works with dynamic Discord server IPs"
echo "  ✅ Easy Discord client configuration"
echo ""
echo "Then configure Discord to use SOCKS5 proxy:"
echo "  - Proxy: $VPS_IP:1080"
echo "  - Type: SOCKS5"
echo ""


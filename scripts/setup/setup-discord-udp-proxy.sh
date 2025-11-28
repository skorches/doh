#!/bin/bash

# Setup UDP proxy for Discord voice chat using 3proxy

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
echo "Discord UDP Proxy Setup (3proxy)"
echo "================================================"
echo ""
echo "This will install 3proxy to handle Discord voice (UDP)"
echo "SNIProxy will continue handling HTTPS (TCP) for text chat"
echo ""

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect VPS IP${NC}"
    read -p "Enter your VPS IP: " VPS_IP
fi

echo -e "${BLUE}VPS IP: $VPS_IP${NC}"
echo ""

# Install 3proxy
echo -e "${YELLOW}[1/5] Installing 3proxy...${NC}"
if command -v 3proxy &> /dev/null; then
    echo -e "${GREEN}✅ 3proxy already installed${NC}"
else
    apt-get update -qq
    apt-get install -y 3proxy
    echo -e "${GREEN}✅ 3proxy installed${NC}"
fi

# Create 3proxy config
echo ""
echo -e "${YELLOW}[2/5] Creating 3proxy configuration...${NC}"

cat > /etc/3proxy/3proxy.cfg << 'EOF3PROXY'
# 3proxy configuration for Discord UDP proxy
# This handles UDP traffic for Discord voice chat
# SNIProxy continues to handle HTTPS (TCP) for text chat

# Logging
log
logformat "- %U %C:%c %R:%r %O %I %h %T"
rotate 30

# Users (no authentication for simplicity)
# In production, you might want to add authentication
users $/etc/3proxy/passwd

# Allow connections from anywhere (adjust if needed)
allow * * * 80-88,8080-8088 HTTP
allow * * * 443,8443 HTTPS
allow * * * 50000-65535 UDP

# HTTP/HTTPS proxy (for text chat - but SNIProxy handles this)
# We'll use this as a fallback if needed
# proxy -p3128

# SOCKS5 proxy with UDP support (for Discord voice)
# This is the key for Discord voice chat
socks -p1080
EOF3PROXY

echo -e "${GREEN}✅ 3proxy config created${NC}"

# Create empty password file (no auth)
echo "" > /etc/3proxy/passwd
chmod 600 /etc/3proxy/passwd

# Create systemd service for 3proxy
echo ""
echo -e "${YELLOW}[3/5] Creating systemd service...${NC}"

cat > /etc/systemd/system/3proxy-discord.service << EOF3PROXY_SERVICE
[Unit]
Description=3proxy UDP Proxy for Discord Voice
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF3PROXY_SERVICE

systemctl daemon-reload
echo -e "${GREEN}✅ Systemd service created${NC}"

# Start 3proxy
echo ""
echo -e "${YELLOW}[4/5] Starting 3proxy...${NC}"
systemctl enable 3proxy-discord
systemctl start 3proxy-discord
sleep 2

if systemctl is-active --quiet 3proxy-discord; then
    echo -e "${GREEN}✅ 3proxy started${NC}"
else
    echo -e "${RED}❌ Failed to start 3proxy${NC}"
    journalctl -u 3proxy-discord -n 10 --no-pager
    exit 1
fi

# Configure firewall
echo ""
echo -e "${YELLOW}[5/5] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 1080/tcp comment "3proxy SOCKS5 TCP"
    ufw allow 1080/udp comment "3proxy SOCKS5 UDP"
    echo -e "${GREEN}✅ Firewall rules added${NC}"
else
    echo -e "${YELLOW}⚠ UFW not found, configure firewall manually${NC}"
fi

echo ""
echo "================================================"
echo "✅ 3proxy Setup Complete!"
echo "================================================"
echo ""
echo "WHAT WAS SETUP:"
echo "───────────────"
echo "✅ 3proxy installed and configured"
echo "✅ SOCKS5 proxy on port 1080 (TCP + UDP)"
echo "✅ Systemd service created and started"
echo ""
echo "HOW TO USE:"
echo "───────────"
echo "1. Configure Discord to use SOCKS5 proxy:"
echo "   - Proxy: $VPS_IP"
echo "   - Port: 1080"
echo "   - Type: SOCKS5"
echo ""
echo "2. Discord Settings:"
echo "   - User Settings → Connections → Proxy"
echo "   - Enable proxy"
echo "   - Enter: $VPS_IP:1080"
echo "   - Type: SOCKS5"
echo ""
echo "CURRENT SETUP:"
echo "──────────────"
echo "✅ SNIProxy: Handles HTTPS (TCP) on port 443"
echo "✅ 3proxy: Handles SOCKS5 (TCP + UDP) on port 1080"
echo ""
echo "NOTE:"
echo "─────"
echo "You can use either:"
echo "  - SNIProxy (automatic, no Discord config) for HTTPS"
echo "  - 3proxy SOCKS5 (requires Discord proxy settings) for full support"
echo ""
echo "For best results, configure Discord to use the SOCKS5 proxy!"
echo ""


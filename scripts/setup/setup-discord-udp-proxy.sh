#!/bin/bash

# Setup UDP proxy for Discord voice chat using 3proxy (from source)

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
echo "Discord UDP Proxy Setup (3proxy from source)"
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

# Check if 3proxy is already installed
if command -v 3proxy &> /dev/null; then
    echo -e "${GREEN}✅ 3proxy already installed${NC}"
    SKIP_INSTALL=true
else
    SKIP_INSTALL=false
fi

# Install dependencies
echo -e "${YELLOW}[1/6] Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y build-essential wget make gcc

# Install 3proxy from source
if [ "$SKIP_INSTALL" = false ]; then
    echo ""
    echo -e "${YELLOW}[2/6] Installing 3proxy from source...${NC}"
    
    BUILD_DIR="/tmp/3proxy-build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Download 3proxy source
    echo "Downloading 3proxy source..."
    wget -q https://github.com/z3APA3A/3proxy/archive/refs/heads/master.zip -O 3proxy.zip || {
        echo -e "${RED}❌ Failed to download 3proxy source${NC}"
        echo "Trying alternative: Docker container approach..."
        exit 1
    }
    
    unzip -q 3proxy.zip
    cd 3proxy-master
    
    # Build 3proxy
    echo "Building 3proxy..."
    make -f Makefile.Linux > /dev/null 2>&1 || {
        echo -e "${RED}❌ Failed to build 3proxy${NC}"
        echo "Trying alternative installation method..."
        
        # Alternative: Install from pre-built binary or use Docker
        echo ""
        echo "Alternative: Using Docker container with 3proxy..."
        cd /root/doh
        
        # Create docker-compose entry for 3proxy
        if [ -f docker-compose.yml ]; then
            echo "Adding 3proxy to docker-compose.yml..."
            # We'll add this manually or use a separate container
        fi
        
        exit 1
    }
    
    # Install 3proxy
    cp bin/3proxy /usr/bin/3proxy
    chmod +x /usr/bin/3proxy
    mkdir -p /etc/3proxy
    
    cd /
    rm -rf "$BUILD_DIR"
    
    echo -e "${GREEN}✅ 3proxy installed${NC}"
else
    echo -e "${GREEN}✅ 3proxy already installed, skipping build${NC}"
fi

# Create 3proxy config
echo ""
echo -e "${YELLOW}[3/6] Creating 3proxy configuration...${NC}"

mkdir -p /etc/3proxy

cat > /etc/3proxy/3proxy.cfg << 'EOF3PROXY'
# 3proxy configuration for Discord UDP proxy
# This handles UDP traffic for Discord voice chat
# SNIProxy continues to handle HTTPS (TCP) for text chat

# Logging
log
logformat "- %U %C:%c %R:%r %O %I %h %T"
rotate 30

# Allow connections from anywhere (adjust if needed)
# Discord uses ports 50000-65535 for voice
allow * * * 80-88,8080-8088 HTTP
allow * * * 443,8443 HTTPS
allow * * * 50000-65535 UDP

# SOCKS5 proxy with UDP support (for Discord voice)
# This is the key for Discord voice chat
# Port 1080 for SOCKS5
socks -p1080
EOF3PROXY

echo -e "${GREEN}✅ 3proxy config created${NC}"

# Create empty password file (no auth for simplicity)
echo "" > /etc/3proxy/passwd
chmod 600 /etc/3proxy/passwd

# Create systemd service for 3proxy
echo ""
echo -e "${YELLOW}[4/6] Creating systemd service...${NC}"

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
echo -e "${YELLOW}[5/6] Starting 3proxy...${NC}"
systemctl enable 3proxy-discord
systemctl start 3proxy-discord
sleep 2

if systemctl is-active --quiet 3proxy-discord; then
    echo -e "${GREEN}✅ 3proxy started${NC}"
    
    # Check if listening
    if ss -tlnp | grep -q ":1080"; then
        echo -e "${GREEN}✅ 3proxy listening on port 1080${NC}"
    else
        echo -e "${YELLOW}⚠ 3proxy running but not listening on 1080 yet${NC}"
    fi
else
    echo -e "${RED}❌ Failed to start 3proxy${NC}"
    echo "Checking logs..."
    journalctl -u 3proxy-discord -n 20 --no-pager
    exit 1
fi

# Configure firewall
echo ""
echo -e "${YELLOW}[6/6] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 1080/tcp comment "3proxy SOCKS5 TCP" 2>/dev/null || true
    ufw allow 1080/udp comment "3proxy SOCKS5 UDP" 2>/dev/null || true
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
echo "   - Discord Settings → Connections → Proxy"
echo "   - Enable proxy"
echo "   - Proxy: $VPS_IP"
echo "   - Port: 1080"
echo "   - Type: SOCKS5"
echo "   - Save and restart Discord"
echo ""
echo "CURRENT SETUP:"
echo "──────────────"
echo "✅ SNIProxy: Handles HTTPS (TCP) on port 443 (automatic)"
echo "✅ 3proxy: Handles SOCKS5 (TCP + UDP) on port 1080 (requires Discord config)"
echo ""
echo "NOTE:"
echo "─────"
echo "For voice chat to work, you MUST configure Discord"
echo "to use the SOCKS5 proxy (Settings → Connections → Proxy)"
echo ""

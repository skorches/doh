#!/bin/bash

# Setup Cloudflare Tunnel to hide Russian VPS IP from Xbox

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
echo "Cloudflare Tunnel Setup for Xbox Bypass"
echo "================================================"
echo ""
echo "This will create a Cloudflare Tunnel to hide"
echo "your Russian VPS IP from Xbox servers."
echo ""
echo -e "${YELLOW}Requirements:${NC}"
echo "  • Cloudflare account"
echo "  • Domain on Cloudflare"
echo "  • Cloudflare API token"
echo ""

read -p "Continue? (y/n): " REPLY
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}Installing cloudflared...${NC}"
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    else
        echo -e "${RED}❌ Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    # Download cloudflared
    cd /tmp
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH} -O cloudflared
    chmod +x cloudflared
    mv cloudflared /usr/local/bin/
    
    echo -e "${GREEN}✅ cloudflared installed${NC}"
else
    echo -e "${GREEN}✅ cloudflared already installed${NC}"
fi

echo ""
echo -e "${YELLOW}Cloudflare Tunnel Setup${NC}"
echo ""
echo "You need to:"
echo "  1. Log in to Cloudflare: cloudflared tunnel login"
echo "  2. Create a tunnel: cloudflared tunnel create xbox-bypass"
echo "  3. Configure DNS: cloudflared tunnel route dns xbox-bypass xbox-proxy.yourdomain.com"
echo ""
echo "OR use quick setup with API token:"
echo ""

read -p "Do you have a Cloudflare API token? (y/n): " HAS_TOKEN
if [[ $HAS_TOKEN =~ ^[Yy]$ ]]; then
    read -p "Enter Cloudflare API token: " CF_TOKEN
    read -p "Enter your Cloudflare account ID: " CF_ACCOUNT_ID
    read -p "Enter domain for tunnel (e.g., xbox-proxy.yourdomain.com): " TUNNEL_DOMAIN
    
    echo ""
    echo -e "${YELLOW}Creating tunnel...${NC}"
    
    # Create tunnel
    TUNNEL_NAME="xbox-bypass-$(date +%s)"
    TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" --token "$CF_TOKEN" 2>&1 || echo "ERROR")
    
    if echo "$TUNNEL_OUTPUT" | grep -q "ERROR"; then
        echo -e "${RED}❌ Failed to create tunnel${NC}"
        echo "$TUNNEL_OUTPUT"
        exit 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
    
    if [ -z "$TUNNEL_ID" ]; then
        echo -e "${RED}❌ Could not extract tunnel ID${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Tunnel created: $TUNNEL_ID${NC}"
    
    # Create config directory
    mkdir -p /etc/cloudflared
    TUNNEL_CONFIG="/etc/cloudflared/config.yml"
    
    # Create tunnel config
    cat > "$TUNNEL_CONFIG" << EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  # Route Xbox SNIProxy traffic through tunnel
  - hostname: $TUNNEL_DOMAIN
    service: tcp://127.0.0.1:443
  
  # Catch-all
  - service: http_status:404
EOF
    
    echo -e "${GREEN}✅ Tunnel config created${NC}"
    
    # Route DNS
    echo ""
    echo -e "${YELLOW}Routing DNS...${NC}"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_DOMAIN" --token "$CF_TOKEN" 2>&1 || echo -e "${YELLOW}⚠ DNS routing may have failed (you can do this manually)${NC}"
    
    echo ""
    echo -e "${GREEN}✅ Tunnel configured${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Update your DNS to point Xbox domains to: $TUNNEL_DOMAIN"
    echo "  2. Start tunnel: cloudflared tunnel run $TUNNEL_NAME"
    echo "  3. Or create systemd service (recommended)"
    echo ""
    
    read -p "Create systemd service? (y/n): " CREATE_SERVICE
    if [[ $CREATE_SERVICE =~ ^[Yy]$ ]]; then
        # Create systemd service
        cat > /etc/systemd/system/cloudflared-tunnel.service << EOFSERVICE
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel run $TUNNEL_NAME
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFSERVICE
        
        systemctl daemon-reload
        systemctl enable cloudflared-tunnel
        systemctl start cloudflared-tunnel
        
        echo -e "${GREEN}✅ Systemd service created and started${NC}"
    fi
    
else
    echo ""
    echo "Manual setup required:"
    echo ""
    echo "1. Log in to Cloudflare:"
    echo "   cloudflared tunnel login"
    echo ""
    echo "2. Create tunnel:"
    echo "   cloudflared tunnel create xbox-bypass"
    echo ""
    echo "3. Create config at /etc/cloudflared/config.yml:"
    echo "   tunnel: <tunnel-id>"
    echo "   credentials-file: /etc/cloudflared/<tunnel-id>.json"
    echo "   ingress:"
    echo "     - hostname: xbox-proxy.yourdomain.com"
    echo "       service: tcp://127.0.0.1:443"
    echo ""
    echo "4. Route DNS:"
    echo "   cloudflared tunnel route dns xbox-bypass xbox-proxy.yourdomain.com"
    echo ""
    echo "5. Run tunnel:"
    echo "   cloudflared tunnel run xbox-bypass"
    echo ""
fi

echo ""
echo "================================================"
echo "Important Notes"
echo "================================================"
echo ""
echo "⚠️  This setup routes SNIProxy traffic through"
echo "   Cloudflare, which will:"
echo "   • Hide your Russian VPS IP from Xbox"
echo "   • Add latency (extra hop)"
echo "   • Route through Cloudflare's network"
echo ""
echo "⚠️  You'll need to update DNS so Xbox domains"
echo "   resolve to the Cloudflare tunnel domain,"
echo "   not directly to VPS IP."
echo ""
echo "⚠️  This is experimental - Xbox might still"
echo "   detect and block proxy traffic."
echo ""


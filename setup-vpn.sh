#!/bin/bash

# WireGuard VPN Setup for Full Traffic Routing
# Use this if DNS-only bypass isn't sufficient due to IP-level blocking

set -e

echo "================================================"
echo "WireGuard VPN Setup for Xbox"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Get VPS IP
VPS_IP=$(hostname -I | awk '{print $1}')
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo -e "${GREEN}Network Interface: $INTERFACE${NC}"
echo ""

# Install WireGuard
echo -e "${YELLOW}Installing WireGuard...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y wireguard wireguard-tools qrencode
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y wireguard-tools qrencode
else
    echo -e "${RED}Unsupported package manager. Please install WireGuard manually.${NC}"
    exit 1
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Create WireGuard directory
mkdir -p /etc/wireguard
cd /etc/wireguard

# Generate server keys
echo -e "${YELLOW}Generating server keys...${NC}"
wg genkey | tee server_private.key | wg pubkey > server_public.key
chmod 600 server_private.key

SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Generate client keys
echo -e "${YELLOW}Generating client keys...${NC}"
wg genkey | tee client_private.key | wg pubkey > client_public.key
chmod 600 client_private.key

CLIENT_PRIVATE_KEY=$(cat client_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

# Create server configuration
echo -e "${YELLOW}Creating WireGuard server configuration...${NC}"
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE

# Client peer (for your router or Windows PC)
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.13.13.2/32
EOF

# Create client configuration
echo -e "${YELLOW}Creating client configuration...${NC}"
cat > /etc/wireguard/client.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.13.13.2/24
DNS = 10.13.13.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $VPS_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 51820/udp
    ufw --force enable
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=51820/udp
    firewall-cmd --reload
fi

# Start WireGuard
echo -e "${YELLOW}Starting WireGuard...${NC}"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Check status
if systemctl is-active --quiet wg-quick@wg0; then
    echo -e "${GREEN}✓ WireGuard started successfully!${NC}"
else
    echo -e "${RED}✗ Failed to start WireGuard${NC}"
    systemctl status wg-quick@wg0
    exit 1
fi

# Generate QR code for mobile
echo ""
echo -e "${YELLOW}Generating QR code for easy mobile setup...${NC}"
qrencode -t ansiutf8 < /etc/wireguard/client.conf

# Save client config to local directory
cp /etc/wireguard/client.conf ~/wireguard-client.conf

echo ""
echo "================================================"
echo -e "${GREEN}WireGuard VPN Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Server Configuration:"
echo "  - VPN Server IP: $VPS_IP:51820"
echo "  - VPN Internal Network: 10.13.13.0/24"
echo "  - Server VPN IP: 10.13.13.1"
echo "  - Client VPN IP: 10.13.13.2"
echo ""
echo "Client Configuration File:"
echo "  Location: /etc/wireguard/client.conf"
echo "  Also saved: ~/wireguard-client.conf"
echo ""
echo "Public Keys:"
echo "  Server: $SERVER_PUBLIC_KEY"
echo "  Client: $CLIENT_PUBLIC_KEY"
echo ""
echo "================================================"
echo "Next Steps:"
echo "================================================"
echo ""
echo "Option 1: Configure Windows PC as Gateway"
echo "  1. Download client.conf to your Windows PC"
echo "  2. Install WireGuard: https://www.wireguard.com/install/"
echo "  3. Import client.conf"
echo "  4. Connect VPN"
echo "  5. Share PC connection with Xbox via Ethernet"
echo ""
echo "Option 2: Configure Router (if supported)"
echo "  1. Check if router supports WireGuard"
echo "  2. Import client.conf to router"
echo "  3. All devices automatically use VPN"
echo ""
echo "Option 3: MikroTik Router"
echo "  See detailed guide in VPN_SETUP_GUIDE.md"
echo ""
echo "To download client config:"
echo "  scp root@$VPS_IP:/etc/wireguard/client.conf ."
echo ""
echo "================================================"


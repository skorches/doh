#!/bin/bash

# OpenVPN Server Setup (Alternative to WireGuard)
# Can run on TCP port 443 to bypass blocking

set -e

echo "================================================"
echo "OpenVPN Server Setup for Xbox Network"
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

# Get VPS info
VPS_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"
echo ""

# Ask for port configuration
echo "Choose OpenVPN port configuration:"
echo "1) Port 1194 UDP (standard, faster)"
echo "2) Port 443 TCP (looks like HTTPS, harder to block) - RECOMMENDED"
echo "3) Custom port"
echo ""
read -p "Select option (1-3): " port_choice

case $port_choice in
    1)
        VPN_PORT=1194
        VPN_PROTOCOL=udp
        echo "Using: 1194/UDP (standard)"
        ;;
    2)
        VPN_PORT=443
        VPN_PROTOCOL=tcp
        echo "Using: 443/TCP (HTTPS stealth mode)"
        ;;
    3)
        read -p "Enter port number: " VPN_PORT
        read -p "Protocol (tcp/udp): " VPN_PROTOCOL
        echo "Using: $VPN_PORT/$VPN_PROTOCOL"
        ;;
    *)
        echo "Invalid option, using 443/TCP"
        VPN_PORT=443
        VPN_PROTOCOL=tcp
        ;;
esac

# Stop conflicting services on port 443
if [ "$VPN_PORT" -eq 443 ]; then
    echo -e "${YELLOW}Port 443 selected. Stopping web servers...${NC}"
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi

# Install OpenVPN
echo -e "${YELLOW}Installing OpenVPN...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y openvpn easy-rsa iptables-persistent
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y openvpn easy-rsa iptables-services
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Setup Easy-RSA
echo -e "${YELLOW}Setting up certificates...${NC}"
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Configure vars
cat > vars << EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "NY"
set_var EASYRSA_REQ_CITY       "NewYork"
set_var EASYRSA_REQ_ORG        "XboxVPN"
set_var EASYRSA_REQ_EMAIL      "admin@xboxvpn.local"
set_var EASYRSA_REQ_OU         "XboxVPN"
set_var EASYRSA_KEY_SIZE       2048
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    3650
EOF

# Generate certificates
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa gen-dh
./easyrsa build-server-full server nopass
./easyrsa build-client-full client nopass
openvpn --genkey secret pki/ta.key

# Copy certificates
cp pki/ca.crt /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
cp pki/dh.pem /etc/openvpn/
cp pki/ta.key /etc/openvpn/

# Create server configuration
echo -e "${YELLOW}Creating OpenVPN server config...${NC}"

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

cat > /etc/openvpn/server.conf << EOF
# OpenVPN Server Configuration for Xbox Network
port $VPN_PORT
proto $VPN_PROTOCOL
dev tun

ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Push DNS to clients (our DoH server)
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 10.8.0.1"
push "dhcp-option DNS 8.8.8.8"

# Gaming optimizations
keepalive 10 120
cipher AES-128-CBC
auth SHA256
comp-lzo
user nobody
group nogroup
persist-key
persist-tun

status openvpn-status.log
log-append /var/log/openvpn.log
verb 3

# Performance tuning for gaming
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"
fast-io
EOF

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"

# iptables rules
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $INTERFACE -j MASQUERADE

# Save iptables
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
    iptables-save > /etc/iptables/rules.v4
fi

# Configure UFW if present
if command -v ufw >/dev/null 2>&1; then
    ufw allow $VPN_PORT/$VPN_PROTOCOL
fi

# Start OpenVPN
echo -e "${YELLOW}Starting OpenVPN server...${NC}"
systemctl enable openvpn@server
systemctl start openvpn@server

# Wait for service
sleep 3

# Check status
if systemctl is-active --quiet openvpn@server; then
    echo -e "${GREEN}✓ OpenVPN server started successfully!${NC}"
else
    echo -e "${RED}✗ Failed to start OpenVPN${NC}"
    systemctl status openvpn@server
    exit 1
fi

# Create client configuration
echo -e "${YELLOW}Creating client configuration...${NC}"

cat > ~/client.ovpn << EOF
client
dev tun
proto $VPN_PROTOCOL
remote $VPS_IP $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-128-CBC
auth SHA256
comp-lzo
verb 3

# Gaming optimizations
sndbuf 393216
rcvbuf 393216

<ca>
$(cat ~/openvpn-ca/pki/ca.crt)
</ca>

<cert>
$(cat ~/openvpn-ca/pki/issued/client.crt)
</cert>

<key>
$(cat ~/openvpn-ca/pki/private/client.key)
</key>

<tls-auth>
$(cat ~/openvpn-ca/pki/ta.key)
</tls-auth>
key-direction 1
EOF

# Copy client config to easy access location
cp ~/client.ovpn /root/xbox-client.ovpn

echo ""
echo "================================================"
echo -e "${GREEN}OpenVPN Server Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Server Configuration:"
echo "  - Protocol: $VPN_PROTOCOL"
echo "  - Port: $VPN_PORT"
echo "  - VPN Network: 10.8.0.0/24"
echo "  - Server VPN IP: 10.8.0.1"
echo ""
echo "Client Configuration File:"
echo "  Location: /root/xbox-client.ovpn"
echo "  Also: ~/client.ovpn"
echo ""
echo "================================================"
echo "Next Steps"
echo "================================================"
echo ""
echo "Download client config:"
echo "  scp root@$VPS_IP:/root/xbox-client.ovpn ."
echo ""
echo "Compatible Devices:"
echo "  - Windows/Mac/Linux: OpenVPN Connect"
echo "  - Android/iOS: OpenVPN Connect app"
echo "  - GL.iNet Routers: Built-in OpenVPN support"
echo "  - ASUS/MikroTik Routers: Native support"
echo "  - Raspberry Pi: openvpn package"
echo ""
echo "Why port $VPN_PORT/$VPN_PROTOCOL?"
if [ "$VPN_PORT" -eq 443 ] && [ "$VPN_PROTOCOL" == "tcp" ]; then
    echo "  ✓ Looks exactly like HTTPS traffic"
    echo "  ✓ Very hard for ISP to block"
    echo "  ✓ Works even with strict firewalls"
fi
echo ""
echo "Setup on GL.iNet Router:"
echo "  1. Access router: 192.168.8.1"
echo "  2. VPN → OpenVPN Client"
echo "  3. Upload: xbox-client.ovpn"
echo "  4. Connect"
echo "  5. Connect Xbox to router"
echo ""
echo "View logs:"
echo "  tail -f /var/log/openvpn.log"
echo ""
echo "Check status:"
echo "  systemctl status openvpn@server"
echo ""
echo "================================================"


#!/bin/bash

# DoH Server Deployment Script for Xbox Network Access
# This script sets up a DNS-over-HTTPS server on your VPS

set -e

echo "================================================"
echo "DoH Server Setup for Xbox Network"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run this script as root or with sudo${NC}"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Docker if not present
if ! command_exists docker; then
    echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}Docker installed successfully${NC}"
else
    echo -e "${GREEN}Docker is already installed${NC}"
fi

# Install Docker Compose if not present
if ! command_exists docker-compose; then
    echo -e "${YELLOW}Docker Compose not found. Installing...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose installed successfully${NC}"
else
    echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Get VPS IP address
VPS_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}Detected VPS IP: $VPS_IP${NC}"

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"

if command_exists ufw; then
    # UFW (Ubuntu/Debian)
    ufw allow 53/tcp
    ufw allow 53/udp
    ufw allow 8053/tcp
    ufw allow 5053/tcp
    ufw allow 5053/udp
    echo -e "${GREEN}UFW firewall rules added${NC}"
elif command_exists firewall-cmd; then
    # FirewallD (CentOS/RHEL)
    firewall-cmd --permanent --add-port=53/tcp
    firewall-cmd --permanent --add-port=53/udp
    firewall-cmd --permanent --add-port=8053/tcp
    firewall-cmd --permanent --add-port=5053/tcp
    firewall-cmd --permanent --add-port=5053/udp
    firewall-cmd --reload
    echo -e "${GREEN}FirewallD rules added${NC}"
else
    echo -e "${YELLOW}No firewall detected. Please manually open ports: 53, 5053, 8053${NC}"
fi

# Optimize system for DNS performance
echo -e "${YELLOW}Optimizing system for DNS performance...${NC}"

# Increase file descriptors
if ! grep -q "fs.file-max" /etc/sysctl.conf; then
    echo "fs.file-max = 65536" >> /etc/sysctl.conf
fi

# Network optimizations for low latency
cat >> /etc/sysctl.conf << EOF
# DNS/Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

sysctl -p
echo -e "${GREEN}System optimizations applied${NC}"

# Create necessary directories
mkdir -p coredns

# Pull Docker images
echo -e "${YELLOW}Pulling Docker images...${NC}"
docker-compose pull

# Start services
echo -e "${YELLOW}Starting DoH services...${NC}"
docker-compose up -d

# Wait for services to start
echo -e "${YELLOW}Waiting for services to initialize...${NC}"
sleep 5

# Check if services are running
if docker ps | grep -q "doh-server" && docker ps | grep -q "dns-proxy"; then
    echo -e "${GREEN}✓ Services started successfully!${NC}"
else
    echo -e "${RED}✗ Error: Services failed to start${NC}"
    echo "Checking logs..."
    docker-compose logs
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}DoH Server Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Your VPS DNS Server IP: $VPS_IP"
echo ""
echo "Available Services:"
echo "  - DNS Server (for Xbox):     $VPS_IP:53"
echo "  - DoH Endpoint:              https://$VPS_IP:8053/dns-query"
echo "  - Internal DoH Server:       $VPS_IP:5053"
echo ""
echo "Next Steps:"
echo "1. Configure your Xbox to use DNS: $VPS_IP"
echo "2. Test connectivity with: dig @$VPS_IP xbox.com"
echo "3. Monitor logs: docker-compose logs -f"
echo ""
echo "For detailed setup instructions, see README.md"
echo "================================================"


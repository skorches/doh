#!/bin/bash

# Setup Let's Encrypt SSL certificate for DoH server

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Let's Encrypt SSL Certificate Setup"
echo "================================================"
echo ""

INSTALL_DIR="/root/doh"
cd "$INSTALL_DIR"

# Check for docker-compose command
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    exit 1
fi

# Check if domain is already configured
if [ -f docker-compose.yml ]; then
    # Try to extract domain from nginx config
    DOMAIN_NAME=$(grep -h "server_name" nginx/conf.d/*.conf 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//' || echo "")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your domain name: " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        echo -e "${RED}Domain name is required!${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Found domain: $DOMAIN_NAME${NC}"
    read -p "Use this domain? (y/n): " REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your domain name: " DOMAIN_NAME
    fi
fi

echo ""
echo "Requirements:"
echo "  1. Domain DNS A record must point to this VPS IP"
echo "  2. Port 80 must be open (for verification)"
echo ""

read -p "Continue? (y/n): " REPLY
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Ask for email (required for Let's Encrypt)
echo ""
read -p "Enter your email for Let's Encrypt (required): " EMAIL
if [ -z "$EMAIL" ]; then
    echo -e "${RED}Email is required for Let's Encrypt!${NC}"
    exit 1
fi

# Install certbot if not installed
if ! command -v certbot &> /dev/null; then
    echo ""
    echo -e "${YELLOW}Installing certbot...${NC}"
    apt-get update -qq
    apt-get install -y certbot
fi

# Stop nginx temporarily (certbot needs port 80)
echo ""
echo -e "${YELLOW}Temporarily stopping Nginx...${NC}"
$DOCKER_COMPOSE_CMD stop doh-nginx 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

# Get certificate
echo ""
echo -e "${YELLOW}Getting Let's Encrypt certificate...${NC}"
certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL" || {
    echo -e "${RED}Failed to get certificate${NC}"
    echo "Make sure:"
    echo "  1. DNS A record for $DOMAIN_NAME points to this VPS"
    echo "  2. Port 80 is open in firewall"
    exit 1
}

# Copy certificate to project
echo ""
echo -e "${YELLOW}Copying certificate...${NC}"
mkdir -p ssl
cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ssl/selfsigned.crt
cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem ssl/selfsigned.key
chmod 644 ssl/selfsigned.crt
chmod 600 ssl/selfsigned.key

# Restart nginx
echo ""
echo -e "${YELLOW}Restarting services...${NC}"
$DOCKER_COMPOSE_CMD restart doh-nginx 2>/dev/null || true

echo ""
echo "================================================"
echo -e "${GREEN}✅ Let's Encrypt certificate installed!${NC}"
echo "================================================"
echo ""
echo "Certificate will auto-renew via certbot timer"
echo "Test: curl -I https://$DOMAIN_NAME/dns-query"
echo ""

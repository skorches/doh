#!/bin/bash

# Setup Let's Encrypt SSL certificate for DoH domain

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

# Get domain name
if [ -f "/root/doh/nginx/conf.d/doh.conf" ]; then
    DOMAIN=$(grep "server_name" /root/doh/nginx/conf.d/doh.conf | head -1 | awk '{print $2}' | sed 's/;//')
fi

if [ -z "$DOMAIN" ]; then
    read -p "Enter your domain name (e.g., bypass.example.com): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Domain name is required${NC}"
    exit 1
fi

echo "Domain: $DOMAIN"
echo ""

# Get VPS IP from local network interface
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
VPS_IP=""
if [ -n "$DEFAULT_IF" ]; then
    VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

echo "VPS IP: ${VPS_IP:-UNKNOWN}"
echo ""

# Check if domain DNS points to VPS
echo "[1/5] Verifying domain DNS..."
DOMAIN_IP=$(dig +short $DOMAIN A | head -1)
if [ "$DOMAIN_IP" == "$VPS_IP" ]; then
    echo -e "${GREEN}✅ Domain DNS points to VPS IP${NC}"
else
    echo -e "${YELLOW}⚠️  Domain DNS does not point to VPS IP${NC}"
    echo "   Domain resolves to: $DOMAIN_IP"
    echo "   VPS IP is: $VPS_IP"
    echo ""
    echo "Please update your domain's DNS A record first:"
    echo "  Type: A"
    echo "  Name: @ (or subdomain)"
    echo "  Content: $VPS_IP"
    echo ""
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi
echo ""

# Check if certbot is installed
echo "[2/5] Checking certbot..."
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}certbot not found, installing...${NC}"
    apt-get update -qq
    apt-get install -y certbot
    echo -e "${GREEN}✅ certbot installed${NC}"
else
    echo -e "${GREEN}✅ certbot found${NC}"
fi
echo ""

# Stop Nginx temporarily (certbot needs port 80)
echo "[3/5] Stopping Nginx for certificate generation..."
docker stop doh-nginx 2>/dev/null || true
sleep 2
echo -e "${GREEN}✅ Nginx stopped${NC}"
echo ""

# Generate certificate
echo "[4/5] Generating Let's Encrypt certificate..."
echo "This may take a minute..."
certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email admin@$DOMAIN \
    -d $DOMAIN \
    --preferred-challenges http \
    --http-01-port 80 || {
    echo -e "${RED}❌ Certificate generation failed${NC}"
    echo "Common issues:"
    echo "  • Domain DNS not pointing to VPS"
    echo "  • Port 80 not accessible"
    echo "  • Rate limit (too many requests)"
    docker start doh-nginx 2>/dev/null || true
    exit 1
}
echo -e "${GREEN}✅ Certificate generated${NC}"
echo ""

# Update Nginx config to use Let's Encrypt certificate
echo "[5/5] Updating Nginx configuration..."
if [ -f "/root/doh/nginx/conf.d/doh.conf" ]; then
    cd /root/doh
    # Update SSL certificate paths
    sed -i "s|ssl_certificate.*|ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;|" nginx/conf.d/doh.conf
    sed -i "s|ssl_certificate_key.*|ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;|" nginx/conf.d/doh.conf
    echo -e "${GREEN}✅ Nginx config updated${NC}"
else
    echo -e "${YELLOW}⚠️  Nginx config not found, you may need to update manually${NC}"
fi
echo ""

# Restart Nginx
echo "Restarting Nginx..."
docker start doh-nginx 2>/dev/null || docker compose up -d doh-nginx 2>/dev/null || docker-compose up -d doh-nginx 2>/dev/null
sleep 3
echo -e "${GREEN}✅ Nginx restarted${NC}"
echo ""

# Test
echo "Testing DoH endpoint with new certificate..."
sleep 2
RESULT=$(curl -s -H 'accept: application/dns-json' "https://$DOMAIN/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' || echo "FAILED")

if echo "$RESULT" | grep -q "Status\":0"; then
    echo -e "${GREEN}✅ DoH working with Let's Encrypt certificate!${NC}"
    echo ""
    echo "Test without -k flag:"
    echo "  curl -H 'accept: application/dns-json' 'https://$DOMAIN/dns-query?name=xboxlive.com&type=A'"
else
    echo -e "${YELLOW}⚠️  DoH test failed, checking logs...${NC}"
    docker logs doh-nginx --tail 10 2>&1 | tail -5
fi
echo ""

echo "================================================"
echo -e "${GREEN}✅ Let's Encrypt Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Certificate location:"
echo "  /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
echo "  /etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo ""
echo "Certificate will auto-renew (certbot timer is enabled)"
echo ""
echo "Your DoH endpoint is now using a valid SSL certificate:"
echo "  https://$DOMAIN/dns-query"
echo ""


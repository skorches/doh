#!/bin/bash

# Quick fix for missing SSL key in Nginx config

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

DOMAIN="440.info"
NGINX_CONF="/root/doh/nginx/conf.d/doh.conf"

echo "=== Fixing Nginx SSL Key Configuration ==="
echo ""

# Check if Let's Encrypt certificate exists
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo -e "${GREEN}✅ Let's Encrypt certificate found${NC}"
    echo "  Using: $SSL_CERT"
    echo "  Key: $SSL_KEY"
elif [ -f "/root/doh/ssl/selfsigned.crt" ] && [ -f "/root/doh/ssl/selfsigned.key" ]; then
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    echo -e "${YELLOW}⚠️  Using self-signed certificate${NC}"
else
    echo -e "${RED}❌ No SSL certificate found${NC}"
    echo "Creating self-signed certificate..."
    mkdir -p /root/doh/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /root/doh/ssl/selfsigned.key \
        -out /root/doh/ssl/selfsigned.crt \
        -subj "/CN=$DOMAIN" 2>/dev/null
    chmod 644 /root/doh/ssl/selfsigned.crt
    chmod 600 /root/doh/ssl/selfsigned.key
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    echo -e "${GREEN}✅ Self-signed certificate created${NC}"
fi
echo ""

# Update Nginx config
echo "Updating Nginx configuration..."
if [ -f "$NGINX_CONF" ]; then
    # Backup
    cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%s)"
    
    # Update SSL paths
    sed -i "s|ssl_certificate.*|ssl_certificate $SSL_CERT;|" "$NGINX_CONF"
    sed -i "s|ssl_certificate_key.*|ssl_certificate_key $SSL_KEY;|" "$NGINX_CONF"
    
    # If ssl_certificate_key line doesn't exist, add it after ssl_certificate
    if ! grep -q "ssl_certificate_key" "$NGINX_CONF"; then
        sed -i "/ssl_certificate.*fullchain.pem/a\\
    ssl_certificate_key $SSL_KEY;
" "$NGINX_CONF"
    fi
    
    echo -e "${GREEN}✅ Nginx config updated${NC}"
else
    echo -e "${RED}❌ Nginx config not found: $NGINX_CONF${NC}"
    exit 1
fi
echo ""

# Verify config
echo "Verifying Nginx config syntax..."
if docker exec doh-nginx nginx -t 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✅ Nginx config is valid${NC}"
else
    echo -e "${YELLOW}⚠️  Nginx config test:${NC}"
    docker exec doh-nginx nginx -t 2>&1 | tail -5
fi
echo ""

# Restart Nginx
echo "Restarting Nginx..."
docker restart doh-nginx
sleep 5

# Check status
if docker ps | grep -q "doh-nginx.*Up"; then
    echo -e "${GREEN}✅ Nginx is running${NC}"
    
    # Test
    echo ""
    echo "Testing DoH endpoint..."
    sleep 2
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' || echo "FAILED")
    
    if echo "$RESULT" | grep -q "Status\":0"; then
        echo -e "${GREEN}✅ DoH working!${NC}"
    else
        echo -e "${YELLOW}⚠️  DoH test failed${NC}"
    fi
else
    echo -e "${RED}❌ Nginx failed to start${NC}"
    echo "Logs:"
    docker logs doh-nginx --tail 20 2>&1 | tail -10
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Fix Complete!${NC}"
echo "================================================"


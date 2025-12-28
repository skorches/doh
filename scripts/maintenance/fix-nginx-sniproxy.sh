#!/bin/bash

# Fix Nginx crashing and SNIProxy domain configuration

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
echo "Fixing Nginx and SNIProxy Configuration"
echo "================================================"
echo ""

# Get domain from Nginx config or ask
DOMAIN=""
if [ -f "/root/doh/nginx/conf.d/doh.conf" ]; then
    DOMAIN=$(grep "server_name" /root/doh/nginx/conf.d/doh.conf | head -1 | awk '{print $2}' | sed 's/;//')
fi

if [ -z "$DOMAIN" ]; then
    read -p "Enter your domain name (e.g., 440.info): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Domain name is required${NC}"
    exit 1
fi

echo "Domain: $DOMAIN"
echo ""

# Step 1: Check Nginx logs
echo "[1/5] Checking Nginx logs for errors..."
echo "Recent Nginx errors:"
docker logs doh-nginx --tail 30 2>&1 | grep -iE "error|emerg|fatal" | tail -10 || echo "No errors found"
echo ""

# Step 2: Check if SSL certificates exist
echo "[2/5] Checking SSL certificates..."
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo -e "${GREEN}✅ Let's Encrypt certificate found${NC}"
    echo "  Certificate: $SSL_CERT"
    echo "  Key: $SSL_KEY"
elif [ -f "/root/doh/ssl/selfsigned.crt" ] && [ -f "/root/doh/ssl/selfsigned.key" ]; then
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    echo -e "${YELLOW}⚠️  Using self-signed certificate${NC}"
else
    echo -e "${YELLOW}⚠️  No SSL certificate found, creating self-signed...${NC}"
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

# Step 3: Fix Nginx config
echo "[3/5] Fixing Nginx configuration..."
mkdir -p /root/doh/nginx/conf.d

cat > /root/doh/nginx/conf.d/doh.conf << EOFNGINX
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    
    server_name $DOMAIN;
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Connection settings
    keepalive_timeout 65;
    client_max_body_size 10m;
    
    # Timeouts
    proxy_connect_timeout 10s;
    proxy_send_timeout 10s;
    proxy_read_timeout 10s;
    
    # DoH endpoint
    location /dns-query {
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # Root page
    location = / {
        return 200 "DNS over HTTPS (DoH) Server\n\nEndpoint: https://$DOMAIN/dns-query\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOFNGINX

echo -e "${GREEN}✅ Nginx config updated${NC}"
echo ""

# Step 4: Fix SNIProxy config
echo "[4/5] Fixing SNIProxy configuration..."
DOMAIN_ESCAPED=$(echo "$DOMAIN" | sed 's/\./\\./g')

# Check if domain is in SNIProxy config
if ! grep -q "$DOMAIN_ESCAPED" /etc/sniproxy.conf 2>/dev/null; then
    echo "Adding domain to SNIProxy config..."
    
    # Backup existing config
    cp /etc/sniproxy.conf /etc/sniproxy.conf.backup.$(date +%s) 2>/dev/null || true
    
    # Add domain to table (before the wildcard rules)
    sed -i "/table https_hosts {/a\\
    # DoH server - route to local nginx\\
    $DOMAIN_ESCAPED\\\$ 127.0.0.1:8443\\
" /etc/sniproxy.conf
    
    # Restart SNIProxy
    systemctl restart sniproxy
    sleep 2
    
    if systemctl is-active sniproxy >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SNIProxy config updated and restarted${NC}"
    else
        echo -e "${RED}❌ SNIProxy failed to start${NC}"
        echo "Restoring backup..."
        cp /etc/sniproxy.conf.backup.* /etc/sniproxy.conf 2>/dev/null || true
        systemctl restart sniproxy
    fi
else
    echo -e "${GREEN}✅ Domain already in SNIProxy config${NC}"
fi
echo ""

# Step 5: Restart Nginx
echo "[5/5] Restarting Nginx..."
docker restart doh-nginx
sleep 8

# Check if Nginx is running
NGINX_STATUS=$(docker inspect doh-nginx --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
if [ "$NGINX_STATUS" == "running" ]; then
    echo -e "${GREEN}✅ Nginx is running${NC}"
elif [ "$NGINX_STATUS" == "restarting" ]; then
    echo -e "${YELLOW}⚠️  Nginx is restarting, checking logs...${NC}"
    sleep 5
    docker logs doh-nginx --tail 30 2>&1 | grep -iE "error|emerg|fatal" | tail -10 || echo "No fatal errors found"
    NGINX_STATUS=$(docker inspect doh-nginx --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
    if [ "$NGINX_STATUS" == "running" ]; then
        echo -e "${GREEN}✅ Nginx is now running${NC}"
    else
        echo -e "${RED}❌ Nginx is still not running${NC}"
        echo "Full logs:"
        docker logs doh-nginx --tail 50 2>&1 | tail -20
        exit 1
    fi
else
    echo -e "${RED}❌ Nginx status: $NGINX_STATUS${NC}"
    echo "Checking logs..."
    docker logs doh-nginx --tail 50 2>&1 | tail -20
    exit 1
fi
echo ""

# Test
echo "Testing DoH endpoint..."
sleep 2
RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' || echo "FAILED")

if echo "$RESULT" | grep -q "Status\":0"; then
    echo -e "${GREEN}✅ DoH working on localhost:8443${NC}"
else
    echo -e "${YELLOW}⚠️  DoH test failed${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Fix Complete!${NC}"
echo "================================================"
echo ""
echo "Test DoH endpoint:"
echo "  curl -k -H 'accept: application/dns-json' 'https://$DOMAIN/dns-query?name=xboxlive.com&type=A'"
echo ""


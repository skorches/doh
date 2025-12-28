#!/bin/bash

# Fix HTTP 405 errors by allowing POST and OPTIONS methods for DoH

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

echo "================================================"
echo "Fixing DoH HTTP 405 Errors"
echo "================================================"
echo ""

# Get domain from Nginx config
DOMAIN=""
if [ -f "nginx/conf.d/doh.conf" ]; then
    DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf | head -1 | awk '{print $2}' | sed 's/;//')
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

# Get SSL certificate paths
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo -e "${GREEN}✅ Using Let's Encrypt certificate${NC}"
elif [ -f "ssl/selfsigned.crt" ] && [ -f "ssl/selfsigned.key" ]; then
    SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
    SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    echo -e "${YELLOW}⚠️  Using self-signed certificate${NC}"
else
    echo -e "${RED}❌ No SSL certificate found${NC}"
    exit 1
fi

echo ""
echo "Updating Nginx config to support GET, POST, and OPTIONS methods..."
mkdir -p nginx/conf.d

cat > nginx/conf.d/doh.conf << EOFNGINX
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
    
    # DoH endpoint - support GET, POST, and OPTIONS
    location /dns-query {
        # Allow all DoH methods (GET, POST, OPTIONS)
        limit_except GET POST OPTIONS {
            deny all;
        }
        
        # Handle OPTIONS (CORS preflight)
        if (\$request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Content-Type";
            add_header Access-Control-Max-Age 3600;
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
        
        # Proxy to DoH backend
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # CORS headers for DoH
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
    }
    
    # Root page
    location = / {
        return 200 "DNS over HTTPS (DoH) Server\n\nEndpoint: https://$DOMAIN/dns-query\n\nSupports: GET, POST, OPTIONS\n";
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

# Test Nginx config
echo "Testing Nginx configuration..."
if docker exec doh-nginx nginx -t 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✅ Nginx config is valid${NC}"
else
    echo -e "${RED}❌ Nginx config test failed${NC}"
    docker exec doh-nginx nginx -t 2>&1 | tail -5
    exit 1
fi
echo ""

# Restart Nginx
echo "Restarting Nginx..."
docker restart doh-nginx
sleep 5

# Test DoH with different methods
echo "Testing DoH endpoint with different methods..."
echo ""

# Test GET
echo "1. Testing GET method:"
GET_RESULT=$(curl -k -s -X GET -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>&1 | grep -o '"Status":[0-9]*' || echo "FAILED")
if echo "$GET_RESULT" | grep -q "Status\":0"; then
    echo -e "  ${GREEN}✅ GET method working${NC}"
else
    echo -e "  ${RED}❌ GET method failed${NC}"
fi

# Test POST
echo "2. Testing POST method:"
POST_DATA='{"name":"xboxlive.com","type":"A"}'
POST_RESULT=$(curl -k -s -X POST -H 'accept: application/dns-json' -H 'Content-Type: application/dns-json' -d "$POST_DATA" "https://localhost:8443/dns-query" 2>&1 | grep -o '"Status":[0-9]*' || echo "FAILED")
if echo "$POST_RESULT" | grep -q "Status\":0"; then
    echo -e "  ${GREEN}✅ POST method working${NC}"
else
    echo -e "  ${YELLOW}⚠️  POST method test: $POST_RESULT${NC}"
    echo "  (Some DoH backends may only support GET)"
fi

# Test OPTIONS
echo "3. Testing OPTIONS method (CORS):"
OPTIONS_RESULT=$(curl -k -s -X OPTIONS -H 'Origin: https://example.com' "https://localhost:8443/dns-query" 2>&1 | head -1)
if echo "$OPTIONS_RESULT" | grep -q "204\|200"; then
    echo -e "  ${GREEN}✅ OPTIONS method working${NC}"
else
    echo -e "  ${YELLOW}⚠️  OPTIONS method: $OPTIONS_RESULT${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Fix Complete!${NC}"
echo "================================================"
echo ""
echo "Nginx now supports:"
echo "  • GET method (standard DoH queries)"
echo "  • POST method (for routers that use POST)"
echo "  • OPTIONS method (CORS preflight)"
echo ""
echo "The HTTP 405 errors should now be resolved."
echo "Wait a few minutes for your router to retry the DoH connection."
echo ""


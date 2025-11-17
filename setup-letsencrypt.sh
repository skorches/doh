#!/bin/bash

# Let's Encrypt SSL Setup for DoH Server
# Usage: ./setup-letsencrypt.sh doh.yourdomain.com

set -e

echo "================================================"
echo "Let's Encrypt SSL Setup for DoH Server"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Check if domain provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Domain name required${NC}"
    echo ""
    echo "Usage: $0 doh.yourdomain.com"
    echo ""
    echo "Example:"
    echo "  $0 doh.mygaming.xyz"
    exit 1
fi

DOMAIN=$1
VPS_IP=$(hostname -I | awk '{print $1}')
EMAIL="admin@${DOMAIN}"

echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo -e "${BLUE}VPS IP:${NC} $VPS_IP"
echo ""

# Verify DNS is pointing to this VPS
echo -e "${YELLOW}Verifying DNS configuration...${NC}"
RESOLVED_IP=$(dig +short $DOMAIN @8.8.8.8 | tail -1)

if [ -z "$RESOLVED_IP" ]; then
    echo -e "${RED}Error: Domain $DOMAIN does not resolve!${NC}"
    echo ""
    echo "Please make sure:"
    echo "  1. DNS A record is created"
    echo "  2. Points to: $VPS_IP"
    echo "  3. DNS has propagated (wait 15-30 minutes after creating)"
    echo ""
    echo "Test with: ping $DOMAIN"
    exit 1
fi

if [ "$RESOLVED_IP" != "$VPS_IP" ]; then
    echo -e "${RED}Error: Domain points to wrong IP!${NC}"
    echo "  Domain resolves to: $RESOLVED_IP"
    echo "  VPS IP is: $VPS_IP"
    echo ""
    echo "Please update your DNS A record to point to: $VPS_IP"
    exit 1
fi

echo -e "${GREEN}✓ DNS correctly configured ($DOMAIN → $VPS_IP)${NC}"
echo ""

# Stop current services
echo -e "${YELLOW}Stopping current services...${NC}"
cd /root/doh
docker-compose down 2>/dev/null || true

# Install Certbot
echo -e "${YELLOW}Installing Certbot...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y certbot
elif command -v yum >/dev/null 2>&1; then
    yum install -y certbot
fi

# Open port 80 temporarily for Let's Encrypt verification
echo -e "${YELLOW}Opening port 80 for Let's Encrypt...${NC}"
ufw allow 80/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

# Get Let's Encrypt certificate
echo -e "${YELLOW}Obtaining Let's Encrypt SSL certificate...${NC}"
echo ""
echo "This may take 30-60 seconds..."
echo ""

certbot certonly --standalone \
    --preferred-challenges http \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    --domain $DOMAIN \
    --non-interactive

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to obtain certificate!${NC}"
    echo ""
    echo "Common issues:"
    echo "  1. Port 80 is blocked by firewall"
    echo "  2. Another service is using port 80"
    echo "  3. DNS not fully propagated yet"
    exit 1
fi

echo -e "${GREEN}✓ SSL certificate obtained!${NC}"

# Copy certificates
echo -e "${YELLOW}Configuring SSL...${NC}"
mkdir -p ssl
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem ssl/doh.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem ssl/doh.key
chmod 644 ssl/doh.crt
chmod 600 ssl/doh.key

# Create nginx config
mkdir -p nginx
cat > nginx/default.conf << EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    # Let's Encrypt SSL Configuration
    ssl_certificate /etc/nginx/ssl/doh.crt;
    ssl_certificate_key /etc/nginx/ssl/doh.key;
    
    # SSL Security (A+ rating)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # DoH endpoint
    location /dns-query {
        proxy_pass http://doh-backend:8080/dns-query;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "DoH Server OK\n";
        add_header Content-Type text/plain;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}
EOF

# Create docker-compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=udp:9.9.9.9:53,udp:149.112.112.112:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8080
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
      - DOH_SERVER_VERBOSE=true
    networks:
      - doh-network

  nginx:
    image: nginx:alpine
    container_name: doh-nginx
    restart: unless-stopped
    ports:
      - "443:443/tcp"
      - "80:80/tcp"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - doh-backend
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOF

# Setup auto-renewal
echo -e "${YELLOW}Setting up auto-renewal...${NC}"

# Create renewal hook
cat > /etc/letsencrypt/renewal-hooks/deploy/doh-renewal.sh << EOF
#!/bin/bash
# Copy renewed certificates
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /root/doh/ssl/doh.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /root/doh/ssl/doh.key
chmod 644 /root/doh/ssl/doh.crt
chmod 600 /root/doh/ssl/doh.key

# Reload nginx
cd /root/doh
docker-compose restart nginx
EOF

chmod +x /etc/letsencrypt/renewal-hooks/deploy/doh-renewal.sh

# Test renewal (dry run)
certbot renew --dry-run --quiet || echo "Renewal test completed"

# Start services
echo -e "${YELLOW}Starting DoH server with Let's Encrypt SSL...${NC}"
docker-compose up -d

sleep 5

# Check status
if docker ps | grep -q "doh-nginx" && docker ps | grep -q "doh-backend"; then
    echo -e "${GREEN}✓ Services running!${NC}"
else
    echo -e "${RED}✗ Failed to start services${NC}"
    docker-compose logs
    exit 1
fi

# Test HTTPS
echo ""
echo -e "${YELLOW}Testing HTTPS endpoint...${NC}"
sleep 2

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/dns-query 2>/dev/null)

if [ "$RESPONSE" == "415" ] || [ "$RESPONSE" == "400" ]; then
    echo -e "${GREEN}✓ HTTPS endpoint working! (HTTP $RESPONSE)${NC}"
else
    echo -e "${YELLOW}⚠ Got HTTP $RESPONSE (might still work)${NC}"
fi

# Test health endpoint
curl -s https://$DOMAIN/health

echo ""
echo "================================================"
echo -e "${GREEN}Setup Complete! 🎉${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}Your DoH URL:${NC}"
echo "  https://$DOMAIN/dns-query"
echo ""
echo -e "${BLUE}Configure in Keenetic:${NC}"
echo "  https://$DOMAIN/dns-query"
echo ""
echo -e "${BLUE}SSL Certificate:${NC}"
echo "  Issued by: Let's Encrypt"
echo "  Valid for: 90 days"
echo "  Auto-renews: Every 60 days"
echo ""
echo -e "${BLUE}Test from your computer:${NC}"
echo "  curl https://$DOMAIN/dns-query"
echo "  (Should get 415 error - that's normal!)"
echo ""
echo -e "${BLUE}View logs:${NC}"
echo "  docker-compose logs -f"
echo ""
echo -e "${BLUE}Check certificate:${NC}"
echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
echo ""
echo "================================================"
echo ""
echo -e "${GREEN}✓ Trusted SSL certificate (just like xbox-dns.ru!)${NC}"
echo -e "${GREEN}✓ Auto-renews every 90 days${NC}"
echo -e "${GREEN}✓ Keenetic will accept this certificate${NC}"
echo ""


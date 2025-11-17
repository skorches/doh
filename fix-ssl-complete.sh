#!/bin/bash

# Complete SSL fix for Nginx + Cloudflare

set -e

echo "================================================"
echo "Fixing SSL Configuration"
echo "================================================"
echo ""

cd /root/doh

echo "[1/5] Creating self-signed SSL certificate..."
mkdir -p ssl

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/selfsigned.key \
  -out ssl/selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Org/CN=bypass.440.info" 2>/dev/null

echo "✅ SSL certificate created"

echo ""
echo "[2/5] Creating proper Nginx configuration with SSL..."

mkdir -p nginx/conf.d

cat > nginx/conf.d/doh.conf << 'EOF'
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name bypass.440.info;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # DoH endpoint
    location /dns-query {
        proxy_pass http://doh-backend:8053;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts for Xbox
        proxy_connect_timeout 10s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}

# HTTP redirect (port 80)
server {
    listen 80;
    listen [::]:80;
    server_name bypass.440.info;
    
    location / {
        return 301 https://$host$request_uri;
    }
}
EOF

echo "✅ Nginx config created"

echo ""
echo "[3/5] Updating docker-compose.yml to mount SSL..."

# Remove old SSL mount if exists
sed -i '/ssl:/d' docker-compose.yml

# Add SSL mount after letsencrypt line
sed -i '/letsencrypt:/a\      - ./ssl:/etc/nginx/ssl:ro' docker-compose.yml

echo "✅ docker-compose.yml updated"

echo ""
echo "[4/5] Restarting Nginx..."
docker-compose restart doh-nginx

sleep 5

echo ""
echo "[5/5] Testing configuration..."

# Test local HTTPS
echo "Testing local HTTPS..."
curl -k -s https://localhost:8443/health && echo "✅ Nginx HTTPS working" || echo "❌ Nginx HTTPS failed"

# Test DoH locally
echo ""
echo "Testing DoH locally..."
curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=google.com&type=A' | grep -q '"Status":0' && echo "✅ DoH working" || echo "❌ DoH failed"

# Test through HAProxy
echo ""
echo "Testing through HAProxy..."
curl -k -s -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A' | grep -q '"Status":0' && echo "✅ HAProxy → Nginx working" || echo "❌ HAProxy failed"

echo ""
echo "================================================"
echo "✅ SSL Configuration Complete!"
echo "================================================"
echo ""
echo "IMPORTANT: Cloudflare SSL Settings"
echo ""
echo "Go to Cloudflare Dashboard:"
echo "  1. Select your domain (440.dev)"
echo "  2. Go to SSL/TLS → Overview"
echo "  3. Set encryption mode to: Full (not Full Strict)"
echo ""
echo "Or use this command to test bypass Cloudflare:"
echo "  curl -k --resolve bypass.440.info:443:YOUR_VPS_IP https://bypass.440.info/dns-query?name=google.com"
echo ""
echo "Test from home in 30 seconds:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "================================================"


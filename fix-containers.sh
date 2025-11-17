#!/bin/bash

# Fix container configuration errors

set -e

echo "================================================"
echo "Fixing Container Configuration"
echo "================================================"
echo ""

cd /root/doh

VPS_IP=$(curl -s ifconfig.me)

echo "Stopping containers..."
docker-compose down

echo ""
echo "Fixing docker-compose.yml..."

cat > docker-compose.yml << 'EOFDOCKER'
version: '3.8'

services:
  # Nginx - HTTPS/SSL termination
  doh-nginx:
    image: nginx:alpine
    container_name: doh-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "8443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./letsencrypt:/etc/letsencrypt:ro
    networks:
      - doh-network
    depends_on:
      - doh-backend

  # DoH Backend - Fixed upstream format
  doh-backend:
    image: satishweb/doh-server:latest
    container_name: doh-backend
    restart: unless-stopped
    environment:
      - UPSTREAM_DNS_SERVER=udp:coredns-smartdns:53
      - DOH_HTTP_PREFIX=/dns-query
      - DOH_SERVER_LISTEN=:8053
      - DOH_SERVER_TIMEOUT=10
      - DOH_SERVER_TRIES=3
    expose:
      - "8053"
    networks:
      - doh-network
    depends_on:
      - coredns-smartdns

  # CoreDNS Smart DNS - Fixed forward
  coredns-smartdns:
    image: coredns/coredns:latest
    container_name: coredns-smartdns
    restart: unless-stopped
    command: -conf /etc/coredns/Corefile
    volumes:
      - ./coredns/Corefile:/etc/coredns/Corefile:ro
      - ./coredns/xbox-hosts:/etc/coredns/xbox-hosts:ro
    expose:
      - "53"
    networks:
      - doh-network

  # Cloudflared - Upstream DoH
  doh-upstream:
    image: cloudflare/cloudflared:latest
    container_name: doh-upstream
    restart: unless-stopped
    command: proxy-dns
    environment:
      - TUNNEL_DNS_UPSTREAM=https://1.1.1.1/dns-query,https://1.0.0.1/dns-query
      - TUNNEL_DNS_ADDRESS=0.0.0.0
      - TUNNEL_DNS_PORT=5053
    expose:
      - "5053"
    networks:
      - doh-network

networks:
  doh-network:
    driver: bridge
EOFDOCKER

echo ""
echo "Fixing CoreDNS Corefile..."

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to Cloudflare (standard DNS, not DoH)
    forward . 1.1.1.1 1.0.0.1
    
    # Cache DNS responses
    cache 300
    
    # Log errors only
    errors
}
EOFCORE

echo ""
echo "Verifying xbox-hosts file..."
if [ ! -f coredns/xbox-hosts ] || ! grep -q "$VPS_IP" coredns/xbox-hosts; then
    echo "Recreating xbox-hosts..."
    cat > coredns/xbox-hosts << EOFHOSTS
# Xbox Live domains
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP catalog.gamepass.com
$VPS_IP login.live.com
$VPS_IP arc.msn.com
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com
$VPS_IP fs.microsoft.com
$VPS_IP client.wns.windows.com
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# Discord domains
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP voice.discord.gg
EOFHOSTS
fi

echo ""
echo "Starting containers..."
docker-compose up -d

echo ""
echo "Waiting for containers..."
sleep 15

echo ""
echo "Checking container status..."
docker-compose ps

echo ""
echo "Checking for errors..."
docker-compose logs --tail=20 doh-backend coredns-smartdns

echo ""
echo "Testing DoH..."
sleep 5
curl -s http://localhost:8053/dns-query?name=google.com\&type=A | head -5

echo ""
echo "================================================"
echo "✅ Containers fixed and restarted!"
echo "================================================"
echo ""
echo "Test from home:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""


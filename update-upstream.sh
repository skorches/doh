#!/bin/bash

# Script to change upstream DNS servers for better performance

echo "================================================"
echo "DoH Upstream DNS Configuration"
echo "================================================"
echo ""

echo "Choose your preferred upstream DNS provider:"
echo ""
echo "⚠️  For Russia: Avoid Cloudflare/Google if blocked!"
echo ""
echo "1) Quad9 (Switzerland) - RECOMMENDED for Russia"
echo "2) OpenDNS (Cisco) - Good alternative"
echo "3) CleanBrowsing (USA) - Family-safe"
echo "4) AdGuard Unfiltered (Cyprus) - Privacy-focused"
echo "5) DNS.SB (Germany) - No logs"
echo "6) Cloudflare (1.1.1.1) - May be blocked in Russia"
echo "7) Google (8.8.8.8) - May be blocked in Russia"
echo "8) Custom - Enter your own DNS servers"
echo ""

read -p "Select option (1-8): " choice

case $choice in
    1)
        UPSTREAM="https://dns.quad9.net/dns-query,https://dns9.quad9.net/dns-query"
        echo "Selected: Quad9 DNS (Switzerland)"
        ;;
    2)
        UPSTREAM="https://doh.opendns.com/dns-query"
        echo "Selected: OpenDNS (Cisco)"
        ;;
    3)
        UPSTREAM="https://doh.cleanbrowsing.org/doh/security-filter/"
        echo "Selected: CleanBrowsing"
        ;;
    4)
        UPSTREAM="https://dns-unfiltered.adguard.com/dns-query"
        echo "Selected: AdGuard Unfiltered"
        ;;
    5)
        UPSTREAM="https://doh.dns.sb/dns-query"
        echo "Selected: DNS.SB (Germany)"
        ;;
    6)
        UPSTREAM="https://1.1.1.1/dns-query,https://1.0.0.1/dns-query"
        echo "Selected: Cloudflare DNS (may be blocked in Russia)"
        ;;
    7)
        UPSTREAM="https://8.8.8.8/dns-query,https://8.8.4.4/dns-query"
        echo "Selected: Google DNS (may be blocked in Russia)"
        ;;
    8)
        read -p "Enter upstream DoH URLs (comma-separated): " UPSTREAM
        echo "Custom upstream: $UPSTREAM"
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

# Update docker-compose.yml
echo ""
echo "Updating configuration..."

# Create backup
cp docker-compose.yml docker-compose.yml.backup

# Update the TUNNEL_DNS_UPSTREAM line
sed -i "s|TUNNEL_DNS_UPSTREAM=.*|TUNNEL_DNS_UPSTREAM=$UPSTREAM|g" docker-compose.yml

# Restart services
echo "Restarting services..."
docker-compose down
docker-compose up -d

echo ""
echo "✓ Configuration updated successfully!"
echo "Testing new configuration..."
sleep 3

# Test DNS
./test-dns.sh localhost

echo ""
echo "If you need to revert, backup is saved as: docker-compose.yml.backup"


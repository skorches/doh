#!/bin/bash

# Keenetic DoH Diagnostic Script
# Run this while testing Keenetic

echo "================================================"
echo "Keenetic DoH Diagnostic Monitor"
echo "================================================"
echo ""
echo "This will monitor for incoming DoH queries"
echo "Try nslookup from your computer now..."
echo ""
echo "Press Ctrl+C to stop"
echo ""
echo "================================================"

cd /root/doh

# Monitor logs and highlight DNS queries
docker-compose logs -f --tail=0 | grep --line-buffered -E "dns-query\?name=|GET /dns-query"


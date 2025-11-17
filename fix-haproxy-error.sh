#!/bin/bash

# Fix HAProxy startup error

echo "================================================"
echo "Checking HAProxy Error"
echo "================================================"
echo ""

# Check HAProxy config syntax
echo "Testing HAProxy configuration..."
haproxy -c -f /etc/haproxy/haproxy.cfg

echo ""
echo "================================================"
echo "HAProxy Error Logs:"
echo "================================================"
journalctl -xeu haproxy.service -n 50 --no-pager

echo ""
echo "================================================"
echo "Common Issues:"
echo "================================================"
echo ""
echo "1. Port 443 already in use (by Nginx DoH)"
echo "2. Port 80 already in use"
echo "3. Config syntax error"
echo ""
echo "Checking ports..."
echo ""
netstat -tlnp | grep -E ':(443|80|8404|3074|3544)\s'


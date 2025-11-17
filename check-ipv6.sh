#!/bin/bash

echo "=== Checking VPS IPv6 Support ==="
echo ""

# Check if VPS has IPv6
if ip -6 addr | grep -q "inet6.*global"; then
    echo "✅ VPS has IPv6 address:"
    ip -6 addr | grep "inet6.*global"
else
    echo "❌ VPS does not have IPv6"
fi

echo ""
echo "=== Test if your PC has IPv6 ==="
echo "Run this on your PC (without VPN):"
echo "  curl -6 https://ifconfig.co"
echo ""
echo "If you get an IPv6 address, we can use IPv6 to bypass ISP blocks!"


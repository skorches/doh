#!/bin/bash

# Quick script to copy Smart DNS files to VPS

echo "================================================"
echo "Copying Smart DNS files to VPS..."
echo "================================================"
echo ""

VPS_IP="91.235.234.92"

echo "Copying scripts..."
scp setup-xbox-proxy.sh \
    integrate-coredns-smartdns.sh \
    test-smartdns.sh \
    add-discord-support.sh \
    SMART_DNS_SETUP.md \
    SMART_DNS_QUICKSTART.txt \
    root@$VPS_IP:/root/doh/

if [ $? -eq 0 ]; then
    echo ""
    echo "================================================"
    echo "✅ Files copied successfully!"
    echo "================================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. SSH to VPS:"
    echo "   ssh root@$VPS_IP"
    echo ""
    echo "2. Run setup:"
    echo "   cd /root/doh"
    echo "   ./setup-xbox-proxy.sh"
    echo "   ./integrate-coredns-smartdns.sh"
    echo "   ./test-smartdns.sh"
    echo ""
    echo "3. Read the guide:"
    echo "   cat SMART_DNS_QUICKSTART.txt"
    echo ""
else
    echo ""
    echo "❌ Copy failed!"
    echo "Try manually:"
    echo "  scp *.sh *.md *.txt root@$VPS_IP:/root/doh/"
fi


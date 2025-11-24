#!/bin/bash

# Note: SNIProxy doesn't support timeout settings
# This script explains the limitation and suggests alternatives

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "SNIProxy Timeout Information"
echo "================================================"
echo ""

SNIPROXY_CONF="/etc/sniproxy.conf"

if [ ! -f "$SNIPROXY_CONF" ]; then
    echo -e "${RED}❌ SNIProxy config not found: $SNIPROXY_CONF${NC}"
    exit 1
fi

echo -e "${YELLOW}IMPORTANT: SNIProxy doesn't support timeout directives${NC}"
echo ""
echo "SNIProxy is a simple SNI-based proxy that doesn't have"
echo "configurable timeout settings. Timeouts are handled by"
echo "the OS TCP stack (typically 60-120 seconds)."
echo ""

# Check current config
echo -e "${BLUE}Current SNIProxy config:${NC}"
echo "----------------------------------------"
head -20 "$SNIPROXY_CONF"
echo ""

# Show connection durations from logs
if [ -f /var/log/sniproxy/https_access.log ]; then
    echo -e "${BLUE}Recent connection durations from logs:${NC}"
    tail -10 /var/log/sniproxy/https_access.log | grep -oE "[0-9]+\.[0-9]+ seconds" | tail -5 || echo "No duration data"
    echo ""
    
    LONG_CONNECTIONS=$(tail -50 /var/log/sniproxy/https_access.log | grep -oE "[0-9]+\.[0-9]+ seconds" | awk -F. '{if ($1 > 60) print $0}' | wc -l)
    if [ "$LONG_CONNECTIONS" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found $LONG_CONNECTIONS connections taking > 60 seconds${NC}"
        echo "This suggests Xbox is hanging connections."
    fi
fi

echo ""
echo "================================================"
echo "Solutions for Long Timeouts"
echo "================================================"
echo ""
echo "Since SNIProxy doesn't support timeout settings,"
echo "here are alternative solutions:"
echo ""
echo "1. REDUCE OS TCP TIMEOUTS (System-level)"
echo "   Edit /etc/sysctl.conf and add:"
echo "   net.ipv4.tcp_fin_timeout = 30"
echo "   net.ipv4.tcp_keepalive_time = 30"
echo "   Then run: sysctl -p"
echo ""
echo "2. TRY NON-RUSSIAN VPS (Recommended)"
echo "   Xbox might be blocking Russian IPs."
echo "   Deploy on: Germany, Netherlands, or US VPS."
echo ""
echo "3. USE NGINX INSTEAD OF SNIPROXY"
echo "   Nginx has better timeout control."
echo "   But requires more configuration."
echo ""
echo "4. CHECK IF XBOX IS BLOCKING"
echo "   The 6-8 minute timeouts suggest Xbox"
echo "   is detecting proxy and silently dropping."
echo ""

read -p "Would you like to reduce OS TCP timeouts? (y/n): " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Reducing OS TCP timeouts...${NC}"
    
    # Backup sysctl.conf
    if [ -f /etc/sysctl.conf ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Add timeout settings
    if ! grep -q "tcp_fin_timeout" /etc/sysctl.conf 2>/dev/null; then
        echo "" >> /etc/sysctl.conf
        echo "# Reduce TCP timeouts for faster failure" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_keepalive_time = 30" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_keepalive_probes = 3" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_keepalive_intvl = 10" >> /etc/sysctl.conf
        echo -e "${GREEN}✅ Added TCP timeout settings to /etc/sysctl.conf${NC}"
    else
        echo -e "${YELLOW}⚠ TCP timeout settings already exist${NC}"
    fi
    
    # Apply immediately
    sysctl -w net.ipv4.tcp_fin_timeout=30
    sysctl -w net.ipv4.tcp_keepalive_time=30
    sysctl -w net.ipv4.tcp_keepalive_probes=3
    sysctl -w net.ipv4.tcp_keepalive_intvl=10
    
    echo -e "${GREEN}✅ TCP timeouts reduced (30 seconds)${NC}"
    echo ""
    echo "Note: These settings will persist after reboot."
    echo "To revert, edit /etc/sysctl.conf and run: sysctl -p"
else
    echo ""
    echo -e "${YELLOW}Skipping TCP timeout changes${NC}"
fi

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""
echo "SNIProxy doesn't support timeout configuration."
echo "The 6-8 minute timeouts are likely because:"
echo "  • Xbox is blocking Russian VPS IPs"
echo "  • Xbox detects proxy and silently drops connections"
echo ""
echo "RECOMMENDED SOLUTION:"
echo "  Deploy on a non-Russian VPS (Germany, Netherlands, US)"
echo "  and run install.sh on the new VPS."
echo ""

#!/bin/bash

# Diagnose VPS network connectivity issues

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "VPS Network Connectivity Diagnosis"
echo "================================================"
echo ""

# 1. Check network interface
echo -e "${YELLOW}[1/6] Network Interface Status${NC}"
echo ""
ip link show | grep -E "^[0-9]+:|state" | head -10
echo ""

# 2. Check routing
echo -e "${YELLOW}[2/6] Routing Table${NC}"
echo ""
ip route | head -5
echo ""

# 3. Test connectivity to multiple hosts
echo -e "${YELLOW}[3/6] Connectivity Tests (10 attempts each)${NC}"
echo ""

test_connectivity() {
    local host=$1
    local name=$2
    local success=0
    local failed=0
    
    for i in {1..10}; do
        if timeout 2 ping -c 1 -W 1 "$host" > /dev/null 2>&1; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        sleep 0.5
    done
    
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}✅ $name: $success/10 successful${NC}"
    elif [ "$success" -gt 5 ]; then
        echo -e "${YELLOW}⚠ $name: $success/10 successful, $failed/10 failed (intermittent)${NC}"
    else
        echo -e "${RED}❌ $name: $success/10 successful, $failed/10 failed (unstable)${NC}"
    fi
}

test_connectivity "1.1.1.1" "Cloudflare DNS"
test_connectivity "8.8.8.8" "Google DNS"
test_connectivity "google.com" "Google.com"

# 4. Check packet loss
echo ""
echo -e "${YELLOW}[4/6] Packet Loss Test (20 pings)${NC}"
echo ""
ping -c 20 -i 0.5 1.1.1.1 2>&1 | tail -3

# 5. Check DNS resolution stability
echo ""
echo -e "${YELLOW}[5/6] DNS Resolution Stability (10 attempts)${NC}"
echo ""

DNS_SUCCESS=0
DNS_FAILED=0

for i in {1..10}; do
    if timeout 2 dig @1.1.1.1 google.com +short > /dev/null 2>&1; then
        DNS_SUCCESS=$((DNS_SUCCESS + 1))
    else
        DNS_FAILED=$((DNS_FAILED + 1))
    fi
    sleep 0.5
done

if [ "$DNS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✅ DNS: $DNS_SUCCESS/10 successful${NC}"
elif [ "$DNS_SUCCESS" -gt 5 ]; then
    echo -e "${YELLOW}⚠ DNS: $DNS_SUCCESS/10 successful, $DNS_FAILED/10 failed (intermittent)${NC}"
else
    echo -e "${RED}❌ DNS: $DNS_SUCCESS/10 successful, $DNS_FAILED/10 failed (unstable)${NC}"
fi

# 6. Check system resources
echo ""
echo -e "${YELLOW}[6/6] System Resources${NC}"
echo ""
echo "CPU Load:"
uptime | awk -F'load average:' '{print $2}'
echo ""
echo "Memory:"
free -h | grep -E "Mem|Swap"
echo ""
echo "Network Interface Statistics:"
ip -s link show | grep -A 5 -E "^[0-9]+:.*UP" | head -10

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ "$DNS_FAILED" -gt 5 ] || [ "$failed" -gt 5 ]; then
    echo -e "${RED}❌ Network connectivity is unstable${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. VPS provider network issues"
    echo "  2. DDoS protection/throttling"
    echo "  3. Network interface problems"
    echo "  4. Routing issues"
    echo "  5. ISP/VPS provider maintenance"
    echo ""
    echo "Recommendations:"
    echo "  • Contact VPS provider support"
    echo "  • Check VPS provider status page"
    echo "  • Try restarting network: systemctl restart networking"
    echo "  • Check if there are any firewall/DDoS rules"
    echo "  • Consider using the DNS proxy (DoH) setup to bypass UDP DNS issues"
else
    echo -e "${GREEN}✅ Network appears stable${NC}"
    echo ""
    echo "If you're still experiencing issues, it might be:"
    echo "  • Specific to certain destinations"
    echo "  • Time-based (peak hours)"
    echo "  • Related to specific protocols (UDP vs TCP)"
fi

echo ""


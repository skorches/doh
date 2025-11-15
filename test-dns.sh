#!/bin/bash

# DNS Testing Script for Xbox Network Connectivity

echo "================================================"
echo "Testing DoH Server & Xbox Network Connectivity"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VPS_IP=${1:-"127.0.0.1"}

# Function to test DNS
test_dns() {
    local domain=$1
    echo -e "${YELLOW}Testing: $domain${NC}"
    
    if command -v dig >/dev/null 2>&1; then
        result=$(dig +short @$VPS_IP $domain | head -n1)
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓ Success: $result${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to resolve${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}dig not found, using nslookup${NC}"
        nslookup $domain $VPS_IP
    fi
}

# Test basic connectivity
echo "1. Testing basic DNS resolution..."
test_dns "google.com"
echo ""

# Test Xbox Live domains
echo "2. Testing Xbox Live domains..."
xbox_domains=(
    "xbox.com"
    "xboxlive.com"
    "live.com"
    "gfx.ms"
    "xboxab.com"
    "xboxservices.com"
    "clientconfig.passport.net"
    "login.live.com"
)

success_count=0
total_tests=${#xbox_domains[@]}

for domain in "${xbox_domains[@]}"; do
    if test_dns "$domain"; then
        ((success_count++))
    fi
    echo ""
done

# Test latency
echo "3. Testing DNS latency (10 queries)..."
if command -v dig >/dev/null 2>&1; then
    total_time=0
    for i in {1..10}; do
        query_time=$(dig @$VPS_IP xbox.com | grep "Query time:" | awk '{print $4}')
        if [ -n "$query_time" ]; then
            total_time=$((total_time + query_time))
            echo "Query $i: ${query_time}ms"
        fi
    done
    avg_time=$((total_time / 10))
    echo -e "${GREEN}Average query time: ${avg_time}ms${NC}"
    
    if [ $avg_time -lt 50 ]; then
        echo -e "${GREEN}✓ Excellent latency for gaming${NC}"
    elif [ $avg_time -lt 100 ]; then
        echo -e "${YELLOW}⚠ Acceptable latency${NC}"
    else
        echo -e "${RED}⚠ High latency - consider choosing a closer VPS${NC}"
    fi
else
    echo -e "${YELLOW}dig not found, skipping latency test${NC}"
fi

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "Successful resolutions: $success_count/$total_tests"

if [ $success_count -eq $total_tests ]; then
    echo -e "${GREEN}✓ All tests passed! Your DoH server is working correctly.${NC}"
    echo ""
    echo "Configure your Xbox with DNS: $VPS_IP"
else
    echo -e "${RED}⚠ Some tests failed. Check the logs:${NC}"
    echo "  docker-compose logs -f"
fi
echo "================================================"


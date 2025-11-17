#!/bin/bash

# Capture Xbox network traffic to identify all domains it uses

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Xbox Network Traffic Capture"
echo "================================================"
echo ""
echo "This will capture:"
echo "  1. DNS queries from Xbox (via CoreDNS logs)"
echo "  2. Network connections to your VPS"
echo "  3. SNI proxy connections (what domains Xbox connects to)"
echo ""
echo "Instructions:"
echo "  1. Start this script"
echo "  2. On Xbox: Test network connection, open games, try multiplayer"
echo "  3. Let it run for 5-10 minutes while you use Xbox"
echo "  4. Press Ctrl+C to stop"
echo ""
echo "================================================"
echo ""

cd /root/doh

# Create output directory
OUTPUT_DIR="/root/doh/xbox-capture-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo -e "${YELLOW}Output directory: $OUTPUT_DIR${NC}"
echo ""

# Capture 1: DNS queries from CoreDNS
echo -e "${YELLOW}[1/3] Starting DNS query capture...${NC}"
docker logs -f coredns-smartdns 2>&1 | tee "$OUTPUT_DIR/dns-queries.log" &
DNS_PID=$!

# Capture 2: DoH backend queries
echo -e "${YELLOW}[2/3] Starting DoH backend capture...${NC}"
docker logs -f doh-backend 2>&1 | grep -E "xbox|live|microsoft|gamepass|discord" | tee "$OUTPUT_DIR/doh-queries.log" &
DOH_PID=$!

# Capture 3: SNI proxy connections (what domains Xbox connects to)
echo -e "${YELLOW}[3/3] Starting SNI proxy connection capture...${NC}"
tail -f /var/log/sniproxy/https_access.log 2>/dev/null | tee "$OUTPUT_DIR/sniproxy-connections.log" &
SNI_PID=$!

# Capture 4: Network connections to VPS (optional - shows IPs)
echo -e "${YELLOW}[4/4] Starting network connection capture...${NC}"
timeout 600 tcpdump -i any -n 'host 91.235.234.92 and (port 443 or port 80 or port 3074 or port 3544)' -w "$OUTPUT_DIR/network.pcap" 2>&1 &
TCPDUMP_PID=$!

# Cleanup function
cleanup() {
    echo ""
    echo ""
    echo "================================================"
    echo -e "${YELLOW}Stopping captures...${NC}"
    kill $DNS_PID $DOH_PID $SNI_PID $TCPDUMP_PID 2>/dev/null || true
    sleep 2
    
    echo ""
    echo "================================================"
    echo -e "${GREEN}Capture Complete!${NC}"
    echo "================================================"
    echo ""
    echo "Files saved to: $OUTPUT_DIR"
    echo ""
    echo "Analyzing captured data..."
    echo ""
    
    # Extract unique domains from DNS queries
    echo "=== Unique Xbox domains queried ==="
    grep -iE "xbox|live|microsoft|gamepass|discord" "$OUTPUT_DIR/dns-queries.log" | \
        grep -oE '[a-zA-Z0-9.-]+\.(xboxlive|xboxservices|xbox|live|microsoft|gamepass|discord|msftncsi|msftconnecttest|windows|msn)\.[a-z]+' | \
        sort -u | tee "$OUTPUT_DIR/unique-domains.txt"
    
    echo ""
    echo "=== Domains Xbox connected to (from SNI proxy) ==="
    grep -oE '\[[^]]+\]' "$OUTPUT_DIR/sniproxy-connections.log" | \
        sed 's/\[//g; s/\]//g' | \
        grep -v "bypass.440.info" | \
        grep -v "91.235.234.92" | \
        sort -u | tee "$OUTPUT_DIR/connected-domains.txt"
    
    echo ""
    echo "================================================"
    echo "Next steps:"
    echo "1. Review: cat $OUTPUT_DIR/unique-domains.txt"
    echo "2. Review: cat $OUTPUT_DIR/connected-domains.txt"
    echo "3. Add missing domains to coredns/xbox-hosts"
    echo "================================================"
    
    exit 0
}

trap cleanup INT TERM

echo ""
echo -e "${GREEN}✅ All captures started!${NC}"
echo ""
echo "Now use your Xbox:"
echo "  - Test network connection"
echo "  - Open Xbox Store"
echo "  - Try multiplayer games"
echo "  - Open Discord app"
echo ""
echo "Capturing for up to 10 minutes..."
echo "Press Ctrl+C when done to analyze results"
echo ""

# Wait for user interrupt
wait


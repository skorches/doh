#!/bin/bash

# Analyze Wireshark .pcap file to extract Xbox domains

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Wireshark PCAP Analyzer for Xbox"
echo "================================================"
echo ""

# Check if file provided
if [ -z "$1" ]; then
    echo "Usage: $0 <wireshark-file.pcap>"
    echo ""
    echo "This script will extract:"
    echo "  - DNS queries (domains Xbox looked up)"
    echo "  - SNI from TLS (domains Xbox connected to via HTTPS)"
    echo "  - HTTP Host headers (domains Xbox connected to via HTTP)"
    echo ""
    exit 1
fi

PCAP_FILE="$1"

if [ ! -f "$PCAP_FILE" ]; then
    echo -e "${RED}File not found: $PCAP_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}Analyzing: $PCAP_FILE${NC}"
echo ""

# Check if tshark is installed
if ! command -v tshark &> /dev/null; then
    echo -e "${YELLOW}Installing tshark (Wireshark command-line tool)...${NC}"
    apt-get update -qq
    apt-get install -y tshark
fi

OUTPUT_DIR="/root/doh/wireshark-analysis-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo -e "${YELLOW}[1/5] Extracting DNS queries...${NC}"
tshark -r "$PCAP_FILE" -Y "dns.flags.response == 0" -T fields -e dns.qry.name 2>/dev/null | \
    sort -u | \
    grep -v "^$" | \
    tee "$OUTPUT_DIR/dns-queries.txt" > /dev/null

DNS_COUNT=$(wc -l < "$OUTPUT_DIR/dns-queries.txt")
echo -e "${GREEN}Found $DNS_COUNT DNS queries${NC}"

echo ""
echo -e "${YELLOW}[2/5] Extracting SNI (TLS Server Name Indication)...${NC}"
tshark -r "$PCAP_FILE" -Y "tls.handshake.type == 1" -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    sort -u | \
    grep -v "^$" | \
    tee "$OUTPUT_DIR/tls-sni.txt" > /dev/null

SNI_COUNT=$(wc -l < "$OUTPUT_DIR/tls-sni.txt")
echo -e "${GREEN}Found $SNI_COUNT TLS SNI entries${NC}"

echo ""
echo -e "${YELLOW}[3/5] Extracting HTTP Host headers...${NC}"
tshark -r "$PCAP_FILE" -Y "http.host" -T fields -e http.host 2>/dev/null | \
    sort -u | \
    grep -v "^$" | \
    tee "$OUTPUT_DIR/http-hosts.txt" > /dev/null

HTTP_COUNT=$(wc -l < "$OUTPUT_DIR/http-hosts.txt")
echo -e "${GREEN}Found $HTTP_COUNT HTTP Host headers${NC}"

echo ""
echo -e "${YELLOW}[4/5] Extracting destination IPs (Xbox connections)...${NC}"
tshark -r "$PCAP_FILE" -Y "ip" -T fields -e ip.dst 2>/dev/null | \
    sort -u | \
    grep -v "^$" | \
    tee "$OUTPUT_DIR/destination-ips.txt" > /dev/null

IP_COUNT=$(wc -l < "$OUTPUT_DIR/destination-ips.txt")
echo -e "${GREEN}Found $IP_COUNT unique destination IPs${NC}"

echo ""
echo -e "${YELLOW}[5/5] Combining all Xbox-related domains...${NC}"

# Combine all domains and filter for Xbox/Microsoft/Discord
cat "$OUTPUT_DIR/dns-queries.txt" "$OUTPUT_DIR/tls-sni.txt" "$OUTPUT_DIR/http-hosts.txt" 2>/dev/null | \
    sort -u | \
    grep -iE "xbox|live|microsoft|gamepass|discord|msftncsi|msftconnecttest|windows|msn|azure|office365|outlook|onedrive|skype|teams" | \
    grep -v "bypass.440.info" | \
    grep -v "^$" | \
    tee "$OUTPUT_DIR/xbox-domains.txt" > /dev/null

XBOX_DOMAIN_COUNT=$(wc -l < "$OUTPUT_DIR/xbox-domains.txt")
echo -e "${GREEN}Found $XBOX_DOMAIN_COUNT Xbox-related domains${NC}"

echo ""
echo "================================================"
echo -e "${GREEN}Analysis Complete!${NC}"
echo "================================================"
echo ""
echo "Results saved to: $OUTPUT_DIR"
echo ""
echo "Files created:"
echo "  - dns-queries.txt ($DNS_COUNT queries)"
echo "  - tls-sni.txt ($SNI_COUNT SNI entries)"
echo "  - http-hosts.txt ($HTTP_COUNT hosts)"
echo "  - destination-ips.txt ($IP_COUNT IPs)"
echo "  - xbox-domains.txt ($XBOX_DOMAIN_COUNT Xbox domains)"
echo ""

# Show sample domains
if [ "$XBOX_DOMAIN_COUNT" -gt 0 ]; then
    echo "Sample Xbox domains found:"
    head -20 "$OUTPUT_DIR/xbox-domains.txt"
    if [ "$XBOX_DOMAIN_COUNT" -gt 20 ]; then
        echo "... and $((XBOX_DOMAIN_COUNT - 20)) more"
    fi
    echo ""
fi

# Show destination IPs (might be Xbox servers)
if [ "$IP_COUNT" -gt 0 ]; then
    echo "Top destination IPs (might be Xbox servers):"
    head -20 "$OUTPUT_DIR/destination-ips.txt"
    echo ""
fi

echo "================================================"
echo "Next steps:"
echo "1. Review domains: cat $OUTPUT_DIR/xbox-domains.txt"
echo "2. Add to Smart DNS: ./add-wireshark-domains.sh $OUTPUT_DIR/xbox-domains.txt"
echo "================================================"


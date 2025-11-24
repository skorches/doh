#!/bin/bash

# Extract domains from pcap file (local analysis, no VPS changes)
# Usage: ./extract-domains-local.sh /path/to/xbox-cap.pcapng

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-pcap-file>"
    echo ""
    echo "Example: $0 ~/Downloads/xbox-cap.pcapng"
    exit 1
fi

PCAP_FILE="$1"

if [ ! -f "$PCAP_FILE" ]; then
    echo -e "${RED}❌ File not found: $PCAP_FILE${NC}"
    exit 1
fi

echo "================================================"
echo "Extracting Domains from Xbox Capture"
echo "================================================"
echo ""
echo "File: $PCAP_FILE"
echo "Size: $(du -h "$PCAP_FILE" | cut -f1)"
echo ""

# Check if tshark is installed
if ! command -v tshark &> /dev/null; then
    echo -e "${YELLOW}tshark not found. Installing...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y tshark
    elif command -v yum &> /dev/null; then
        sudo yum install -y wireshark
    else
        echo -e "${RED}❌ Please install Wireshark/tshark manually${NC}"
        exit 1
    fi
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
DOMAINS_FILE="$TEMP_DIR/domains.txt"
UNIQUE_DOMAINS="$TEMP_DIR/unique_domains.txt"
OUTPUT_FILE="$(dirname "$PCAP_FILE")/xbox-domains-extracted.txt"

echo -e "${YELLOW}[1/3] Extracting DNS queries...${NC}"

# Extract DNS queries
tshark -r "$PCAP_FILE" -Y "dns.flags.response == 0" -T fields -e dns.qry.name 2>/dev/null | \
    grep -v "^$" | sort -u > "$DOMAINS_FILE" || true

DNS_COUNT=$(wc -l < "$DOMAINS_FILE" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $DNS_COUNT DNS queries${NC}"

echo ""
echo -e "${YELLOW}[2/3] Extracting TLS SNI...${NC}"

# Extract TLS SNI
tshark -r "$PCAP_FILE" -Y "tls.handshake.type == 1" -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    grep -v "^$" | sort -u >> "$DOMAINS_FILE" || true

echo -e "  ${GREEN}✅ Found TLS SNI entries${NC}"

echo ""
echo -e "${YELLOW}[3/3] Extracting HTTP Host headers...${NC}"

# Extract HTTP Host headers
tshark -r "$PCAP_FILE" -Y "http.host" -T fields -e http.host 2>/dev/null | \
    grep -v "^$" | sort -u >> "$DOMAINS_FILE" || true

echo -e "  ${GREEN}✅ Found HTTP Host headers${NC}"

echo ""
echo -e "${YELLOW}Processing domains...${NC}"

# Clean and filter
cat "$DOMAINS_FILE" | \
    grep -v "^$" | \
    grep -v "^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$" | \
    grep -v "^localhost$" | \
    grep -v "\.local$" | \
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" | \
    grep -v "\.arpa$" | \
    sort -u > "$UNIQUE_DOMAINS"

TOTAL_DOMAINS=$(wc -l < "$UNIQUE_DOMAINS" | tr -d ' ')

# Filter out already-covered domains
ALREADY_COVERED=(
    "xboxlive.com"
    "xboxservices.com"
    "xbox.com"
    "microsoft.com"
    "microsoftonline.com"
    "live.com"
    "msftncsi.com"
    "msftconnecttest.com"
    "windows.com"
    "msn.com"
    "gamepass.com"
    "discord.com"
    "discordapp.com"
    "discordapp.net"
    "discord.gg"
    "discord.media"
)

NEW_DOMAINS="$TEMP_DIR/new_domains.txt"
> "$NEW_DOMAINS"

while IFS= read -r domain; do
    SKIP=false
    for covered in "${ALREADY_COVERED[@]}"; do
        if [[ "$domain" == *"$covered"* ]]; then
            SKIP=true
            break
        fi
    done
    
    if [ "$SKIP" = false ]; then
        echo "$domain" >> "$NEW_DOMAINS"
    fi
done < "$UNIQUE_DOMAINS"

NEW_COUNT=$(wc -l < "$NEW_DOMAINS" | tr -d ' ')

echo ""
echo "================================================"
echo "Results"
echo "================================================"
echo ""
echo -e "Total unique domains: ${BLUE}$TOTAL_DOMAINS${NC}"
echo -e "Already covered: ${YELLOW}$((TOTAL_DOMAINS - NEW_COUNT))${NC}"
echo -e "New domains to add: ${GREEN}$NEW_COUNT${NC}"
echo ""

if [ "$NEW_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ All domains are already covered!${NC}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Save to file
cp "$NEW_DOMAINS" "$OUTPUT_FILE"

echo -e "${YELLOW}New domains (first 30):${NC}"
echo "----------------------------------------"
head -30 "$NEW_DOMAINS"
if [ "$NEW_COUNT" -gt 30 ]; then
    echo "... and $((NEW_COUNT - 30)) more"
fi
echo ""
echo -e "${GREEN}✅ Full list saved to: $OUTPUT_FILE${NC}"
echo ""
echo "To add these domains to your VPS:"
echo "  1. Copy the file to your VPS:"
echo "     scp $OUTPUT_FILE root@YOUR_VPS_IP:/root/doh/"
echo ""
echo "  2. On your VPS, run:"
echo "     cd /root/doh"
echo "     cat xbox-domains-extracted.txt | xargs ./scripts/maintenance/add-game-domain.sh"
echo ""
echo "Or use the full analysis script on VPS:"
echo "  scp $PCAP_FILE root@YOUR_VPS_IP:/root/doh/"
echo "  ssh root@YOUR_VPS_IP"
echo "  cd /root/doh"
echo "  ./scripts/analysis/analyze-xbox-pcap.sh /root/doh/xbox-cap.pcapng"

rm -rf "$TEMP_DIR"


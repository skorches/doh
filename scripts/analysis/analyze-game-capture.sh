#!/bin/bash

# Analyze gameplay capture specifically for EA and Activision domains
# Usage: ./analyze-game-capture.sh <pcap-file>

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: $0 <pcap-file>"
    echo ""
    echo "Example: $0 ~/Downloads/xbox-ea-activision.pcapng"
    exit 1
fi

PCAP_FILE="$1"

if [ ! -f "$PCAP_FILE" ]; then
    echo -e "${RED}❌ File not found: $PCAP_FILE${NC}"
    exit 1
fi

echo "================================================"
echo "Analyzing Gameplay Capture for EA/Activision"
echo "================================================"
echo ""
echo "File: $PCAP_FILE"
echo ""

# Check if tshark is installed
if ! command -v tshark &> /dev/null; then
    echo -e "${YELLOW}Installing tshark...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y tshark
    else
        echo -e "${RED}❌ Please install tshark manually${NC}"
        exit 1
    fi
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
ALL_DOMAINS="$TEMP_DIR/all_domains.txt"
EA_DOMAINS="$TEMP_DIR/ea_domains.txt"
ACTIVISION_DOMAINS="$TEMP_DIR/activision_domains.txt"
OTHER_GAME_DOMAINS="$TEMP_DIR/other_game_domains.txt"
OUTPUT_FILE="$(dirname "$PCAP_FILE")/game-domains-extracted.txt"

echo -e "${YELLOW}[1/4] Extracting all domains...${NC}"

# Extract DNS queries
tshark -r "$PCAP_FILE" -Y "dns.flags.response == 0" -T fields -e dns.qry.name 2>/dev/null | \
    grep -v "^$" | sort -u > "$ALL_DOMAINS" || true

# Extract TLS SNI
tshark -r "$PCAP_FILE" -Y "tls.handshake.type == 1" -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    grep -v "^$" | sort -u >> "$ALL_DOMAINS" || true

# Extract HTTP Host headers
tshark -r "$PCAP_FILE" -Y "http.host" -T fields -e http.host 2>/dev/null | \
    grep -v "^$" | sort -u >> "$ALL_DOMAINS" || true

# Clean domains
cat "$ALL_DOMAINS" | \
    grep -v "^$" | \
    grep -v "^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$" | \
    grep -v "^localhost$" | \
    grep -v "\.local$" | \
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" | \
    grep -v "\.arpa$" | \
    sort -u > "$ALL_DOMAINS"

TOTAL=$(wc -l < "$ALL_DOMAINS" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $TOTAL total domains${NC}"

echo ""
echo -e "${YELLOW}[2/4] Filtering EA domains...${NC}"

# EA-related domains
cat "$ALL_DOMAINS" | grep -iE "(ea\.|easports|eamobile|origin|eaplay|tnt-ea|swtor|dice|bioware|respawn)" > "$EA_DOMAINS" || true

EA_COUNT=$(wc -l < "$EA_DOMAINS" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $EA_COUNT EA-related domains${NC}"

echo ""
echo -e "${YELLOW}[3/4] Filtering Activision domains...${NC}"

# Activision-related domains
cat "$ALL_DOMAINS" | grep -iE "(activision|callofduty|cod|sledgehammer|infinityward|treyarch|blizzard)" > "$ACTIVISION_DOMAINS" || true

ACTIVISION_COUNT=$(wc -l < "$ACTIVISION_DOMAINS" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $ACTIVISION_COUNT Activision-related domains${NC}"

echo ""
echo -e "${YELLOW}[4/4] Finding other game domains...${NC}"

# Other game publishers
GAME_KEYWORDS="ubisoft|epicgames|rockstar|2k|2ksports|riot|blizzard|bethesda|square-enix"
cat "$ALL_DOMAINS" | grep -iE "$GAME_KEYWORDS" > "$OTHER_GAME_DOMAINS" || true

OTHER_COUNT=$(wc -l < "$OTHER_GAME_DOMAINS" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $OTHER_COUNT other game domains${NC}"

# Combine all game domains
COMBINED="$TEMP_DIR/combined_game_domains.txt"
cat "$EA_DOMAINS" "$ACTIVISION_DOMAINS" "$OTHER_GAME_DOMAINS" | sort -u > "$COMBINED"

# Filter out already-covered domains
ALREADY_COVERED=(
    "xboxlive.com"
    "xboxservices.com"
    "microsoft.com"
    "discord.com"
)

FINAL_DOMAINS="$TEMP_DIR/final_domains.txt"
> "$FINAL_DOMAINS"

while IFS= read -r domain; do
    SKIP=false
    for covered in "${ALREADY_COVERED[@]}"; do
        if [[ "$domain" == *"$covered"* ]]; then
            SKIP=true
            break
        fi
    done
    
    if [ "$SKIP" = false ]; then
        echo "$domain" >> "$FINAL_DOMAINS"
    fi
done < "$COMBINED"

FINAL_COUNT=$(wc -l < "$FINAL_DOMAINS" | tr -d ' ')

echo ""
echo "================================================"
echo "Results"
echo "================================================"
echo ""
echo -e "Total domains found: ${BLUE}$TOTAL${NC}"
echo -e "EA domains: ${GREEN}$EA_COUNT${NC}"
echo -e "Activision domains: ${GREEN}$ACTIVISION_COUNT${NC}"
echo -e "Other game domains: ${GREEN}$OTHER_COUNT${NC}"
echo -e "New domains to add: ${GREEN}$FINAL_COUNT${NC}"
echo ""

if [ "$FINAL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No new game domains found${NC}"
    echo "This could mean:"
    echo "  • Domains are already covered"
    echo "  • Game uses Xbox Live infrastructure only"
    echo "  • Capture didn't include game traffic"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Save to file
cp "$FINAL_DOMAINS" "$OUTPUT_FILE"

echo -e "${BLUE}EA Domains:${NC}"
if [ "$EA_COUNT" -gt 0 ]; then
    cat "$EA_DOMAINS" | head -10
    if [ "$EA_COUNT" -gt 10 ]; then
        echo "... and $((EA_COUNT - 10)) more"
    fi
else
    echo "  (none found)"
fi

echo ""
echo -e "${BLUE}Activision Domains:${NC}"
if [ "$ACTIVISION_COUNT" -gt 0 ]; then
    cat "$ACTIVISION_DOMAINS" | head -10
    if [ "$ACTIVISION_COUNT" -gt 10 ]; then
        echo "... and $((ACTIVISION_COUNT - 10)) more"
    fi
else
    echo "  (none found)"
fi

echo ""
echo -e "${GREEN}✅ Full list saved to: $OUTPUT_FILE${NC}"
echo ""

# Show how to add
echo "To add these domains to your VPS:"
echo ""
echo "Option 1: Copy file and add manually"
echo "  scp $OUTPUT_FILE root@YOUR_VPS_IP:/root/doh/"
echo "  ssh root@YOUR_VPS_IP"
echo "  cd /root/doh"
echo "  cat game-domains-extracted.txt | xargs ./scripts/maintenance/add-game-domain.sh"
echo ""
echo "Option 2: Use full analysis script on VPS"
echo "  scp $PCAP_FILE root@YOUR_VPS_IP:/root/doh/"
echo "  ssh root@YOUR_VPS_IP"
echo "  cd /root/doh"
echo "  ./scripts/analysis/analyze-xbox-pcap.sh /root/doh/$(basename "$PCAP_FILE")"
echo ""

rm -rf "$TEMP_DIR"


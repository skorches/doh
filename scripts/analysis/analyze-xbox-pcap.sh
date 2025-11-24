#!/bin/bash

# Analyze Xbox pcap file and extract domains to add to Smart DNS
# Usage: ./analyze-xbox-pcap.sh /path/to/xbox-cap.pcapng

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
echo "Analyzing Xbox Network Capture"
echo "================================================"
echo ""
echo "File: $PCAP_FILE"
echo ""

# Check if tshark is installed
if ! command -v tshark &> /dev/null; then
    echo -e "${YELLOW}Installing tshark (Wireshark command-line)...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y tshark
    elif command -v yum &> /dev/null; then
        yum install -y wireshark
    else
        echo -e "${RED}❌ Cannot install tshark. Please install Wireshark manually.${NC}"
        exit 1
    fi
fi

# Create temp directory for analysis
TEMP_DIR=$(mktemp -d)
DOMAINS_FILE="$TEMP_DIR/domains.txt"
UNIQUE_DOMAINS="$TEMP_DIR/unique_domains.txt"

echo -e "${YELLOW}[1/4] Extracting DNS queries...${NC}"

# Extract DNS queries (QNAME field)
tshark -r "$PCAP_FILE" -Y "dns.flags.response == 0" -T fields -e dns.qry.name 2>/dev/null | \
    grep -v "^$" | sort -u > "$DOMAINS_FILE" || true

DNS_COUNT=$(wc -l < "$DOMAINS_FILE" | tr -d ' ')
echo -e "  ${GREEN}✅ Found $DNS_COUNT DNS queries${NC}"

echo ""
echo -e "${YELLOW}[2/4] Extracting TLS SNI (Server Name Indication)...${NC}"

# Extract TLS SNI from Client Hello
tshark -r "$PCAP_FILE" -Y "tls.handshake.type == 1" -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    grep -v "^$" | sort -u >> "$DOMAINS_FILE" || true

SNI_COUNT=$(grep -c "." "$DOMAINS_FILE" 2>/dev/null || echo "0")
echo -e "  ${GREEN}✅ Found TLS SNI entries${NC}"

echo ""
echo -e "${YELLOW}[3/4] Extracting HTTP Host headers...${NC}"

# Extract HTTP Host headers
tshark -r "$PCAP_FILE" -Y "http.host" -T fields -e http.host 2>/dev/null | \
    grep -v "^$" | sort -u >> "$DOMAINS_FILE" || true

HTTP_COUNT=$(grep -c "." "$DOMAINS_FILE" 2>/dev/null || echo "0")
echo -e "  ${GREEN}✅ Found HTTP Host headers${NC}"

echo ""
echo -e "${YELLOW}[4/4] Processing and filtering domains...${NC}"

# Clean and filter domains
cat "$DOMAINS_FILE" | \
    # Remove empty lines
    grep -v "^$" | \
    # Remove IP addresses
    grep -v "^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$" | \
    # Remove local/private domains
    grep -v "^localhost$" | \
    grep -v "\.local$" | \
    grep -v "^[0-9]" | \
    # Remove invalid characters
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" | \
    # Remove common non-game domains
    grep -v "\.arpa$" | \
    grep -v "\.in-addr$" | \
    # Sort and get unique
    sort -u > "$UNIQUE_DOMAINS"

TOTAL_DOMAINS=$(wc -l < "$UNIQUE_DOMAINS" | tr -d ' ')

echo -e "  ${GREEN}✅ Found $TOTAL_DOMAINS unique domains${NC}"

# Filter out domains already covered
echo ""
echo -e "${BLUE}Filtering out already-covered domains...${NC}"

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
    # Check if domain or its parent is already covered
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
echo "Analysis Results"
echo "================================================"
echo ""
echo -e "Total unique domains found: ${BLUE}$TOTAL_DOMAINS${NC}"
echo -e "Already covered domains: ${YELLOW}$((TOTAL_DOMAINS - NEW_COUNT))${NC}"
echo -e "New domains to add: ${GREEN}$NEW_COUNT${NC}"
echo ""

if [ "$NEW_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ All domains are already covered!${NC}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

echo -e "${YELLOW}New domains found:${NC}"
echo "----------------------------------------"
cat "$NEW_DOMAINS" | head -20
if [ "$NEW_COUNT" -gt 20 ]; then
    echo "... and $((NEW_COUNT - 20)) more"
fi
echo ""

# Ask if user wants to add them
read -p "Add these domains to Smart DNS? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Domains saved to: $NEW_DOMAINS"
    echo "You can review and add them manually later."
    exit 0
fi

# Get VPS IP
cd /root/doh 2>/dev/null || cd "$(dirname "$0")/../.."
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")

if [ -z "$VPS_IP" ]; then
    read -p "Enter your VPS IP address: " VPS_IP
    if [ -z "$VPS_IP" ]; then
        echo -e "${RED}❌ VPS IP is required${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}Adding domains to Smart DNS...${NC}"

# Add to xbox-hosts
HOSTS_FILE="coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ xbox-hosts file not found. Are you in the doh directory?${NC}"
    exit 1
fi

# Backup
cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Add new domains
echo "" >> "$HOSTS_FILE"
echo "# Domains extracted from pcap on $(date)" >> "$HOSTS_FILE"
while IFS= read -r domain; do
    # Remove www. prefix for base domain
    BASE_DOMAIN=$(echo "$domain" | sed 's/^www\.//')
    
    # Check if already in file
    if ! grep -q "^$VPS_IP.*$BASE_DOMAIN" "$HOSTS_FILE"; then
        echo "$VPS_IP $BASE_DOMAIN" >> "$HOSTS_FILE"
        echo "$VPS_IP www.$BASE_DOMAIN" >> "$HOSTS_FILE"
    fi
done < "$NEW_DOMAINS"

echo -e "  ${GREEN}✅ Added to $HOSTS_FILE${NC}"

# Add to SNIProxy config
SNIPROXY_CONF="/etc/sniproxy.conf"
if [ -f "$SNIPROXY_CONF" ]; then
    # Backup
    cp "$SNIPROXY_CONF" "${SNIPROXY_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add SNIProxy rules
    while IFS= read -r domain; do
        BASE_DOMAIN=$(echo "$domain" | sed 's/^www\.//')
        ESCAPED_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's/\./\\./g')
        
        # Check if rule already exists
        if ! grep -q ".*\\.$ESCAPED_DOMAIN\\$" "$SNIPROXY_CONF"; then
            # Add before closing brace
            sed -i "/^}$/i\    .*\\.$ESCAPED_DOMAIN\\$ *" "$SNIPROXY_CONF"
        fi
    done < "$NEW_DOMAINS"
    
    echo -e "  ${GREEN}✅ Added to SNIProxy config${NC}"
    
    # Restart SNIProxy
    systemctl restart sniproxy
    sleep 1
    
    if systemctl is-active --quiet sniproxy; then
        echo -e "  ${GREEN}✅ SNIProxy restarted${NC}"
    else
        echo -e "  ${RED}❌ SNIProxy failed to restart${NC}"
        echo "Check config: journalctl -u sniproxy -n 20"
    fi
fi

# Restart CoreDNS if using Docker
if command -v docker &> /dev/null; then
    if docker ps | grep -q coredns-smartdns; then
        echo -e "${YELLOW}Restarting CoreDNS...${NC}"
        docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns
        sleep 2
        echo -e "  ${GREEN}✅ CoreDNS restarted${NC}"
    fi
fi

echo ""
echo -e "${GREEN}✅ Done! Added $NEW_COUNT new domains${NC}"
echo ""
echo "Backup files created:"
echo "  • ${HOSTS_FILE}.backup.*"
if [ -f "$SNIPROXY_CONF" ]; then
    echo "  • ${SNIPROXY_CONF}.backup.*"
fi
echo ""
echo "Full list of new domains saved to: $NEW_DOMAINS"

# Cleanup
rm -rf "$TEMP_DIR"


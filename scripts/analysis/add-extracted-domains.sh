#!/bin/bash

# Add extracted Xbox/game domains from pcap analysis
# This adds only the game-related domains, filtering out non-Xbox services

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root on your VPS${NC}"
    exit 1
fi

cd /root/doh

# Game-related domains extracted from pcap
GAME_DOMAINS=(
    # NBA 2K26
    "nba2k26-gw.aws.2ksports.com"
    "nba2k26-svc.2ksports.com"
    "nba2k26-ws.2ksports.com"
    "nba2k26-ws-telem.aws.2ksports.com"
    "nba-cdn3.2ksports.com"
    "w268ad8436.aws.2ksports.com"
    # Microsoft/Azure
    "e-0014.e-msedge.net"
    "part-0016.t-0009.t-msedge.net"
    "part-0025.t-0009.t-msedge.net"
    "titlestoragewus0505.blob.core.windows.net"
)

echo "================================================"
echo "Adding Game Domains from Xbox Capture"
echo "================================================"
echo ""
echo "Domains to add: ${#GAME_DOMAINS[@]}"
echo ""

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi

# Use the existing add-game-domain script
echo -e "${YELLOW}Adding domains...${NC}"
./scripts/maintenance/add-game-domain.sh "${GAME_DOMAINS[@]}"

echo ""
echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "Added domains:"
for domain in "${GAME_DOMAINS[@]}"; do
    echo "  • $domain"
done


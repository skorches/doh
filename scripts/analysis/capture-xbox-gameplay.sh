#!/bin/bash

# Guide for capturing Xbox gameplay traffic
# This script provides instructions and tools for capturing packets

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Xbox Gameplay Packet Capture Guide"
echo "================================================"
echo ""

cat << 'EOF'
METHODS TO CAPTURE XBOX TRAFFIC:
─────────────────────────────────

METHOD 1: Router-Level Capture (Recommended)
  If your router (Keenetic) supports packet capture:
  
  1. Enable packet capture on router
  2. Start capture before launching game
  3. Play EA/Activision game for 5-10 minutes
  4. Stop capture and download .pcap file
  5. Analyze with: ./analyze-game-capture.sh <file.pcapng>

METHOD 2: Network Tap/Mirror Port
  If you have a managed switch:
  
  1. Set up port mirroring to mirror Xbox traffic
  2. Connect computer to mirror port
  3. Run tcpdump/Wireshark on computer
  4. Capture while playing game

METHOD 3: Computer as Gateway (Advanced)
  Route Xbox traffic through a computer:
  
  1. Set computer as Xbox gateway
  2. Enable IP forwarding on computer
  3. Run tcpdump/Wireshark on computer
  4. Capture all Xbox traffic

METHOD 4: Wireshark on Router (If Supported)
  Some routers allow SSH access:
  
  1. SSH into router
  2. Install tcpdump
  3. Capture traffic: tcpdump -i eth0 -w capture.pcap
  4. Transfer file to computer

RECOMMENDED: Use your router's packet capture feature
EOF

echo ""
echo -e "${YELLOW}Checking for capture tools...${NC}"
echo ""

# Check for tshark
if command -v tshark &> /dev/null; then
    echo -e "${GREEN}✅ tshark installed${NC}"
else
    echo -e "${YELLOW}⚠ tshark not found${NC}"
    echo "Install: sudo apt-get install tshark"
fi

# Check for tcpdump
if command -v tcpdump &> /dev/null; then
    echo -e "${GREEN}✅ tcpdump installed${NC}"
else
    echo -e "${YELLOW}⚠ tcpdump not found${NC}"
    echo "Install: sudo apt-get install tcpdump"
fi

echo ""
echo "================================================"
echo "Quick Capture Commands"
echo "================================================"
echo ""

cat << 'EOF'
ON YOUR COMPUTER (if routing through it):
──────────────────────────────────────────
# Capture all traffic on interface (replace eth0 with your interface)
sudo tcpdump -i eth0 -w xbox-ea-activision.pcapng host XBOX_IP

# Or with tshark
sudo tshark -i eth0 -w xbox-ea-activision.pcapng -f "host XBOX_IP"

# Find your Xbox IP first:
# Xbox → Settings → Network → Advanced → IP Settings

ON ROUTER (if SSH access):
──────────────────────────
# Capture Xbox traffic (replace XBOX_IP with actual IP)
tcpdump -i br0 -w /tmp/xbox-capture.pcap host XBOX_IP

# Then transfer to computer:
scp root@ROUTER_IP:/tmp/xbox-capture.pcap ./

CAPTURE DURATION:
─────────────────
• Start capture BEFORE launching game
• Play for 5-10 minutes (enough to connect, load, play)
• Stop capture
• File size: Usually 10-50MB for 10 minutes

WHAT TO CAPTURE:
────────────────
✅ Game launch and login
✅ Multiplayer matchmaking
✅ In-game activity
✅ Menu navigation
❌ Skip: Just sitting in menu (minimal traffic)
EOF

echo ""
echo "================================================"
echo "After Capture - Analyze Domains"
echo "================================================"
echo ""

cat << 'EOF'
Once you have the .pcap/.pcapng file:

1. Analyze for EA/Activision domains:
   ./scripts/analysis/analyze-game-capture.sh xbox-capture.pcapng

2. This will extract:
   • EA domains (ea.com, easports.com, etc.)
   • Activision domains (activision.com, callofduty.com, etc.)
   • Game-specific server domains
   • CDN domains

3. Add the found domains:
   ./scripts/maintenance/add-game-domain.sh domain1.com domain2.com ...

Or use the full analysis script that auto-adds:
   ./scripts/analysis/analyze-xbox-pcap.sh xbox-capture.pcapng
EOF

echo ""


#!/bin/bash

# Fix SNIProxy systemd service to handle forking properly

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
echo "Fixing SNIProxy Systemd Service"
echo "================================================"
echo ""

# Find SNIProxy service file (could be in different locations)
SNIPROXY_SERVICE=""
for location in \
    "/etc/systemd/system/sniproxy.service" \
    "/lib/systemd/system/sniproxy.service" \
    "/usr/lib/systemd/system/sniproxy.service"; do
    if [ -f "$location" ]; then
        SNIPROXY_SERVICE="$location"
        break
    fi
done

# If not found, create override or use systemd drop-in
if [ -z "$SNIPROXY_SERVICE" ]; then
    echo -e "${YELLOW}SNIProxy service file not found in standard locations${NC}"
    echo "Creating systemd override instead..."
    
    # Create override directory
    mkdir -p /etc/systemd/system/sniproxy.service.d/
    
    # Create override file
    cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOFCONF'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOFCONF
    
    echo -e "${GREEN}✅ Created systemd override${NC}"
    SNIPROXY_SERVICE="/etc/systemd/system/sniproxy.service.d/override.conf"
else
    echo -e "${GREEN}Found service file: $SNIPROXY_SERVICE${NC}"
fi

echo -e "${YELLOW}Updating SNIProxy service configuration...${NC}"

# If it's an override file, we're done
if [ "$SNIPROXY_SERVICE" = "/etc/systemd/system/sniproxy.service.d/override.conf" ]; then
    echo -e "${GREEN}✅ Override file created${NC}"
else
    # Backup original service file
    cp "$SNIPROXY_SERVICE" "${SNIPROXY_SERVICE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if already fixed
    if grep -q "Type=forking" "$SNIPROXY_SERVICE"; then
        echo -e "${GREEN}✅ Service already configured for forking${NC}"
    else
        # Create override instead of modifying system file
        mkdir -p /etc/systemd/system/sniproxy.service.d/
        cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOFCONF'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOFCONF
        echo -e "${GREEN}✅ Created systemd override (safer than modifying system file)${NC}"
    fi
fi

# Reload systemd
echo ""
echo -e "${YELLOW}Reloading systemd...${NC}"
systemctl daemon-reload

# Kill any leftover processes (more aggressively)
echo -e "${YELLOW}Cleaning up old processes...${NC}"
pkill -9 sniproxy 2>/dev/null || true
# Kill by PID if pkill didn't work
ps aux | grep sniproxy | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true
sleep 2

# Check what's using port 443
echo -e "${YELLOW}Checking port 443...${NC}"
PORT_443_USAGE=$(ss -tlnp | grep ":443" || echo "")
if [ -n "$PORT_443_USAGE" ]; then
    echo -e "${YELLOW}⚠ Port 443 is in use:${NC}"
    echo "$PORT_443_USAGE"
    echo ""
    echo -e "${YELLOW}Killing processes on port 443...${NC}"
    # Get PIDs using port 443 and kill them
    ss -tlnp | grep ":443" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null || true
    sleep 2
fi

# Restart SNIProxy
echo ""
echo -e "${YELLOW}Restarting SNIProxy...${NC}"
systemctl restart sniproxy
sleep 3

# Check status
echo ""
echo -e "${YELLOW}Checking SNIProxy status...${NC}"

if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy is listening on port 443${NC}"
elif systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy service is active${NC}"
elif pgrep -f sniproxy > /dev/null; then
    echo -e "${GREEN}✅ SNIProxy process is running${NC}"
    echo -e "${YELLOW}⚠ Systemd status may still show inactive, but SNIProxy is working${NC}"
else
    echo -e "${RED}❌ SNIProxy is not running${NC}"
    journalctl -u sniproxy -n 10 --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}✅ SNIProxy fixed!${NC}"
echo ""
echo "Note: If systemd still shows 'inactive', that's OK."
echo "The important thing is that SNIProxy is listening on port 443."
echo ""
echo "Verify: ss -tlnp | grep :443"


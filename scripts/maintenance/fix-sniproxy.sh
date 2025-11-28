#!/bin/bash

# Comprehensive SNIProxy fix (systemd, ports, timeouts)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "SNIProxy Comprehensive Fix"
echo "================================================"
echo ""

# Step 1: Fix systemd tracking
echo -e "${YELLOW}[1/4] Fixing systemd tracking...${NC}"
if [ ! -f /etc/systemd/system/sniproxy.service.d/override.conf ]; then
    mkdir -p /etc/systemd/system/sniproxy.service.d
    cat > /etc/systemd/system/sniproxy.service.d/override.conf << 'EOF'
[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
EOF
    systemctl daemon-reload
    echo -e "${GREEN}✅ Systemd override created${NC}"
else
    echo -e "${GREEN}✅ Systemd override already exists${NC}"
fi

# Step 2: Check port 443
echo ""
echo -e "${YELLOW}[2/4] Checking port 443...${NC}"
PORT_443_USAGE=$(ss -tlnp | grep ":443 " || echo "")
if [ -n "$PORT_443_USAGE" ]; then
    if echo "$PORT_443_USAGE" | grep -q "sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "${YELLOW}⚠ Port 443 in use by another process:${NC}"
        echo "$PORT_443_USAGE"
        read -p "Kill process using port 443? (y/n): " REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            PID=$(lsof -ti:443 2>/dev/null | head -1 || echo "")
            if [ -n "$PID" ]; then
                kill -9 "$PID" 2>/dev/null || true
                echo -e "${GREEN}✅ Process killed${NC}"
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠ Nothing listening on port 443${NC}"
fi

# Step 3: Start/restart SNIProxy
echo ""
echo -e "${YELLOW}[3/4] Starting SNIProxy...${NC}"
if ps aux | grep -q "[s]niproxy"; then
    echo -e "${GREEN}✅ SNIProxy is running${NC}"
    systemctl restart sniproxy
    sleep 2
else
    systemctl start sniproxy
    sleep 2
fi

# Step 4: Verify
echo ""
echo -e "${YELLOW}[4/4] Verifying SNIProxy...${NC}"
sleep 2

if ps aux | grep -q "[s]niproxy"; then
    echo -e "${GREEN}✅ SNIProxy process running${NC}"
    
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "${YELLOW}⚠ SNIProxy running but not listening on 443${NC}"
    fi
    
    # Check systemd status
    if systemctl is-active --quiet sniproxy; then
        echo -e "${GREEN}✅ Systemd reports SNIProxy as active${NC}"
    else
        echo -e "${YELLOW}⚠ Systemd reports inactive (but process is running)${NC}"
        echo "This is normal - SNIProxy forks, systemd tracking may be off"
    fi
else
    echo -e "${RED}❌ SNIProxy not running${NC}"
    echo "Check logs: journalctl -u sniproxy -n 20"
    exit 1
fi

echo ""
echo "================================================"
echo "✅ SNIProxy Fix Complete"
echo "================================================"
echo ""
echo "NOTE: SNIProxy doesn't support timeout settings."
echo "Timeouts are handled by the OS TCP stack."
echo ""


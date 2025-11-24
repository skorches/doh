#!/bin/bash

# Aggressively fix port 443 conflict

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
echo "Fixing Port 443 Conflict"
echo "================================================"
echo ""

# Step 1: Find what's using port 443
echo -e "${YELLOW}[1/5] Finding what's using port 443...${NC}"
PORT_443_INFO=$(ss -tlnp | grep ":443" || echo "")

if [ -z "$PORT_443_INFO" ]; then
    echo -e "${GREEN}✅ Port 443 is free${NC}"
else
    echo -e "${YELLOW}Port 443 is in use:${NC}"
    echo "$PORT_443_INFO"
    echo ""
    
    # Extract PIDs
    PIDS=$(echo "$PORT_443_INFO" | grep -oP 'pid=\K[0-9]+' | sort -u)
    
    if [ -n "$PIDS" ]; then
        echo -e "${YELLOW}Found processes: $PIDS${NC}"
        for PID in $PIDS; do
            PROCESS_INFO=$(ps -p $PID -o comm=,args= 2>/dev/null || echo "unknown")
            echo "  PID $PID: $PROCESS_INFO"
        done
    fi
fi

# Step 2: Stop SNIProxy service
echo ""
echo -e "${YELLOW}[2/5] Stopping SNIProxy service...${NC}"
systemctl stop sniproxy 2>/dev/null || true
sleep 1

# Step 3: Kill all sniproxy processes
echo ""
echo -e "${YELLOW}[3/5] Killing all sniproxy processes...${NC}"
pkill -9 sniproxy 2>/dev/null || true
# Also kill by finding processes
ps aux | grep '[s]niproxy' | awk '{print $2}' | xargs kill -9 2>/dev/null || true
sleep 2

# Step 4: Kill whatever is on port 443
echo ""
echo -e "${YELLOW}[4/5] Killing processes on port 443...${NC}"

# Get current port 443 usage
PORT_443_INFO=$(ss -tlnp | grep ":443" || echo "")
if [ -n "$PORT_443_INFO" ]; then
    PIDS=$(echo "$PORT_443_INFO" | grep -oP 'pid=\K[0-9]+' | sort -u)
    
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            PROCESS_NAME=$(ps -p $PID -o comm= 2>/dev/null || echo "unknown")
            echo "  Killing PID $PID ($PROCESS_NAME)..."
            kill -9 $PID 2>/dev/null || true
        done
        sleep 2
    fi
fi

# Step 5: Verify port is free and start SNIProxy
echo ""
echo -e "${YELLOW}[5/5] Verifying port 443 is free...${NC}"

PORT_443_CHECK=$(ss -tlnp | grep ":443" || echo "")
if [ -n "$PORT_443_CHECK" ]; then
    echo -e "${RED}❌ Port 443 is still in use:${NC}"
    echo "$PORT_443_CHECK"
    echo ""
    echo "This might be Nginx or another service."
    echo "Checking if it's Nginx..."
    
    if echo "$PORT_443_CHECK" | grep -q nginx; then
        echo -e "${YELLOW}⚠ Nginx is on port 443${NC}"
        echo "Nginx should only be on 8443 (internal)."
        echo "Checking docker-compose.yml..."
        
        # Check if nginx is accidentally exposed on 443
        if docker ps | grep doh-nginx | grep -q ":443"; then
            echo -e "${RED}❌ Nginx container is exposing port 443!${NC}"
            echo "This conflicts with SNIProxy."
            echo ""
            echo "Solution: Nginx should only expose 8443, not 443."
            echo "SNIProxy should be the only thing on port 443."
            exit 1
        fi
    fi
    
    echo ""
    echo -e "${RED}❌ Cannot start SNIProxy - port 443 still in use${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Port 443 is free${NC}"
fi

# Start SNIProxy
echo ""
echo -e "${YELLOW}Starting SNIProxy...${NC}"
systemctl start sniproxy
sleep 3

# Check status
echo ""
echo -e "${YELLOW}Checking SNIProxy status...${NC}"

if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy is listening on port 443${NC}"
    systemctl status sniproxy --no-pager | head -10
elif systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✅ SNIProxy service is active${NC}"
elif pgrep -f sniproxy > /dev/null; then
    echo -e "${GREEN}✅ SNIProxy process is running${NC}"
    echo -e "${YELLOW}⚠ Systemd status may show inactive, but SNIProxy is working${NC}"
else
    echo -e "${RED}❌ SNIProxy failed to start${NC}"
    journalctl -u sniproxy -n 15 --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Port 443 conflict fixed!${NC}"


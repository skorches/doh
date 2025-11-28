#!/bin/bash

# Stop and disable 3proxy service

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
echo "Stopping 3proxy Service"
echo "================================================"
echo ""

# Check if 3proxy service exists
if systemctl list-unit-files | grep -q "3proxy"; then
    SERVICE_NAME=$(systemctl list-unit-files | grep "3proxy" | awk '{print $1}' | head -1)
    
    echo -e "${YELLOW}Found service: $SERVICE_NAME${NC}"
    echo ""
    
    # Stop service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${YELLOW}Stopping $SERVICE_NAME...${NC}"
        systemctl stop "$SERVICE_NAME"
        sleep 1
        echo -e "${GREEN}✅ Service stopped${NC}"
    else
        echo -e "${GREEN}✅ Service already stopped${NC}"
    fi
    
    # Disable service
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${YELLOW}Disabling $SERVICE_NAME...${NC}"
        systemctl disable "$SERVICE_NAME"
        echo -e "${GREEN}✅ Service disabled${NC}"
    else
        echo -e "${GREEN}✅ Service already disabled${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No 3proxy systemd service found${NC}"
fi

# Check for 3proxy process
if ps aux | grep -q "[3]proxy"; then
    echo ""
    echo -e "${YELLOW}Found running 3proxy process, killing...${NC}"
    pkill -f 3proxy || true
    sleep 1
    echo -e "${GREEN}✅ Process killed${NC}"
else
    echo -e "${GREEN}✅ No 3proxy process running${NC}"
fi

# Check for Docker container
if docker ps | grep -q "3proxy"; then
    echo ""
    echo -e "${YELLOW}Found 3proxy Docker container, stopping...${NC}"
    CONTAINER_NAME=$(docker ps | grep "3proxy" | awk '{print $NF}' | head -1)
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    echo -e "${GREEN}✅ Container stopped${NC}"
else
    echo -e "${GREEN}✅ No 3proxy Docker container running${NC}"
fi

# Check port 1080
echo ""
echo -e "${BLUE}Checking port 1080...${NC}"
if ss -tlnp | grep -q ":1080"; then
    echo -e "${YELLOW}⚠ Port 1080 still in use:${NC}"
    ss -tlnp | grep ":1080"
    echo ""
    read -p "Kill process using port 1080? (y/n): " REPLY
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        PID=$(lsof -ti:1080 2>/dev/null | head -1 || echo "")
        if [ -n "$PID" ]; then
            kill -9 "$PID" 2>/dev/null || true
            echo -e "${GREEN}✅ Process killed${NC}"
        fi
    fi
else
    echo -e "${GREEN}✅ Port 1080 is free${NC}"
fi

echo ""
echo "================================================"
echo "✅ 3proxy Stopped"
echo "================================================"
echo ""
echo "3proxy has been stopped and disabled."
echo "It will not start automatically on boot."
echo ""
echo "To start it again (if needed):"
echo "  systemctl start 3proxy-discord"
echo "  systemctl enable 3proxy-discord"
echo ""


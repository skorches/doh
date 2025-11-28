#!/bin/bash

# Comprehensive log monitoring script for DoH + Smart DNS setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "================================================"
echo "DoH + Smart DNS Log Monitor"
echo "================================================"
echo ""
echo "Press Ctrl+C to exit"
echo ""

# Function to show menu
show_menu() {
    echo ""
    echo -e "${CYAN}=== Monitoring Options ===${NC}"
    echo "1) SNIProxy Access Logs (real-time)"
    echo "2) SNIProxy Error Logs (real-time)"
    echo "3) CoreDNS Logs (real-time)"
    echo "4) Nginx Logs (real-time)"
    echo "5) DoH Backend Logs (real-time)"
    echo "6) All Logs Combined (real-time)"
    echo "7) Connection Statistics"
    echo "8) Recent Xbox Connections"
    echo "9) System Logs (Xbox-related)"
    echo "10) Port 443 Connections (live)"
    echo "11) DNS Query Logs"
    echo "0) Exit"
    echo ""
    read -p "Select option [0-11]: " choice
}

# Function to monitor SNIProxy access logs
monitor_sniproxy_access() {
    echo ""
    echo -e "${BLUE}=== SNIProxy Access Logs (Press Ctrl+C to stop) ===${NC}"
    echo ""
    if [ -f /var/log/sniproxy/https_access.log ]; then
        tail -f /var/log/sniproxy/https_access.log 2>/dev/null || {
            echo -e "${YELLOW}⚠ Log file not found, checking journal...${NC}"
            journalctl -u sniproxy -f --no-pager 2>/dev/null || echo -e "${RED}❌ No SNIProxy logs available${NC}"
        }
    else
        echo -e "${YELLOW}⚠ Log file not found, checking journal...${NC}"
        journalctl -u sniproxy -f --no-pager 2>/dev/null || echo -e "${RED}❌ No SNIProxy logs available${NC}"
    fi
}

# Function to monitor SNIProxy error logs
monitor_sniproxy_errors() {
    echo ""
    echo -e "${BLUE}=== SNIProxy Error Logs (Press Ctrl+C to stop) ===${NC}"
    echo ""
    journalctl -u sniproxy -f --no-pager -p err 2>/dev/null || {
        echo -e "${YELLOW}⚠ Checking syslog for errors...${NC}"
        tail -f /var/log/syslog | grep -i sniproxy || echo -e "${RED}❌ No error logs available${NC}"
    }
}

# Function to monitor CoreDNS logs
monitor_coredns() {
    echo ""
    echo -e "${BLUE}=== CoreDNS Logs (Press Ctrl+C to stop) ===${NC}"
    echo ""
    docker logs -f coredns-smartdns 2>&1 || echo -e "${RED}❌ CoreDNS container not running${NC}"
}

# Function to monitor Nginx logs
monitor_nginx() {
    echo ""
    echo -e "${BLUE}=== Nginx Logs (Press Ctrl+C to stop) ===${NC}"
    echo ""
    docker logs -f doh-nginx 2>&1 || echo -e "${RED}❌ Nginx container not running${NC}"
}

# Function to monitor DoH backend logs
monitor_doh_backend() {
    echo ""
    echo -e "${BLUE}=== DoH Backend Logs (Press Ctrl+C to stop) ===${NC}"
    echo ""
    docker logs -f doh-backend 2>&1 || echo -e "${RED}❌ DoH backend container not running${NC}"
}

# Function to monitor all logs combined
monitor_all() {
    echo ""
    echo -e "${BLUE}=== All Logs Combined (Press Ctrl+C to stop) ===${NC}"
    echo ""
    echo -e "${CYAN}Starting multi-log monitor...${NC}"
    echo ""
    
    # Create temporary log file
    TEMP_LOG=$(mktemp)
    
    # Start background processes
    {
        while true; do
            if [ -f /var/log/sniproxy/https_access.log ]; then
                tail -n 1 /var/log/sniproxy/https_access.log 2>/dev/null | sed 's/^/[SNIProxy] /' || true
            fi
            sleep 1
        done
    } >> "$TEMP_LOG" &
    PID1=$!
    
    {
        docker logs -f --tail 0 coredns-smartdns 2>&1 | sed 's/^/[CoreDNS] /' || true
    } >> "$TEMP_LOG" &
    PID2=$!
    
    {
        docker logs -f --tail 0 doh-nginx 2>&1 | sed 's/^/[Nginx] /' || true
    } >> "$TEMP_LOG" &
    PID3=$!
    
    {
        docker logs -f --tail 0 doh-backend 2>&1 | sed 's/^/[DoH] /' || true
    } >> "$TEMP_LOG" &
    PID4=$!
    
    # Monitor the combined log
    tail -f "$TEMP_LOG" 2>/dev/null &
    TAIL_PID=$!
    
    # Wait for interrupt
    trap "kill $PID1 $PID2 $PID3 $PID4 $TAIL_PID 2>/dev/null; rm -f $TEMP_LOG; exit" INT TERM
    wait
    
    # Cleanup
    kill $PID1 $PID2 $PID3 $PID4 $TAIL_PID 2>/dev/null
    rm -f "$TEMP_LOG"
}

# Function to show connection statistics
show_stats() {
    echo ""
    echo -e "${BLUE}=== Connection Statistics ===${NC}"
    echo ""
    
    # SNIProxy stats
    if [ -f /var/log/sniproxy/https_access.log ]; then
        TOTAL_CONNECTIONS=$(wc -l < /var/log/sniproxy/https_access.log 2>/dev/null || echo "0")
        XBOX_CONNECTIONS=$(grep -i "xbox\|microsoft\|live\.com" /var/log/sniproxy/https_access.log 2>/dev/null | wc -l || echo "0")
        RECENT_CONNECTIONS=$(tail -100 /var/log/sniproxy/https_access.log 2>/dev/null | wc -l || echo "0")
        
        echo -e "${CYAN}SNIProxy Statistics:${NC}"
        echo "  Total connections: $TOTAL_CONNECTIONS"
        echo "  Xbox-related: $XBOX_CONNECTIONS"
        echo "  Recent (last 100): $RECENT_CONNECTIONS"
        echo ""
    else
        echo -e "${YELLOW}⚠ SNIProxy log file not found${NC}"
    fi
    
    # Container stats
    echo -e "${CYAN}Container Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|coredns|doh-nginx|doh-backend" || echo "  No containers running"
    echo ""
    
    # Port 443 status
    echo -e "${CYAN}Port 443 Status:${NC}"
    if ss -tlnp | grep -q ":443"; then
        ss -tlnp | grep ":443" | sed 's/^/  /'
    else
        echo "  ❌ Nothing listening on port 443"
    fi
    echo ""
    
    # DNS resolution test
    echo -e "${CYAN}DNS Resolution Test:${NC}"
    if docker ps | grep -q coredns-smartdns; then
        DNS_RESULT=$(timeout 3 dig @127.0.0.1 xboxlive.com +short 2>/dev/null | head -1 || echo "FAILED")
        echo "  xboxlive.com → $DNS_RESULT"
    else
        echo "  ❌ CoreDNS not running"
    fi
}

# Function to show recent Xbox connections
show_xbox_connections() {
    echo ""
    echo -e "${BLUE}=== Recent Xbox Connections ===${NC}"
    echo ""
    
    if [ -f /var/log/sniproxy/https_access.log ]; then
        echo -e "${CYAN}Last 20 Xbox-related connections:${NC}"
        tail -100 /var/log/sniproxy/https_access.log | grep -iE "xbox|microsoft|live\.com|xboxservices" | tail -20 || echo "  No Xbox connections found"
    else
        echo -e "${YELLOW}⚠ SNIProxy log file not found${NC}"
        echo "Checking journal..."
        journalctl -u sniproxy -n 50 --no-pager | grep -iE "xbox|microsoft|live\.com" | tail -10 || echo "  No Xbox connections in journal"
    fi
}

# Function to show system logs
show_system_logs() {
    echo ""
    echo -e "${BLUE}=== System Logs (Xbox-related) ===${NC}"
    echo ""
    
    echo -e "${CYAN}Recent system logs mentioning Xbox/Microsoft:${NC}"
    journalctl -n 100 --no-pager | grep -iE "xbox|microsoft|live\.com|443|sniproxy" | tail -20 || echo "  No relevant logs found"
    echo ""
    
    echo -e "${CYAN}SNIProxy service status:${NC}"
    systemctl status sniproxy --no-pager -l | head -15 || echo "  Service not found"
}

# Function to monitor port 443 connections
monitor_port_443() {
    echo ""
    echo -e "${BLUE}=== Port 443 Connections (Live) ===${NC}"
    echo ""
    echo -e "${CYAN}Watching for connections on port 443...${NC}"
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        CONNECTIONS=$(ss -tnp | grep ":443" | grep -v "LISTEN" || echo "")
        if [ -n "$CONNECTIONS" ]; then
            echo -e "${GREEN}[$(date +%H:%M:%S)] Active connections:${NC}"
            echo "$CONNECTIONS" | sed 's/^/  /'
            echo ""
        fi
        sleep 2
    done
}

# Function to show DNS query logs
show_dns_logs() {
    echo ""
    echo -e "${BLUE}=== DNS Query Logs ===${NC}"
    echo ""
    
    echo -e "${CYAN}CoreDNS recent queries:${NC}"
    docker logs --tail 50 coredns-smartdns 2>&1 | grep -iE "query|dns|A|AAAA" | tail -20 || echo "  No DNS query logs"
    echo ""
    
    echo -e "${CYAN}DoH backend recent queries:${NC}"
    docker logs --tail 50 doh-backend 2>&1 | grep -iE "query|dns|request" | tail -20 || echo "  No DoH query logs"
}

# Main loop
while true; do
    show_menu
    
    case $choice in
        1)
            monitor_sniproxy_access
            ;;
        2)
            monitor_sniproxy_errors
            ;;
        3)
            monitor_coredns
            ;;
        4)
            monitor_nginx
            ;;
        5)
            monitor_doh_backend
            ;;
        6)
            monitor_all
            ;;
        7)
            show_stats
            read -p "Press Enter to continue..."
            ;;
        8)
            show_xbox_connections
            read -p "Press Enter to continue..."
            ;;
        9)
            show_system_logs
            read -p "Press Enter to continue..."
            ;;
        10)
            monitor_port_443
            ;;
        11)
            show_dns_logs
            read -p "Press Enter to continue..."
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac
done


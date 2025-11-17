#!/bin/bash

# Monitor Xbox activity to see what it's trying to connect to

echo "================================================"
echo "Xbox Activity Monitor"
echo "================================================"
echo ""
echo "This will monitor DNS queries and connections."
echo "Try to connect Xbox NOW and watch what happens!"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""
echo "================================================"
echo ""

# Monitor CoreDNS logs
echo "=== CoreDNS DNS Queries ==="
docker logs -f coredns-smartdns 2>&1 &
COREDNS_PID=$!

# Monitor DoH backend logs
echo "=== DoH Backend Queries ==="
docker logs -f doh-backend 2>&1 | grep -i "xbox\|live\|microsoft" &
DOH_PID=$!

# Monitor sniproxy connections
echo "=== SNIProxy Connections ==="
tail -f /var/log/sniproxy/https_access.log 2>/dev/null | grep -i "xbox\|live\|microsoft" &
SNIPROXY_PID=$!

# Monitor network connections
echo "=== Network Connections to VPS ==="
watch -n 1 'ss -tnp | grep -E "ESTAB|SYN" | grep -E "xbox|live|microsoft|91.235.234.92" | head -20' &
WATCH_PID=$!

# Cleanup on exit
trap "kill $COREDNS_PID $DOH_PID $SNIPROXY_PID $WATCH_PID 2>/dev/null; exit" INT TERM

echo "Monitoring... (Press Ctrl+C to stop)"
wait


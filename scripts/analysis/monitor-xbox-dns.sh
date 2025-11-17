#!/bin/bash

# Monitor Xbox DNS queries in real-time

echo "================================================"
echo "Monitoring Xbox DNS Queries"
echo "================================================"
echo ""
echo "This will show what domains Xbox is querying."
echo "Try to connect Xbox NOW and watch the output!"
echo ""
echo "Press Ctrl+C to stop"
echo ""
echo "================================================"
echo ""

cd /root/doh

# Monitor CoreDNS logs for Xbox-related queries
echo "=== CoreDNS DNS Queries ==="
docker logs -f coredns-smartdns 2>&1 &
COREDNS_PID=$!

# Monitor DoH backend
echo "=== DoH Backend Queries ==="
docker logs -f doh-backend 2>&1 | grep -iE "xbox|live|microsoft|gamepass|discord" &
DOH_PID=$!

# Cleanup
trap "kill $COREDNS_PID $DOH_PID 2>/dev/null; exit" INT TERM

echo "Monitoring... (Press Ctrl+C to stop)"
wait


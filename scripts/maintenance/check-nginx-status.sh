#!/bin/bash

# Quick check of Nginx status and actual errors

echo "=== Nginx Container Status ==="
docker ps -a --filter "name=doh-nginx" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Container State Details ==="
docker inspect doh-nginx --format 'Status: {{.State.Status}}
Running: {{.State.Running}}
RestartCount: {{.RestartCount}}
ExitCode: {{.State.ExitCode}}' 2>/dev/null || echo "Container not found"

echo ""
echo "=== Recent Nginx Logs (last 30 lines) ==="
docker logs doh-nginx --tail 30 2>&1

echo ""
echo "=== Checking for Fatal Errors ==="
docker logs doh-nginx 2>&1 | grep -iE "error|emerg|fatal|failed" | tail -10 || echo "No fatal errors found"

echo ""
echo "=== Testing Nginx on localhost:8443 ==="
timeout 3 curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>&1 | head -3 || echo "❌ Connection failed"

echo ""
echo "=== Checking if port 8443 is listening ==="
ss -tlnp | grep ":8443" || echo "❌ Port 8443 not listening"


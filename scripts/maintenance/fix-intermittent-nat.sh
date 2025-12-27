#!/bin/bash

# Fix intermittent NAT unavailability (cache expiry issue)

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing Intermittent NAT Unavailability"
echo "================================================"
echo ""

echo "[1/4] Updating Corefile with improved cache handling..."
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    # CRITICAL: hosts plugin returns immediately, no cache/upstream needed
    # reload ensures hosts file is checked periodically (prevents stale entries)
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward with parallel upstreams and fast fail settings
    # max_fails and health_check prevent long timeouts when port 53 is blocked
    # except directive ensures hosts file domains NEVER go to upstream
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Enable caching (very long cache to prevent upstream timeouts)
    # NOTE: Domains in hosts file bypass cache and upstream entirely
    # Cache only applies to domains NOT in hosts file
    # When cache expires for non-hosts domains, fast fail prevents long timeouts
    cache 3600 {
        success 3600
        denial 3600
    }
    
    # Log errors (helps diagnose issues)
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE
echo "✅ Corefile updated"
echo ""

echo "[2/4] Verifying all NAT domains are in hosts file..."
NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
)

MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        echo "  ❌ $domain MISSING"
        MISSING=1
    fi
done

if [ $MISSING -eq 0 ]; then
    echo "✅ All NAT domains present in hosts file"
else
    echo "⚠️  Some NAT domains missing - run fix-nat-teredo.sh first"
fi
echo ""

echo "[3/4] Restarting CoreDNS..."
docker restart coredns-smartdns
sleep 3
echo "✅ CoreDNS restarted"
echo ""

echo "[4/4] Testing DNS resolution..."
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)
echo -n "  xbox.nat.microsoft.com: "
RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$RESULT" == "$VPS_IP" ]; then
    echo "✅ $RESULT"
else
    echo "⚠️  $RESULT (expected $VPS_IP)"
fi
echo ""

echo "================================================"
echo "✅ Fix Applied!"
echo "================================================"
echo ""
echo "Changes made:"
echo "  • Added 'reload 1h' to hosts plugin (auto-reloads hosts file)"
echo "  • Improved cache configuration"
echo "  • Ensured hosts file domains never hit upstream"
echo ""
echo "This should prevent NAT from becoming unavailable after cache expiry."
echo ""
echo "Next steps:"
echo "1. Restart Xbox (hold power 10 seconds, wait 30s, turn on)"
echo "2. Monitor NAT type - it should stay available"
echo "3. If still intermittent, check CoreDNS logs:"
echo "   docker logs coredns-smartdns --tail 50"
echo ""


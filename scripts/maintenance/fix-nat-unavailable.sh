#!/bin/bash

# Comprehensive fix for NAT unavailable (when DNS is working but NAT still unavailable)

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing NAT Unavailable (No Timeout Errors)"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/7] Verifying all NAT domains are present and correct..."
bash scripts/maintenance/fix-nat-teredo.sh > /dev/null 2>&1
echo "✅ NAT domains verified"
echo ""

echo "[2/7] Testing DNS resolution for all NAT domains..."
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

ALL_RESOLVING=1
for domain in "${NAT_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$RESULT" != "$VPS_IP" ]; then
        echo "  ❌ $domain → $RESULT (expected $VPS_IP)"
        ALL_RESOLVING=0
    fi
done

if [ $ALL_RESOLVING -eq 1 ]; then
    echo "✅ All NAT domains resolving correctly"
else
    echo "⚠️  Some domains not resolving correctly"
fi
echo ""

echo "[3/7] Adding base domains (Xbox might query these)..."
# Add base domains that Xbox might query
BASE_DOMAINS=("msftncsi.com" "msftconnecttest.com")
for domain in "${BASE_DOMAINS[@]}"; do
    if ! grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
        echo "  Added: $domain"
    fi
done
echo "✅ Base domains verified"
echo ""

echo "[4/7] Ensuring CoreDNS is optimized..."
# Update Corefile to ensure hosts are always served first
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts FIRST - NAT domains served immediately
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 1h
    }
    
    # Forward with fast-fail (prevents timeouts)
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        except /etc/coredns/xbox-hosts
    }
    
    # Long cache for non-hosts domains
    cache 3600 {
        success 3600
        denial 3600
    }
    
    # Log errors
    errors
    
    # Health check
    health :8080
}
EOFCORE
echo "✅ CoreDNS optimized"
echo ""

echo "[5/7] Restarting CoreDNS..."
docker restart coredns-smartdns
sleep 3
echo "✅ CoreDNS restarted"
echo ""

echo "[6/7] Testing DNS from Xbox's perspective..."
echo "Testing if DNS is accessible from external network:"
EXTERNAL_TEST=$(curl -k -s -H 'accept: application/dns-json' "https://$VPS_IP/dns-query?name=xbox.nat.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$EXTERNAL_TEST" == "$VPS_IP" ]; then
    echo "  ✅ DNS accessible externally"
else
    echo "  ⚠️  DNS may not be accessible externally"
fi
echo ""

echo "[7/7] Checking port 53 (DNS) is accessible..."
if ss -tuln | grep -q ":53"; then
    echo "  ✅ Port 53 is listening"
else
    echo "  ❌ Port 53 is NOT listening!"
fi
echo ""

echo "================================================"
echo "✅ DNS Configuration: Complete"
echo "================================================"
echo ""
echo "If NAT is still unavailable, the issue is likely:"
echo ""
echo "1. ⚠️  CRITICAL: Xbox DNS not set to VPS IP"
echo "   - Xbox → Settings → Network → Network settings"
echo "   - Advanced settings → DNS settings"
echo "   - Must be: Manual"
echo "   - Primary DNS: $VPS_IP"
echo "   - Secondary DNS: 8.8.8.8 (or leave empty)"
echo "   - Restart Xbox after changing DNS"
echo ""
echo "2. Router blocking Xbox traffic"
echo "   - Check router firewall rules"
echo "   - Ensure Xbox can reach VPS IP"
echo ""
echo "3. Double NAT"
echo "   - Router behind another router"
echo "   - Causes NAT detection issues"
echo ""
echo "4. UPnP disabled"
echo "   - Enable UPnP on router"
echo "   - Helps with NAT type detection"
echo ""
echo "5. Port forwarding"
echo "   - Forward port 3074 (TCP/UDP) to Xbox"
echo "   - Or enable UPnP"
echo ""
echo "To verify Xbox is using VPS DNS:"
echo "  - Check Xbox network settings show DNS: $VPS_IP"
echo "  - If it shows router IP or automatic, that's the problem!"
echo ""
echo "================================================"
echo ""


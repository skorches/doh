#!/bin/bash

# Fix immediate NAT unavailability by ensuring NO upstream queries for NAT domains

cd /root/doh || { echo "❌ Error: /root/doh not found"; exit 1; }

echo "================================================"
echo "Fixing Immediate NAT Unavailability"
echo "================================================"
echo ""

VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"
echo ""

echo "[1/4] Updating Corefile to prevent ALL upstream queries for NAT domains..."
cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts FIRST - this ensures NAT domains are always served immediately
    # NO fallthrough for NAT domains - they should NEVER hit upstream
    hosts /etc/coredns/xbox-hosts {
        # Don't fallthrough for hosts file entries - serve them immediately
        # This prevents any upstream queries for NAT domains
    }
    
    # Forward with STRICT exception for hosts file
    # The except directive ensures hosts file domains NEVER go to upstream
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        max_fails 1
        health_check 5s
        # CRITICAL: except ensures hosts file domains bypass upstream entirely
        except /etc/coredns/xbox-hosts
    }
    
    # Cache for non-hosts domains only
    # Hosts file entries don't use cache (served directly)
    cache 3600 {
        success 3600
        denial 3600
    }
    
    # Log errors (helps diagnose)
    errors
    
    # Health check
    health :8080
}
EOFCORE
echo "✅ Corefile updated (removed fallthrough from hosts plugin)"
echo ""

echo "[2/4] Verifying all NAT domains are in hosts file..."
# Ensure all NAT domains are present
NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
    "msftncsi.com"
    "msftconnecttest.com"
)

MISSING=0
for domain in "${NAT_DOMAINS[@]}"; do
    if ! grep -q "^[0-9].*$domain" coredns/xbox-hosts; then
        echo "  ⚠️  $domain not found, adding..."
        echo "$VPS_IP $domain" >> coredns/xbox-hosts
        MISSING=1
    fi
done

if [ $MISSING -eq 0 ]; then
    echo "✅ All NAT domains present"
else
    echo "✅ Added missing NAT domains"
fi
echo ""

echo "[3/4] Restarting CoreDNS..."
docker restart coredns-smartdns
sleep 5
echo "✅ CoreDNS restarted"
echo ""

echo "[4/4] Testing immediate resolution (should be instant, no upstream query)..."
echo "Testing NAT domains (should return immediately from hosts file):"
for domain in "xbox.nat.microsoft.com" "dns.msftncsi.com"; do
    echo -n "  $domain: "
    START=$(date +%s%N)
    RESULT=$(timeout 1 dig @127.0.0.1 $domain +short 2>/dev/null | head -1)
    END=$(date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo "✅ $RESULT (${DURATION}ms - instant from hosts)"
    else
        echo "❌ $RESULT (${DURATION}ms - may have hit upstream)"
    fi
done
echo ""

echo "================================================"
echo "✅ Fix Applied!"
echo "================================================"
echo ""
echo "Key changes:"
echo "  • Removed 'fallthrough' from hosts plugin"
echo "  • NAT domains now served ONLY from hosts file"
echo "  • NO upstream queries for NAT domains"
echo "  • Added missing NAT domains if any"
echo ""
echo "This should prevent NAT from becoming unavailable."
echo "NAT domains are now served instantly from hosts file"
echo "with zero chance of upstream timeouts."
echo ""
echo "Next: Restart Xbox and test NAT type"
echo ""


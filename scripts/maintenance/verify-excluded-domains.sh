#!/bin/bash

################################################
# Verify Excluded Domains
# Ensures Call of Duty and 2K Games domains are NOT in hosts file or SNIProxy
# These domains cause disconnections/timeouts when routed through VPS
################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

HOSTS_FILE="coredns/xbox-hosts"
SNIPROXY_CONF="/etc/sniproxy.conf"

# Detect project root
if [ -f "$HOSTS_FILE" ]; then
    PROJECT_ROOT="."
elif [ -f "../../$HOSTS_FILE" ]; then
    PROJECT_ROOT="../.."
    cd "$PROJECT_ROOT"
else
    echo -e "${RED}❌ Cannot find $HOSTS_FILE${NC}"
    echo "Please run this script from the project root or scripts/maintenance directory"
    exit 1
fi

echo "================================================"
echo "Verifying Excluded Domains"
echo "================================================"
echo ""
echo "These domains MUST NOT be in hosts file or SNIProxy:"
echo "  • Call of Duty / Activision (causes timeouts)"
echo "  • 2K Games / NBA 2K (causes matchmaking failures)"
echo ""

# Domains that should NEVER be in hosts file or SNIProxy
EXCLUDED_DOMAINS=(
    # Call of Duty / Activision
    "activision.com"
    "www.activision.com"
    "callofduty.com"
    "www.callofduty.com"
    "profile.callofduty.com"
    "accounts.callofduty.com"
    "s2s.callofduty.com"
    "profile.activision.com"
    "sledgehammergames.com"
    "infinityward.com"
    "treyarch.com"
    "activisionblizzard.com"
    "atvi.com"
    "www.atvi.com"
    "demonware.net"
    "genesis.stun.eu.demonware.net"
    "genesis.stun.us.demonware.net"
    "user-consent.prod.demonware.net"
    "cod-assets.cdn.callofduty.com"
    "prod.cdni.callofduty.com"
    "ingest.datax.activision.com"
    
    # 2K Games / NBA 2K
    "2k.com"
    "www.2k.com"
    "2ksports.com"
    "www.2ksports.com"
    "take2games.com"
    "www.take2games.com"
    "a978.i6g1.akamai.net"
)

ISSUES_FOUND=false

echo "[1/2] Checking hosts file: $HOSTS_FILE"
echo ""

for domain in "${EXCLUDED_DOMAINS[@]}"; do
    if grep -q "^[0-9].*${domain}$" "$HOSTS_FILE" 2>/dev/null; then
        echo -e "  ${RED}❌ FOUND: $domain${NC}"
        ISSUES_FOUND=true
    fi
done

if [ "$ISSUES_FOUND" = false ]; then
    echo -e "  ${GREEN}✅ No excluded domains in hosts file${NC}"
fi

echo ""
echo "[2/2] Checking SNIProxy: $SNIPROXY_CONF"
echo ""

if [ -f "$SNIPROXY_CONF" ]; then
    SNIPROXY_ISSUES=false
    for domain in "${EXCLUDED_DOMAINS[@]}"; do
        # Check for domain patterns in SNIProxy (e.g., .*\.activision\.com$ *)
        ESCAPED_DOMAIN=$(echo "$domain" | sed 's/\./\\./g')
        if grep -qE "(\*\.)?${ESCAPED_DOMAIN}" "$SNIPROXY_CONF" 2>/dev/null; then
            echo -e "  ${RED}❌ FOUND: $domain${NC}"
            SNIPROXY_ISSUES=true
            ISSUES_FOUND=true
        fi
    done
    
    if [ "$SNIPROXY_ISSUES" = false ]; then
        echo -e "  ${GREEN}✅ No excluded domains in SNIProxy${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  SNIProxy config not found (skipped)${NC}"
fi

echo ""
echo "================================================"

if [ "$ISSUES_FOUND" = true ]; then
    echo -e "${RED}❌ ISSUES FOUND!${NC}"
    echo "================================================"
    echo ""
    echo "Excluded domains were found in your configuration."
    echo "This will cause game disconnections and timeouts."
    echo ""
    echo "To fix:"
    echo "  1. Run: bash scripts/maintenance/fix-cod-disconnects.sh"
    echo "  2. Or manually remove the domains from hosts file"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo "================================================"
    echo ""
    echo "No excluded domains found in configuration."
    echo "Call of Duty and 2K Games will connect directly."
    echo ""
    exit 0
fi

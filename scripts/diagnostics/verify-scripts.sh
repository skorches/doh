#!/bin/bash

# Verify all scripts for hardcoded IPs and completeness

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    # Try to detect from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../../docker-compose.yml" ]; then
        cd "$SCRIPT_DIR/../.."
    elif [ -f "./docker-compose.yml" ]; then
        cd .
    else
        echo -e "${RED}❌ doh directory not found${NC}"
        exit 1
    fi
}

echo "================================================"
echo "Script Verification"
echo "================================================"
echo ""

# Check for hardcoded VPS IPs (should use $VPS_IP variable)
echo "[1/3] Checking for hardcoded VPS IPs..."
HARDCODED_VPS_IPS=$(grep -rE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' scripts/ 2>/dev/null | grep -vE '(8\.8\.|1\.1\.1\.|1\.0\.0\.|127\.0\.0\.|0\.0\.0\.)' | grep -v "VPS_IP\|ifconfig\|icanhazip\|ipinfo" || true)

if [ -z "$HARDCODED_VPS_IPS" ]; then
    echo -e "  ${GREEN}✅ No hardcoded VPS IPs found${NC}"
    echo "  All scripts use \$VPS_IP variable (auto-detected)"
else
    echo -e "  ${RED}❌ Found hardcoded VPS IPs:${NC}"
    echo "$HARDCODED_VPS_IPS"
fi
echo ""

# Check template and install.sh fallback domain counts
echo "[2/3] Checking domain template and install.sh consistency..."
TEMPLATE_DOMAINS=0
INSTALL_DOMAINS=0

if [ -f "coredns/xbox-hosts.template" ]; then
    TEMPLATE_DOMAINS=$(grep -cE "^__VPS_IP__ [a-zA-Z0-9.-]+" coredns/xbox-hosts.template)
    echo "  xbox-hosts.template: $TEMPLATE_DOMAINS domains"
else
    echo -e "  ${RED}❌ coredns/xbox-hosts.template not found${NC}"
fi

INSTALL_DOMAINS=$(grep -cE "^\\\$VPS_IP [a-zA-Z0-9.-]+" scripts/setup/install.sh || echo "0")
echo "  install.sh (inline fallback): $INSTALL_DOMAINS domains"

if [ "$TEMPLATE_DOMAINS" -gt 0 ]; then
    if [ "$INSTALL_DOMAINS" -eq "$TEMPLATE_DOMAINS" ]; then
        echo -e "  ${GREEN}✅ Domain counts match${NC}"
    else
        echo -e "  ${YELLOW}⚠️  install.sh fallback has fewer domains than template (expected - template is authoritative)${NC}"
    fi
fi

# Check for critical missing domains in template
CRITICAL_DOMAINS=(
    "xboxgamepass.com"
    "v20.events.data.microsoft.com"
    "account.microsoft.com"
    "licensing.mp.microsoft.com"
    "xbox.com"
)

echo ""
echo "Checking for critical domains in template:"
MISSING_IN_TEMPLATE=0
for domain in "${CRITICAL_DOMAINS[@]}"; do
    if [ -f "coredns/xbox-hosts.template" ] && grep -q "__VPS_IP__ $domain" coredns/xbox-hosts.template; then
        echo -e "  ${GREEN}✅ $domain${NC}"
    else
        echo -e "  ${RED}❌ $domain MISSING${NC}"
        MISSING_IN_TEMPLATE=$((MISSING_IN_TEMPLATE + 1))
    fi
done
echo ""

# Check script syntax
echo "[3/3] Checking script syntax..."
SCRIPTS=(
    "scripts/install.sh"
    "scripts/setup/install.sh"
    "scripts/setup/update.sh"
    "scripts/setup/cleanup.sh"
    "scripts/setup/setup-letsencrypt.sh"
    "scripts/maintenance/regenerate-hosts.sh"
    "scripts/maintenance/verify-xbox-services.sh"
    "scripts/maintenance/fix-xbox-nat-unavailable.sh"
    "scripts/maintenance/fix-cod-disconnects.sh"
    "scripts/diagnostics/compare-public-dns.sh"
    "scripts/diagnostics/fix-sniproxy-ipv6-unreachable.sh"
    "scripts/diagnostics/verify-excluded-domains.sh"
    "scripts/diagnostics/verify-scripts.sh"
)

SYNTAX_ERRORS=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $script syntax OK${NC}"
        else
            echo -e "  ${RED}❌ $script has syntax errors${NC}"
            bash -n "$script" 2>&1 | head -3
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  $script not found (optional)${NC}"
    fi
done
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ -z "$HARDCODED_VPS_IPS" ] && [ $MISSING_IN_TEMPLATE -eq 0 ] && [ $SYNTAX_ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All scripts verified!${NC}"
    echo ""
    echo "✅ No hardcoded VPS IPs"
    echo "✅ All critical domains present in template"
    echo "✅ All scripts have valid syntax"
    echo ""
    echo "Scripts are ready for public release!"
else
    echo -e "${YELLOW}⚠️  Issues found:${NC}"
    if [ -n "$HARDCODED_VPS_IPS" ]; then
        echo "  • Hardcoded VPS IPs found"
    fi
    if [ $MISSING_IN_TEMPLATE -gt 0 ]; then
        echo "  • $MISSING_IN_TEMPLATE critical domain(s) missing in template"
    fi
    if [ $SYNTAX_ERRORS -gt 0 ]; then
        echo "  • $SYNTAX_ERRORS script(s) have syntax errors"
    fi
fi
echo ""


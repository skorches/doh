#!/bin/bash

# Verify all scripts for hardcoded IPs and completeness

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd /home/wars09/Cursor/doh 2>/dev/null || cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
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

# Check if install.sh and regenerate-hosts.sh have same domains
echo "[2/3] Comparing install.sh and regenerate-hosts.sh domains..."
INSTALL_DOMAINS=$(grep -E "^\$VPS_IP [a-zA-Z0-9.-]+" scripts/setup/install.sh | wc -l)
REGENERATE_DOMAINS=$(grep -E "^\$VPS_IP [a-zA-Z0-9.-]+" scripts/maintenance/regenerate-hosts.sh | wc -l)

echo "  install.sh: $INSTALL_DOMAINS domains"
echo "  regenerate-hosts.sh: $REGENERATE_DOMAINS domains"

if [ "$INSTALL_DOMAINS" -eq "$REGENERATE_DOMAINS" ]; then
    echo -e "  ${GREEN}✅ Domain counts match${NC}"
else
    echo -e "  ${YELLOW}⚠️  Domain counts differ (may be intentional)${NC}"
fi

# Check for critical missing domains
CRITICAL_DOMAINS=(
    "xboxgamepass.com"
    "v20.events.data.microsoft.com"
    "account.microsoft.com"
    "licensing.mp.microsoft.com"
    "xbox.com"
)

echo ""
echo "Checking for critical domains in install.sh:"
MISSING_IN_INSTALL=0
for domain in "${CRITICAL_DOMAINS[@]}"; do
    if grep -q "\$VPS_IP $domain" scripts/setup/install.sh; then
        echo -e "  ${GREEN}✅ $domain${NC}"
    else
        echo -e "  ${RED}❌ $domain MISSING${NC}"
        MISSING_IN_INSTALL=$((MISSING_IN_INSTALL + 1))
    fi
done
echo ""

# Check script syntax
echo "[3/3] Checking script syntax..."
SCRIPTS=(
    "scripts/setup/install.sh"
    "scripts/setup/cleanup.sh"
    "scripts/setup/setup-letsencrypt.sh"
    "scripts/maintenance/regenerate-hosts.sh"
    "scripts/maintenance/verify-xbox-services.sh"
    "scripts/maintenance/fix-xbox-nat-unavailable.sh"
)

SYNTAX_ERRORS=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>&1 | grep -q "error"; then
            echo -e "  ${RED}❌ $script has syntax errors${NC}"
            bash -n "$script" 2>&1 | head -3
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        else
            echo -e "  ${GREEN}✅ $script syntax OK${NC}"
        fi
    else
        echo -e "  ${RED}❌ $script not found${NC}"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ -z "$HARDCODED_VPS_IPS" ] && [ $MISSING_IN_INSTALL -eq 0 ] && [ $SYNTAX_ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All scripts verified!${NC}"
    echo ""
    echo "✅ No hardcoded VPS IPs"
    echo "✅ All critical domains present"
    echo "✅ All scripts have valid syntax"
    echo ""
    echo "Scripts are ready for public release!"
else
    echo -e "${YELLOW}⚠️  Issues found:${NC}"
    if [ -n "$HARDCODED_VPS_IPS" ]; then
        echo "  • Hardcoded VPS IPs found"
    fi
    if [ $MISSING_IN_INSTALL -gt 0 ]; then
        echo "  • $MISSING_IN_INSTALL critical domain(s) missing in install.sh"
    fi
    if [ $SYNTAX_ERRORS -gt 0 ]; then
        echo "  • $SYNTAX_ERRORS script(s) have syntax errors"
    fi
fi
echo ""


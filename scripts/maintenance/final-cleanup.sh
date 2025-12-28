#!/bin/bash

# Final cleanup - remove all redundant/one-time scripts for public release

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

echo "================================================"
echo "Final Cleanup for Public Release"
echo "================================================"
echo ""
echo "This will remove all redundant/one-time scripts."
echo "Only essential scripts will remain."
echo ""

# Scripts to REMOVE (redundant/one-time fixes)
REMOVE_SCRIPTS=(
    "scripts/maintenance/check-nginx-status.sh"
    "scripts/maintenance/cleanup-config.sh"
    "scripts/maintenance/diagnose-nat-detection.sh"
    "scripts/maintenance/ensure-all-services.sh"
    "scripts/maintenance/fix-doh-405.sh"
    "scripts/maintenance/fix-intermittent-nat.sh"
    "scripts/maintenance/fix-nat-teredo.sh"
    "scripts/maintenance/fix-nat-unavailable.sh"
    "scripts/maintenance/fix-nginx-sniproxy.sh"
    "scripts/maintenance/fix-nginx-ssl-key.sh"
    "scripts/maintenance/minimal-cleanup.sh"
    "scripts/maintenance/optimize-for-stability.sh"
    "scripts/maintenance/verify-all-domains.sh"
    "scripts/maintenance/verify.sh"
)

# Essential scripts to KEEP
KEEP_SCRIPTS=(
    "scripts/setup/install.sh"
    "scripts/setup/cleanup.sh"
    "scripts/setup/setup-letsencrypt.sh"
    "scripts/maintenance/regenerate-hosts.sh"
    "scripts/maintenance/verify-xbox-services.sh"
    "scripts/maintenance/fix-xbox-nat-unavailable.sh"
)

echo "Scripts to remove:"
REMOVE_COUNT=0
for script in "${REMOVE_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${YELLOW}❌ $script${NC}"
        REMOVE_COUNT=$((REMOVE_COUNT + 1))
    fi
done

if [ $REMOVE_COUNT -eq 0 ]; then
    echo -e "  ${GREEN}✅ No redundant scripts found${NC}"
    echo ""
    echo "All scripts are already minimal!"
    exit 0
fi

echo ""
echo "Essential scripts to keep:"
for script in "${KEEP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${GREEN}✅ $script${NC}"
    fi
done
echo ""

read -p "Remove $REMOVE_COUNT redundant script(s)? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "Removing redundant scripts..."
REMOVED=0
for script in "${REMOVE_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        rm -f "$script"
        echo -e "  ${GREEN}✅ Removed: $script${NC}"
        REMOVED=$((REMOVED + 1))
    fi
done

echo ""
echo "Removing backup files..."
find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | while read file; do
    rm -f "$file"
    echo -e "  ${GREEN}✅ Removed: $file${NC}"
done

echo ""
echo "Removing temporary files..."
find . -name "*.tmp" -o -name "*.log" 2>/dev/null | grep -v "archive" | while read file; do
    rm -f "$file"
    echo -e "  ${GREEN}✅ Removed: $file${NC}"
done

echo ""
echo "================================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "Removed $REMOVED redundant script(s)"
echo ""
echo "Final minimal structure:"
echo ""
echo "  ${GREEN}Setup (3 scripts):${NC}"
echo "    • install.sh - Complete one-time installer (all optimizations included)"
echo "    • cleanup.sh - Complete cleanup"
echo "    • setup-letsencrypt.sh - SSL certificate setup"
echo ""
echo "  ${GREEN}Maintenance (3 scripts):${NC}"
echo "    • regenerate-hosts.sh - Regenerate hosts file"
echo "    • verify-xbox-services.sh - Comprehensive verification (includes domain check & auto-start)"
echo "    • fix-xbox-nat-unavailable.sh - Fix NAT issues (includes DoH 405 fix)"
echo ""
echo "All functionality consolidated into 6 essential scripts!"
echo "Ready for public release."
echo ""


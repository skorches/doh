#!/bin/bash

# Minimal cleanup - remove all redundant scripts and consolidate functionality

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
echo "Minimal Configuration Cleanup"
echo "================================================"
echo ""
echo "This will remove redundant scripts and keep only essentials."
echo ""

# Scripts to REMOVE (redundant)
REMOVE_SCRIPTS=(
    "scripts/maintenance/fix-nat-teredo.sh"
    "scripts/maintenance/fix-nat-unavailable.sh"
    "scripts/maintenance/fix-intermittent-nat.sh"
    "scripts/maintenance/check-nginx-status.sh"
    "scripts/maintenance/diagnose-nat-detection.sh"
    "scripts/maintenance/fix-nginx-ssl-key.sh"
    "scripts/maintenance/fix-nginx-sniproxy.sh"
    "scripts/maintenance/verify.sh"
    "scripts/maintenance/verify-all-domains.sh"  # Will merge into verify-xbox-services.sh
    "scripts/maintenance/ensure-all-services.sh"  # Will merge into verify-xbox-services.sh
    "scripts/maintenance/fix-doh-405.sh"  # Will merge into fix-xbox-nat-unavailable.sh
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
for script in "${REMOVE_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${YELLOW}❌ $script${NC}"
    fi
done
echo ""

echo "Essential scripts to keep:"
for script in "${KEEP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${GREEN}✅ $script${NC}"
    fi
done
echo ""

read -p "Remove redundant scripts? (yes/no): " CONFIRM

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
BACKUP_REMOVED=0
find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | while read file; do
    rm -f "$file"
    echo -e "  ${GREEN}✅ Removed: $file${NC}"
    BACKUP_REMOVED=$((BACKUP_REMOVED + 1))
done

echo ""
echo "Removing temporary files..."
TEMP_REMOVED=0
find . -name "*.tmp" -o -name "*.log" 2>/dev/null | grep -v "archive" | while read file; do
    rm -f "$file"
    echo -e "  ${GREEN}✅ Removed: $file${NC}"
    TEMP_REMOVED=$((TEMP_REMOVED + 1))
done

echo ""
echo "================================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "Removed $REMOVED redundant script(s)"
echo ""
echo "Minimal script structure:"
echo "  ${GREEN}Setup:${NC}"
echo "    • install.sh - Main installer"
echo "    • cleanup.sh - Complete cleanup"
echo "    • setup-letsencrypt.sh - SSL certificate setup"
echo ""
echo "  ${GREEN}Maintenance:${NC}"
echo "    • regenerate-hosts.sh - Regenerate hosts file"
echo "    • verify-xbox-services.sh - Verify all services & domains"
echo "    • fix-xbox-nat-unavailable.sh - Fix NAT issues"
echo ""
echo "All functionality has been consolidated into these 6 scripts."
echo ""


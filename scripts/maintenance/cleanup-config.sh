#!/bin/bash

# Cleanup and organize configuration files

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh 2>/dev/null || cd "$HOME/doh" 2>/dev/null || {
    echo -e "${RED}❌ doh directory not found${NC}"
    exit 1
}

echo "================================================"
echo "Configuration Cleanup"
echo "================================================"
echo ""

# Scripts to keep (essential)
KEEP_SCRIPTS=(
    "scripts/setup/install.sh"
    "scripts/setup/cleanup.sh"
    "scripts/setup/setup-letsencrypt.sh"
    "scripts/maintenance/regenerate-hosts.sh"
    "scripts/maintenance/verify-xbox-services.sh"
    "scripts/maintenance/verify-all-domains.sh"
    "scripts/maintenance/fix-doh-405.sh"
    "scripts/maintenance/ensure-all-services.sh"
)

# Scripts that are redundant (can be removed)
REDUNDANT_SCRIPTS=(
    "scripts/maintenance/fix-nat-teredo.sh"          # Merged into fix-xbox-nat-unavailable.sh
    "scripts/maintenance/fix-nat-unavailable.sh"    # Merged into fix-xbox-nat-unavailable.sh
    "scripts/maintenance/fix-intermittent-nat.sh"   # Merged into fix-xbox-nat-unavailable.sh
    "scripts/maintenance/check-nginx-status.sh"     # Functionality in verify-xbox-services.sh
    "scripts/maintenance/diagnose-nat-detection.sh" # Functionality in verify-xbox-services.sh
    "scripts/maintenance/fix-nginx-ssl-key.sh"      # One-time fix, can be removed
    "scripts/maintenance/fix-nginx-sniproxy.sh"      # One-time fix, can be removed
    "scripts/maintenance/verify.sh"                  # Replaced by verify-xbox-services.sh
)

echo "[1/4] Identifying redundant scripts..."
REDUNDANT_FOUND=0
for script in "${REDUNDANT_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${YELLOW}⚠️  $script${NC}"
        REDUNDANT_FOUND=$((REDUNDANT_FOUND + 1))
    fi
done

if [ $REDUNDANT_FOUND -eq 0 ]; then
    echo -e "  ${GREEN}✅ No redundant scripts found${NC}"
else
    echo -e "  ${YELLOW}Found $REDUNDANT_FOUND redundant script(s)${NC}"
fi
echo ""

echo "[2/4] Checking for backup files..."
BACKUP_FILES=$(find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | wc -l)
if [ "$BACKUP_FILES" -gt 0 ]; then
    echo -e "  ${YELLOW}Found $BACKUP_FILES backup file(s)${NC}"
    find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | head -10
else
    echo -e "  ${GREEN}✅ No backup files found${NC}"
fi
echo ""

echo "[3/4] Checking for temporary files..."
TEMP_FILES=$(find . -name "*.tmp" -o -name "*.log" -o -name ".DS_Store" 2>/dev/null | grep -v "archive" | wc -l)
if [ "$TEMP_FILES" -gt 0 ]; then
    echo -e "  ${YELLOW}Found $TEMP_FILES temporary file(s)${NC}"
    find . -name "*.tmp" -o -name "*.log" -o -name ".DS_Store" 2>/dev/null | grep -v "archive" | head -10
else
    echo -e "  ${GREEN}✅ No temporary files found${NC}"
fi
echo ""

echo "[4/4] Summary of essential files..."
echo ""
echo "Essential scripts:"
for script in "${KEEP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${GREEN}✅ $script${NC}"
    else
        echo -e "  ${RED}❌ $script (missing)${NC}"
    fi
done
echo ""

echo "================================================"
echo "Cleanup Options"
echo "================================================"
echo ""
echo "What would you like to do?"
echo ""
echo "1. Remove redundant scripts (recommended)"
echo "2. Remove backup files"
echo "3. Remove temporary files"
echo "4. Do all of the above"
echo "5. Just show what would be removed (dry run)"
echo "6. Cancel"
echo ""
read -p "Enter choice (1-6): " CHOICE

case $CHOICE in
    1)
        echo ""
        echo "Removing redundant scripts..."
        for script in "${REDUNDANT_SCRIPTS[@]}"; do
            if [ -f "$script" ]; then
                rm -f "$script"
                echo -e "  ${GREEN}✅ Removed: $script${NC}"
            fi
        done
        ;;
    2)
        echo ""
        echo "Removing backup files..."
        find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | while read file; do
            rm -f "$file"
            echo -e "  ${GREEN}✅ Removed: $file${NC}"
        done
        ;;
    3)
        echo ""
        echo "Removing temporary files..."
        find . -name "*.tmp" -o -name "*.log" -o -name ".DS_Store" 2>/dev/null | grep -v "archive" | while read file; do
            rm -f "$file"
            echo -e "  ${GREEN}✅ Removed: $file${NC}"
        done
        ;;
    4)
        echo ""
        echo "Removing redundant scripts..."
        for script in "${REDUNDANT_SCRIPTS[@]}"; do
            if [ -f "$script" ]; then
                rm -f "$script"
                echo -e "  ${GREEN}✅ Removed: $script${NC}"
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
        find . -name "*.tmp" -o -name "*.log" -o -name ".DS_Store" 2>/dev/null | grep -v "archive" | while read file; do
            rm -f "$file"
            echo -e "  ${GREEN}✅ Removed: $file${NC}"
        done
        ;;
    5)
        echo ""
        echo "=== DRY RUN - No files will be removed ==="
        echo ""
        echo "Redundant scripts that would be removed:"
        for script in "${REDUNDANT_SCRIPTS[@]}"; do
            if [ -f "$script" ]; then
                echo "  - $script"
            fi
        done
        echo ""
        echo "Backup files that would be removed:"
        find . -name "*.backup.*" -o -name "*.bak" -o -name "*~" 2>/dev/null | head -20
        echo ""
        echo "Temporary files that would be removed:"
        find . -name "*.tmp" -o -name "*.log" -o -name ".DS_Store" 2>/dev/null | grep -v "archive" | head -20
        exit 0
        ;;
    6)
        echo "Cleanup cancelled"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo "================================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "Essential scripts remaining:"
for script in "${KEEP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  ${GREEN}✅ $script${NC}"
    fi
done
echo ""


#!/bin/bash

# Fix common Git issues before pushing

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Fix Git Issues"
echo "================================================"
echo ""

cd /home/wars09/Cursor/doh

# Check if git repo
if [ ! -d .git ]; then
    echo -e "${YELLOW}Not a git repository. Initializing...${NC}"
    git init
    git remote add origin $(git remote get-url origin 2>/dev/null || echo "YOUR_REPO_URL")
fi

# Check .gitignore
if [ ! -f .gitignore ]; then
    echo -e "${YELLOW}Creating .gitignore...${NC}"
    cat > .gitignore << 'EOF'
# SSL certificates
ssl/*.crt
ssl/*.key
ssl/*.pem

# Logs
*.log
logs/

# Capture files
*.pcap
*.pcapng
wireshark-analysis-*/
xbox-capture-*/

# Backups
*.backup*
*.bak

# Archive
archive/

# OS files
.DS_Store
Thumbs.db

# Environment
.env
EOF
    echo -e "${GREEN}✅ .gitignore created${NC}"
fi

# Remove sensitive files from git
echo ""
echo -e "${YELLOW}Removing sensitive files from git...${NC}"
git rm --cached ssl/*.crt ssl/*.key ssl/*.pem 2>/dev/null || true
git rm --cached coredns/xbox-hosts 2>/dev/null || true
git rm --cached *.pcap *.pcapng 2>/dev/null || true

# Check for large files
echo ""
echo -e "${YELLOW}Checking for large files...${NC}"
LARGE_FILES=$(find . -type f -size +10M -not -path "./.git/*" -not -path "./archive/*" 2>/dev/null | head -10)
if [ ! -z "$LARGE_FILES" ]; then
    echo -e "${RED}Large files found (>10MB):${NC}"
    echo "$LARGE_FILES"
    echo ""
    echo "Consider moving to archive/ or .gitignore"
else
    echo -e "${GREEN}✅ No large files found${NC}"
fi

# Check git status
echo ""
echo -e "${YELLOW}Git status:${NC}"
git status --short | head -20

echo ""
echo "================================================"
echo "Next steps:"
echo ""
echo "1. Review changes:"
echo "   git status"
echo ""
echo "2. Add files:"
echo "   git add ."
echo ""
echo "3. Commit:"
echo "   git commit -m 'Clean up and organize project'"
echo ""
echo "4. Push:"
echo "   git push origin main"
echo ""
echo "If you get errors, try:"
echo "   git push -f origin main  # Force push (be careful!)"
echo ""
echo "================================================"


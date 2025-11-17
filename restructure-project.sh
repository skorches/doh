#!/bin/bash

# Restructure the project for better organization

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Restructuring Project"
echo "================================================"
echo ""

cd /home/wars09/Cursor/doh

# Create directory structure
echo -e "${YELLOW}[1/6] Creating directory structure...${NC}"
mkdir -p scripts/{setup,maintenance,analysis}
mkdir -p docs
mkdir -p config
mkdir -p archive

echo -e "${GREEN}✅ Directories created${NC}"

# Copy essential config files (keep originals for compatibility)
echo ""
echo -e "${YELLOW}[2/6] Organizing configuration files...${NC}"
[ -f docker-compose.yml ] && cp docker-compose.yml config/ 2>/dev/null || true
[ -d coredns ] && cp -r coredns config/ 2>/dev/null || true
[ -d nginx ] && cp -r nginx config/ 2>/dev/null || true
[ -d ssl ] && cp -r ssl config/ 2>/dev/null || true
[ -f env.example ] && cp env.example config/ 2>/dev/null || true

echo -e "${GREEN}✅ Config files organized${NC}"

# Move essential scripts
echo ""
echo -e "${YELLOW}[3/6] Organizing scripts...${NC}"

# Setup scripts
mv deploy-smartdns-complete.sh scripts/setup/ 2>/dev/null || true
mv setup-letsencrypt.sh scripts/setup/ 2>/dev/null || true
mv install-sniproxy.sh scripts/setup/ 2>/dev/null || true

# Maintenance scripts
mv optimize-xbox-hosts.sh scripts/maintenance/ 2>/dev/null || true
mv add-wireshark-domains-filtered.sh scripts/maintenance/ 2>/dev/null || true
mv fix-haproxy-config.sh scripts/maintenance/ 2>/dev/null || true
mv fix-coredns-forward.sh scripts/maintenance/ 2>/dev/null || true

# Analysis scripts
mv analyze-wireshark.sh scripts/analysis/ 2>/dev/null || true
mv capture-xbox-traffic.sh scripts/analysis/ 2>/dev/null || true
mv diagnose-xbox-issue.sh scripts/analysis/ 2>/dev/null || true

echo -e "${GREEN}✅ Scripts organized${NC}"

# Move documentation
echo ""
echo -e "${YELLOW}[4/6] Organizing documentation...${NC}"
mv README.md docs/ 2>/dev/null || true
mv SMART_DNS_SETUP.md docs/ 2>/dev/null || true
mv DOMAIN_SETUP_GUIDE.md docs/ 2>/dev/null || true
mv XBOX_SETUP_GUIDE.md docs/ 2>/dev/null || true
mv TROUBLESHOOTING.md docs/ 2>/dev/null || true
mv *.md docs/ 2>/dev/null || true
mv *.txt docs/ 2>/dev/null || true

echo -e "${GREEN}✅ Documentation organized${NC}"

# Archive old/obsolete files
echo ""
echo -e "${YELLOW}[5/6] Archiving obsolete files...${NC}"

# Archive old scripts
mv deploy-doh-443.sh archive/ 2>/dev/null || true
mv deploy-doh-443-simple.sh archive/ 2>/dev/null || true
mv deploy-keenetic-doh.sh archive/ 2>/dev/null || true
mv deploy.sh archive/ 2>/dev/null || true
mv fix-*.sh archive/ 2>/dev/null || true
mv add-*.sh archive/ 2>/dev/null || true
mv setup-*.sh archive/ 2>/dev/null || true
mv integrate-*.sh archive/ 2>/dev/null || true
mv restore-*.sh archive/ 2>/dev/null || true
mv test-*.sh archive/ 2>/dev/null || true
mv check-*.sh archive/ 2>/dev/null || true
mv verify-*.sh archive/ 2>/dev/null || true
mv switch-*.sh archive/ 2>/dev/null || true
mv update-*.sh archive/ 2>/dev/null || true
mv enable-*.sh archive/ 2>/dev/null || true
mv optimize-for-xbox.sh archive/ 2>/dev/null || true
mv monitor-*.sh archive/ 2>/dev/null || true
mv copy-to-vps.sh archive/ 2>/dev/null || true
mv cleanup.sh archive/ 2>/dev/null || true
mv COMPLETE_CLEANUP.sh archive/ 2>/dev/null || true
mv docker-compose-working.yml archive/ 2>/dev/null || true
mv Makefile archive/ 2>/dev/null || true
mv wireguard archive/ 2>/dev/null || true
mv pap.pcapng archive/ 2>/dev/null || true

echo -e "${GREEN}✅ Obsolete files archived${NC}"

# Create new README
echo ""
echo -e "${YELLOW}[6/6] Creating new README...${NC}"

cat > README.md << 'EOF'
# Xbox Smart DNS + DoH Server

DNS over HTTPS (DoH) server with Smart DNS proxy for Xbox Live connectivity in geo-blocked regions.

## 🎯 What This Does

- **DoH Server**: Encrypted DNS queries over HTTPS
- **Smart DNS**: Returns VPS IP for Xbox/Discord domains (bypasses geo-blocks)
- **SNI Proxy**: Forwards Xbox traffic to real servers through your VPS
- **Bypass ISP Blocks**: Works even when ISP blocks Cloudflare/AWS

## 📁 Project Structure

```
.
├── config/              # Configuration files
│   ├── docker-compose.yml
│   ├── coredns/         # CoreDNS config
│   ├── nginx/           # Nginx config
│   └── ssl/             # SSL certificates
├── scripts/
│   ├── setup/           # Initial setup scripts
│   ├── maintenance/     # Maintenance scripts
│   └── analysis/        # Traffic analysis tools
├── docs/                # Documentation
└── archive/             # Old/obsolete files
```

## 🚀 Quick Start

### 1. Initial Setup

```bash
# On your VPS
cd /root/doh
./scripts/setup/deploy-smartdns-complete.sh
```

### 2. Configure Router

**Keenetic Router:**
- Internet → DNS → Use DNS over HTTPS (DoH)
- URL: `https://bypass.440.info/dns-query`

### 3. Test

```bash
# Test Smart DNS
curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'
# Should return your VPS IP
```

## 📚 Documentation

- [Smart DNS Setup Guide](docs/SMART_DNS_SETUP.md)
- [Xbox Configuration](docs/XBOX_SETUP_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## 🔧 Maintenance

### Add Xbox Domains from Wireshark

```bash
# Analyze Wireshark capture
./scripts/analysis/analyze-wireshark.sh capture.pcap

# Add domains
./scripts/maintenance/add-wireshark-domains-filtered.sh wireshark-analysis-*/xbox-domains.txt
```

### Optimize Hosts File

```bash
./scripts/maintenance/optimize-xbox-hosts.sh
```

## 🛠️ Services

- **Nginx**: DoH frontend (port 8443 internal)
- **DoH Backend**: satishweb/doh-server (port 8053)
- **CoreDNS**: Smart DNS layer (returns VPS IP for Xbox domains)
- **Cloudflared**: Upstream DoH (port 5053)
- **SNIProxy**: SNI proxy for Xbox traffic (port 443)

## 📝 License

MIT
EOF

echo -e "${GREEN}✅ README created${NC}"

# Create .gitignore
cat > .gitignore << 'EOF'
# Config files with sensitive data
config/ssl/*
config/coredns/xbox-hosts
config/.env

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

# Archive (old files)
archive/

# OS files
.DS_Store
Thumbs.db
EOF

echo ""
echo "================================================"
echo -e "${GREEN}✅ Restructuring Complete!${NC}"
echo "================================================"
echo ""
echo "New structure:"
echo "  📁 config/     - Configuration files"
echo "  📁 scripts/    - Organized scripts"
echo "  📁 docs/       - Documentation"
echo "  📁 archive/    - Old files"
echo ""
echo "Next steps:"
echo "  1. Review the structure"
echo "  2. Update paths in scripts if needed"
echo "  3. Commit to git:"
echo "     git add ."
echo "     git commit -m 'Restructure project'"
echo "     git push"
echo ""
echo "================================================"


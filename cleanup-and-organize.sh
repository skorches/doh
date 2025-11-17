#!/bin/bash

# Clean up and organize project - keeps working files in place

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================"
echo "Clean Up and Organize Project"
echo "================================================"
echo ""

cd /home/wars09/Cursor/doh

# Create directories
echo -e "${YELLOW}[1/5] Creating directories...${NC}"
mkdir -p scripts/{setup,maintenance,analysis}
mkdir -p docs
mkdir -p archive

echo -e "${GREEN}✅ Directories created${NC}"

# Archive obsolete scripts (keep working ones)
echo ""
echo -e "${YELLOW}[2/5] Archiving obsolete files...${NC}"

# Archive old/duplicate scripts
for file in \
    deploy-doh-443.sh deploy-doh-443-simple.sh deploy-keenetic-doh.sh \
    deploy.sh fix-containers.sh fix-dns-proxy.sh fix-haproxy-error.sh \
    fix-port-conflict.sh fix-ssl-complete.sh fix-xbox-complete.sh \
    fix-xbox-stability.sh integrate-coredns-smartdns.sh \
    integrate-doh-openvpn.sh restore-and-setup-smartdns.sh \
    setup-nginx-smartdns.sh setup-smartdns-haproxy-fixed.sh \
    setup-openvpn.sh setup-vpn.sh setup-xbox-proxy.sh \
    test-dns.sh test-ipv6-home.sh test-keenetic.sh test-smartdns.sh \
    test-smartdns-from-pc.sh check-ipv6.sh check-openvpn.sh \
    verify-ipv6-ready.sh switch-upstream-dns.sh update-upstream.sh \
    enable-ipv6.sh optimize-for-xbox.sh monitor-xbox-activity.sh \
    copy-to-vps.sh cleanup.sh COMPLETE_CLEANUP.sh \
    add-captured-domains.sh add-discord-support.sh add-dns-cache.sh \
    add-https.sh add-wireshark-domains.sh capture-xbox-traffic.sh \
    diagnose-xbox-issue.sh; do
    [ -f "$file" ] && mv "$file" archive/ 2>/dev/null || true
done

# Archive old docs
for file in \
    ALTERNATIVES.md DNS_PROVIDERS.md EXISTING_OPENVPN.md \
    GLINET_SETUP.md ISP_DNS_BLOCKING.md KEENETIC_SETUP.md \
    MANUAL_CLEANUP_STEPS.md PULL_INSTRUCTIONS.txt QUICKSTART.md \
    RUSSIA_SETUP.md START_HERE.md SUMMARY.txt YOUR_SITUATION.md \
    VPN_SETUP_GUIDE.md INDEX.md SMART_DNS_QUICKSTART.txt; do
    [ -f "$file" ] && mv "$file" docs/ 2>/dev/null || true
done

# Archive other files
[ -f docker-compose-working.yml ] && mv docker-compose-working.yml archive/ 2>/dev/null || true
[ -f Makefile ] && mv Makefile archive/ 2>/dev/null || true
[ -d wireguard ] && mv wireguard archive/ 2>/dev/null || true
[ -f pap.pcapng ] && mv pap.pcapng archive/ 2>/dev/null || true

echo -e "${GREEN}✅ Obsolete files archived${NC}"

# Organize essential scripts
echo ""
echo -e "${YELLOW}[3/5] Organizing essential scripts...${NC}"

# Setup scripts
[ -f deploy-smartdns-complete.sh ] && mv deploy-smartdns-complete.sh scripts/setup/ 2>/dev/null || true
[ -f setup-letsencrypt.sh ] && mv setup-letsencrypt.sh scripts/setup/ 2>/dev/null || true
[ -f install-sniproxy.sh ] && mv install-sniproxy.sh scripts/setup/ 2>/dev/null || true

# Maintenance scripts
[ -f optimize-xbox-hosts.sh ] && mv optimize-xbox-hosts.sh scripts/maintenance/ 2>/dev/null || true
[ -f add-wireshark-domains-filtered.sh ] && mv add-wireshark-domains-filtered.sh scripts/maintenance/ 2>/dev/null || true
[ -f fix-haproxy-config.sh ] && mv fix-haproxy-config.sh scripts/maintenance/ 2>/dev/null || true
[ -f fix-coredns-forward.sh ] && mv fix-coredns-forward.sh scripts/maintenance/ 2>/dev/null || true

# Analysis scripts
[ -f analyze-wireshark.sh ] && mv analyze-wireshark.sh scripts/analysis/ 2>/dev/null || true

echo -e "${GREEN}✅ Scripts organized${NC}"

# Organize documentation
echo ""
echo -e "${YELLOW}[4/5] Organizing documentation...${NC}"

[ -f README.md ] && mv README.md docs/README-OLD.md 2>/dev/null || true
[ -f SMART_DNS_SETUP.md ] && mv SMART_DNS_SETUP.md docs/ 2>/dev/null || true
[ -f DOMAIN_SETUP_GUIDE.md ] && mv DOMAIN_SETUP_GUIDE.md docs/ 2>/dev/null || true
[ -f XBOX_SETUP_GUIDE.md ] && mv XBOX_SETUP_GUIDE.md docs/ 2>/dev/null || true
[ -f TROUBLESHOOTING.md ] && mv TROUBLESHOOTING.md docs/ 2>/dev/null || true

echo -e "${GREEN}✅ Documentation organized${NC}"

# Create new README
echo ""
echo -e "${YELLOW}[5/5] Creating new README...${NC}"

cat > README.md << 'EOF'
# Xbox Smart DNS + DoH Server

DNS over HTTPS (DoH) server with Smart DNS proxy for Xbox Live connectivity in geo-blocked regions.

## 🎯 Features

- **DoH Server**: Encrypted DNS queries over HTTPS
- **Smart DNS**: Returns VPS IP for Xbox/Discord domains (bypasses geo-blocks)
- **SNI Proxy**: Forwards Xbox traffic to real servers through your VPS
- **Bypass ISP Blocks**: Works even when ISP blocks Cloudflare/AWS

## 📁 Project Structure

```
.
├── docker-compose.yml      # Main Docker Compose config
├── coredns/                # CoreDNS Smart DNS config
├── nginx/                  # Nginx DoH frontend config
├── ssl/                    # SSL certificates
├── scripts/
│   ├── setup/             # Initial setup scripts
│   ├── maintenance/       # Maintenance scripts
│   └── analysis/          # Traffic analysis tools
├── docs/                   # Documentation
└── archive/                # Old/obsolete files
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
# Should return your VPS IP (91.235.234.92)
```

## 📚 Documentation

- [Smart DNS Setup](docs/SMART_DNS_SETUP.md)
- [Xbox Configuration](docs/XBOX_SETUP_GUIDE.md)
- [Domain Setup](docs/DOMAIN_SETUP_GUIDE.md)
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

- **Nginx**: DoH frontend (port 8443 internal, proxied by SNIProxy on 443)
- **DoH Backend**: satishweb/doh-server (port 8053)
- **CoreDNS**: Smart DNS layer (returns VPS IP for Xbox domains)
- **Cloudflared**: Upstream DoH (port 5053)
- **SNIProxy**: SNI proxy for Xbox traffic (port 443)

## 📝 License

MIT
EOF

# Create .gitignore
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

# Archive (old files)
archive/

# OS files
.DS_Store
Thumbs.db

# Environment
.env
EOF

echo -e "${GREEN}✅ README and .gitignore created${NC}"

echo ""
echo "================================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "================================================"
echo ""
echo "Summary:"
echo "  ✅ Organized scripts into scripts/{setup,maintenance,analysis}"
echo "  ✅ Moved documentation to docs/"
echo "  ✅ Archived obsolete files to archive/"
echo "  ✅ Created new README.md"
echo "  ✅ Created .gitignore"
echo ""
echo "Working files kept in root:"
echo "  - docker-compose.yml"
echo "  - coredns/"
echo "  - nginx/"
echo "  - ssl/"
echo ""
echo "Next steps:"
echo "  1. Review changes: git status"
echo "  2. Commit: git add ."
echo "  3. Commit: git commit -m 'Clean up and organize project structure'"
echo "  4. Push: git push"
echo ""
echo "================================================"


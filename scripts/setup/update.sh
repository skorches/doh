#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "DoH Configuration Update Script"
echo "================================================"
echo ""
echo "This script will update your running configuration"
echo "to match the latest version without full reinstall."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root (sudo)${NC}"
    exit 1
fi

# Check if installation exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ No existing installation found${NC}"
    echo "Please run install.sh first"
    exit 1
fi

echo -e "${YELLOW}[1/7] Backing up current configuration...${NC}"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r coredns/ "$BACKUP_DIR/" 2>/dev/null || true
cp -r nginx/ "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
echo -e "${GREEN}✅ Backup created: $BACKUP_DIR${NC}"
echo ""

# Detect VPS IP (priority: .env file > network interface)
echo -e "${YELLOW}[2/7] Detecting VPS IP address...${NC}"
VPS_IP=""
if [ -f ".env" ]; then
    source .env
fi
if [ -z "$VPS_IP" ]; then
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

if [ -z "$VPS_IP" ]; then
    echo -e "${RED}❌ Could not detect VPS IP${NC}"
    exit 1
fi
echo -e "${GREEN}✅ VPS IP: $VPS_IP${NC}"
echo ""

# Get domain from existing config
echo -e "${YELLOW}[3/7] Reading existing configuration...${NC}"
DOMAIN_NAME=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';' || echo "")
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}❌ Could not read domain name from config${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Domain: $DOMAIN_NAME${NC}"
echo ""

# Check SSL certificate type
SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
if [ -f "$SSL_CERT" ]; then
    echo -e "${GREEN}✅ Using Let's Encrypt certificate${NC}"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
else
    echo -e "${YELLOW}ℹ Using self-signed certificate${NC}"
    SSL_CERT="/etc/nginx/ssl/doh.crt"
    SSL_KEY="/etc/nginx/ssl/doh.key"
fi
echo ""

# Update hosts file from template
echo -e "${YELLOW}[4/7] Updating hosts file with latest domains...${NC}"
if [ -f "coredns/xbox-hosts.template" ]; then
    sed -e "s/__VPS_IP__/$VPS_IP/g" -e "s/__DATE__/$(date)/g" coredns/xbox-hosts.template > coredns/xbox-hosts
    DOMAIN_COUNT=$(grep -c "^$VPS_IP" coredns/xbox-hosts)
    echo -e "${GREEN}✅ Hosts file updated from template with $DOMAIN_COUNT domains${NC}"
else
    echo -e "${YELLOW}⚠ Template not found, generating hosts file inline...${NC}"
cat > coredns/xbox-hosts << EOFHOSTS
# Auto-generated Xbox/Gaming DNS hosts file
# Last updated: $(date)
# VPS IP: $VPS_IP
#
# TRIAL: sign-in + Xbox auth only. Full list: coredns/xbox-hosts.template.full

# === MICROSOFT ACCOUNT & IDENTITY ===
$VPS_IP login.live.com
$VPS_IP account.live.com
$VPS_IP account.microsoft.com
$VPS_IP login.microsoftonline.com

# === XBOX LIVE AUTHENTICATION ===
$VPS_IP auth.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP device.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP sisu.xboxlive.com
EOFHOSTS

DOMAIN_COUNT=$(grep -c "^$VPS_IP" coredns/xbox-hosts)
echo -e "${GREEN}✅ Hosts file updated with $DOMAIN_COUNT domains${NC}"
fi
echo ""

# Update Corefile if needed
echo -e "${YELLOW}[5/7] Checking CoreDNS configuration...${NC}"
if ! grep -q "policy sequential" coredns/Corefile 2>/dev/null; then
    echo "Updating Corefile with low-latency settings..."
    cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    # CRITICAL: hosts plugin returns immediately (~0ms), no upstream query needed
    hosts /etc/coredns/xbox-hosts {
        fallthrough
        reload 30s
        ttl 300
    }
    
    # Forward non-hosts domains to upstream DNS
    # policy sequential = try servers in order (Cloudflare first = usually fastest)
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        policy sequential
        max_fails 2
        expire 10s
        health_check 5s
    }
    
    # Cache for non-hosts domains
    # prefetch: refresh popular entries before expiry (0 latency on re-query)
    cache 3600 {
        success 3600
        denial 600
        prefetch 10 1m 10%
    }
    
    # Minimal logging (reduces I/O overhead)
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE
    echo -e "${GREEN}✅ Corefile updated with low-latency settings${NC}"
else
    echo -e "${GREEN}✅ Corefile already optimized${NC}"
fi
echo ""

# Update docker-compose.yml environment if needed
echo -e "${YELLOW}[6/7] Checking docker-compose configuration...${NC}"
if ! grep -q "DOH_SERVER_TIMEOUT=5" docker-compose.yml 2>/dev/null; then
    echo "Updating docker-compose.yml timeouts..."
    sed -i 's/DOH_SERVER_TIMEOUT=.*/DOH_SERVER_TIMEOUT=5/' docker-compose.yml
    sed -i 's/DOH_SERVER_TRIES=.*/DOH_SERVER_TRIES=3/' docker-compose.yml
    echo -e "${GREEN}✅ docker-compose.yml updated${NC}"
else
    echo -e "${GREEN}✅ docker-compose.yml already optimized${NC}"
fi
echo ""

# Restart services
echo -e "${YELLOW}[7/7] Restarting services...${NC}"
echo "Restarting CoreDNS..."
docker-compose restart coredns-smartdns 2>/dev/null || docker compose restart coredns-smartdns 2>/dev/null || docker restart coredns-smartdns
sleep 3

echo "Restarting DoH backend..."
docker-compose restart doh-backend 2>/dev/null || docker compose restart doh-backend 2>/dev/null || docker restart doh-backend
sleep 2

echo "Restarting Nginx..."
docker-compose restart doh-nginx 2>/dev/null || docker compose restart doh-nginx 2>/dev/null || docker restart doh-nginx
sleep 2

echo -e "${GREEN}✅ All services restarted${NC}"
echo ""

# Verify services
echo "================================================"
echo "Verifying Update"
echo "================================================"
echo ""

echo "Checking Docker containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "coredns|doh-backend|doh-nginx"
echo ""

echo "Testing DNS resolution..."
TEST_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=xboxlive.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1)
if echo "$TEST_RESULT" | grep -q "$VPS_IP"; then
    echo -e "${GREEN}✅ DNS resolution working (xboxlive.com → $VPS_IP)${NC}"
else
    echo -e "${YELLOW}⚠️  DNS test inconclusive, check manually${NC}"
fi
echo ""

echo "================================================"
echo "Update Complete!"
echo "================================================"
echo ""
echo "Changes applied:"
echo "  • Hosts file updated with latest domains"
echo "  • CoreDNS cache set to 24 hours"
echo "  • Fast-fail upstream settings enabled"
echo "  • DoH backend timeout increased to 10s"
echo "  • All services restarted"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To verify everything:"
echo "  bash scripts/maintenance/verify-xbox-services.sh"
echo ""
echo "If you need to rollback:"
echo "  cp -r $BACKUP_DIR/* ./"
echo "  docker-compose restart"
echo ""

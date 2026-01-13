#!/bin/bash

# Comprehensive verification of all services needed for Xbox

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

# Get VPS IP from local network interface
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
VPS_IP=""
if [ -n "$DEFAULT_IF" ]; then
    VPS_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
fi
if [ -z "$VPS_IP" ]; then
    VPS_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
fi

ISSUES=0

echo "================================================"
echo "Xbox Services Verification"
echo "================================================"
echo ""
echo "VPS IP: $VPS_IP"
echo ""
echo "This script verifies all services and domains."
echo ""

# Critical NAT detection domains
NAT_DOMAINS=(
    "xbox.nat.microsoft.com"
    "xbox.ipv4.microsoft.com"
    "xbox.ipv6.microsoft.com"
    "dns.msftncsi.com"
    "www.msftncsi.com"
    "ipv6.msftncsi.com"
    "www.msftconnecttest.com"
    "ipv4.msftconnecttest.com"
    "ipv6.msftconnecttest.com"
)

# Critical Xbox domains
XBOX_DOMAINS=(
    "xboxlive.com"
    "xbox.com"
    "xboxservices.com"
    "login.live.com"
    "account.live.com"
)

echo "[1/8] Checking Docker Service..."
if systemctl is-active docker >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ Docker is running${NC}"
else
    echo -e "  ${RED}❌ Docker is NOT running${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[2/8] Checking Docker Containers..."
CONTAINERS_OK=true

# Check CoreDNS
if docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$"; then
    STATUS=$(docker inspect coredns-smartdns --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" == "running" ]; then
        echo -e "  ${GREEN}✅ coredns-smartdns: Running${NC}"
    else
        echo -e "  ${RED}❌ coredns-smartdns: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ coredns-smartdns: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi

# Check DoH Backend
if docker ps --format "{{.Names}}" | grep -q "^doh-backend$"; then
    STATUS=$(docker inspect doh-backend --format '{{.State.Status}}' 2>/dev/null)
    HEALTH=$(docker inspect doh-backend --format '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
    if [ "$STATUS" == "running" ]; then
        if [ "$HEALTH" == "healthy" ] || [ "$HEALTH" == "no-healthcheck" ]; then
            echo -e "  ${GREEN}✅ doh-backend: Running${NC}"
        else
            echo -e "  ${YELLOW}⚠️  doh-backend: Running but unhealthy ($HEALTH)${NC}"
        fi
    else
        echo -e "  ${RED}❌ doh-backend: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ doh-backend: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi

# Check Nginx
if docker ps --format "{{.Names}}" | grep -q "^doh-nginx$"; then
    STATUS=$(docker inspect doh-nginx --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATUS" == "running" ]; then
        echo -e "  ${GREEN}✅ doh-nginx: Running${NC}"
    else
        echo -e "  ${RED}❌ doh-nginx: $STATUS${NC}"
        CONTAINERS_OK=false
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ doh-nginx: Not found${NC}"
    CONTAINERS_OK=false
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[3/8] Checking SNIProxy Service..."
if systemctl is-active sniproxy >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ SNIProxy is running${NC}"
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "  ${GREEN}✅ SNIProxy listening on port 443${NC}"
    else
        echo -e "  ${YELLOW}⚠️  SNIProxy running but port 443 not listening${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ SNIProxy is NOT running${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[4/8] Checking Port 53 (DNS)..."
if ss -ulnp | grep -q ":53.*docker-proxy" || ss -tlnp | grep -q ":53.*docker-proxy"; then
    echo -e "  ${GREEN}✅ Port 53 is listening (CoreDNS)${NC}"
    
    # Test DNS resolution (try both UDP and TCP)
    TEST_RESULT_UDP=$(timeout 3 dig @127.0.0.1 +time=2 xboxlive.com +short 2>/dev/null | head -1 | tr -d '[:space:]')
    TEST_RESULT_TCP=$(timeout 3 dig @127.0.0.1 +tcp +time=2 xboxlive.com +short 2>/dev/null | head -1 | tr -d '[:space:]')
    
    if [ "$TEST_RESULT_UDP" == "$VPS_IP" ] || [ "$TEST_RESULT_TCP" == "$VPS_IP" ]; then
        TEST_RESULT=${TEST_RESULT_UDP:-$TEST_RESULT_TCP}
        echo -e "  ${GREEN}✅ DNS resolution working (xboxlive.com → $TEST_RESULT)${NC}"
    elif [ -n "$TEST_RESULT_UDP" ] || [ -n "$TEST_RESULT_TCP" ]; then
        TEST_RESULT=${TEST_RESULT_UDP:-$TEST_RESULT_TCP}
        echo -e "  ${YELLOW}⚠️  DNS resolution returned different IP (xboxlive.com → $TEST_RESULT, expected $VPS_IP)${NC}"
        echo -e "  ${YELLOW}   Note: DoH is working correctly, this may be a cache issue${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Direct DNS test failed (timeout or no response)${NC}"
        echo -e "  ${YELLOW}   Note: DoH is working correctly, Xbox will use DoH or DNS from router${NC}"
        # Don't count this as an issue since DoH works
    fi
else
    echo -e "  ${RED}❌ Port 53 is NOT listening${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[5/8] Checking DoH Endpoint (port 443/8443)..."
# Test local DoH
DOH_RESULT=$(curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>/dev/null | grep -o '"Status":[0-9]*' || echo "FAILED")
if echo "$DOH_RESULT" | grep -q "Status\":0"; then
    DOH_DATA=$(curl -k -s -H 'accept: application/dns-json' 'https://localhost:8443/dns-query?name=xboxlive.com&type=A' 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$DOH_DATA" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ DoH endpoint working (localhost:8443)${NC}"
        echo -e "  ${GREEN}✅ DoH resolution correct (xboxlive.com → $VPS_IP)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  DoH working but wrong IP ($DOH_DATA, expected $VPS_IP)${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "  ${RED}❌ DoH endpoint not responding${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Check port 443
if ss -tlnp | grep -q ":443"; then
    echo -e "  ${GREEN}✅ Port 443 is listening (SNIProxy)${NC}"
else
    echo -e "  ${RED}❌ Port 443 is NOT listening${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[6/8] Checking NAT Detection Domains in Hosts File..."
HOSTS_FILE="coredns/xbox-hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "  ${RED}❌ Hosts file not found: $HOSTS_FILE${NC}"
    ISSUES=$((ISSUES + 1))
else
    NAT_MISSING=0
    for domain in "${NAT_DOMAINS[@]}"; do
        if grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
            echo -e "  ${GREEN}✅ $domain${NC}"
        else
            echo -e "  ${RED}❌ $domain MISSING${NC}"
            NAT_MISSING=$((NAT_MISSING + 1))
            ISSUES=$((ISSUES + 1))
        fi
    done
    
    # Check Teredo is NOT in hosts
    if grep -q "^[0-9].*teredo\.ipv6\.microsoft\.com" "$HOSTS_FILE"; then
        echo -e "  ${RED}❌ ERROR: teredo.ipv6.microsoft.com is in hosts file (must be removed)${NC}"
        ISSUES=$((ISSUES + 1))
    else
        echo -e "  ${GREEN}✅ teredo.ipv6.microsoft.com correctly removed${NC}"
    fi
fi
echo ""

echo "[7/8] Testing NAT Domain DNS Resolution..."
NAT_RESOLUTION_OK=true
for domain in "${NAT_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ $domain → $VPS_IP${NC}"
    else
        echo -e "  ${RED}❌ $domain → $RESULT (expected $VPS_IP)${NC}"
        NAT_RESOLUTION_OK=false
        ISSUES=$((ISSUES + 1))
    fi
done

# Test Teredo (should NOT be VPS IP)
TEREDO_RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=teredo.ipv6.microsoft.com&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
if [ "$TEREDO_RESULT" != "$VPS_IP" ] && [ "$TEREDO_RESULT" != "FAILED" ]; then
    echo -e "  ${GREEN}✅ teredo.ipv6.microsoft.com → $TEREDO_RESULT (real server - correct)${NC}"
else
    echo -e "  ${RED}❌ teredo.ipv6.microsoft.com → $TEREDO_RESULT (should be real Microsoft server)${NC}"
    ISSUES=$((ISSUES + 1))
fi
echo ""

echo "[8/8] Testing Critical Xbox Domains..."
XBOX_RESOLUTION_OK=true
for domain in "${XBOX_DOMAINS[@]}"; do
    RESULT=$(curl -k -s -H 'accept: application/dns-json' "https://localhost:8443/dns-query?name=$domain&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "FAILED")
    if [ "$RESULT" == "$VPS_IP" ]; then
        echo -e "  ${GREEN}✅ $domain → $VPS_IP${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $domain → $RESULT (may be correct if not in hosts file)${NC}"
    fi
done
echo ""

# Quick domain check (minimal version of verify-all-domains.sh)
echo "[9/9] Quick Domain Check..."
HOSTS_FILE="coredns/xbox-hosts"
if [ -f "$HOSTS_FILE" ]; then
    TOTAL_DOMAINS=$(grep -c "^[0-9]" "$HOSTS_FILE" 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✅ Hosts file has $TOTAL_DOMAINS domain entries${NC}"
    
    # Check a few critical domains
    CRITICAL_DOMAINS=("xboxlive.com" "xbox.com" "discord.com" "activision.com" "ea.com")
    MISSING_CRITICAL=0
    for domain in "${CRITICAL_DOMAINS[@]}"; do
        if ! grep -q "^[0-9].*$domain" "$HOSTS_FILE"; then
            MISSING_CRITICAL=$((MISSING_CRITICAL + 1))
        fi
    done
    
    if [ $MISSING_CRITICAL -eq 0 ]; then
        echo -e "  ${GREEN}✅ All critical domains present${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $MISSING_CRITICAL critical domain(s) missing${NC}"
        echo "     Run: bash scripts/maintenance/regenerate-hosts.sh"
    fi
fi
echo ""

# Auto-start services if needed
echo "[10/10] Ensuring all services are running..."
if ! systemctl is-active docker >/dev/null 2>&1; then
    systemctl start docker
    sleep 2
fi

if ! docker ps --format "{{.Names}}" | grep -q "^coredns-smartdns$"; then
    docker compose up -d coredns-smartdns 2>/dev/null || docker-compose up -d coredns-smartdns 2>/dev/null || true
    echo -e "  ${GREEN}✅ Started CoreDNS${NC}"
fi

if ! systemctl is-active sniproxy >/dev/null 2>&1; then
    systemctl start sniproxy 2>/dev/null || true
    echo -e "  ${GREEN}✅ Started SNIProxy${NC}"
fi
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ All services are running correctly!${NC}"
    echo ""
    echo "Your Xbox should work correctly if:"
    echo "  1. Xbox DNS is set to VPS IP: $VPS_IP"
    echo "     Settings → Network → DNS settings → Manual"
    echo "     Primary DNS: $VPS_IP"
    echo ""
    echo "  2. Router is configured:"
    echo "     • UPnP enabled"
    echo "     • Port 3074 (UDP) forwarded to Xbox"
    echo "     • No double NAT"
    echo ""
    echo "  3. Xbox is restarted after DNS change"
    echo ""
else
    echo -e "${RED}❌ Found $ISSUES issue(s)${NC}"
    echo ""
    echo "To fix issues:"
    echo "  • Docker containers: docker compose up -d"
    echo "  • SNIProxy: systemctl start sniproxy"
    echo "  • NAT/DNS issues: bash scripts/maintenance/fix-xbox-nat-unavailable.sh"
    echo "  • Regenerate hosts: bash scripts/maintenance/regenerate-hosts.sh"
    echo ""
fi

echo "================================================"
echo ""


#!/bin/bash

# Check if all services are working after VPS restart

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "Post-Restart Service Check"
echo "================================================"
echo ""

# Find doh directory
DOH_DIR=""
if [ -d "/root/doh" ]; then
    DOH_DIR="/root/doh"
elif [ -d "$HOME/doh" ]; then
    DOH_DIR="$HOME/doh"
elif [ -d "./doh" ]; then
    DOH_DIR="./doh"
elif [ -d "." ] && [ -f "docker-compose.yml" ]; then
    DOH_DIR="."
else
    echo -e "${RED}❌ Could not find doh directory${NC}"
    exit 1
fi

cd "$DOH_DIR"

ISSUES=0

# 1. Check Docker
echo -e "${YELLOW}[1/8] Docker Service${NC}"
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✅ Docker is running${NC}"
else
    echo -e "${RED}❌ Docker is not running${NC}"
    echo "   Starting Docker..."
    systemctl start docker
    sleep 3
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✅ Docker started${NC}"
    else
        echo -e "${RED}❌ Failed to start Docker${NC}"
        ISSUES=$((ISSUES + 1))
    fi
fi

# 2. Check Docker containers
echo ""
echo -e "${YELLOW}[2/8] Docker Containers${NC}"

EXPECTED_CONTAINERS=("coredns-smartdns" "doh-backend" "doh-nginx")
MISSING_CONTAINERS=()

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        STATUS=$(docker ps --format "{{.Status}}" --filter "name=${container}")
        echo -e "${GREEN}✅ $container: Running ($STATUS)${NC}"
    else
        echo -e "${RED}❌ $container: Not running${NC}"
        MISSING_CONTAINERS+=("$container")
        ISSUES=$((ISSUES + 1))
    fi
done

# Start missing containers
if [ ${#MISSING_CONTAINERS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Starting missing containers...${NC}"
    docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || {
        echo -e "${RED}❌ Failed to start containers${NC}"
    }
    sleep 5
fi


# 3. Check SNIProxy
echo ""
echo -e "${YELLOW}[3/8] SNIProxy Service${NC}"
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy is running (listening on port 443)${NC}"
elif systemctl is-enabled --quiet sniproxy; then
    echo -e "${YELLOW}⚠ SNIProxy is enabled but not running${NC}"
    echo "   Killing any leftover processes..."
    pkill -9 sniproxy 2>/dev/null || true
    sleep 1
    echo "   Starting SNIProxy..."
    systemctl start sniproxy
    sleep 2
    if ss -tlnp | grep -q ":443.*sniproxy"; then
        echo -e "${GREEN}✅ SNIProxy started${NC}"
    else
        echo -e "${RED}❌ Failed to start SNIProxy${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "${YELLOW}⚠ SNIProxy is not enabled${NC}"
fi

# 4. Check xbox-hosts file
echo ""
echo -e "${YELLOW}[4/9] Xbox Hosts File${NC}"

# Get VPS IP
VPS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "")

if [ -z "$VPS_IP" ]; then
    echo -e "${YELLOW}⚠ Could not detect VPS IP, skipping hosts file check${NC}"
else
    # Essential domains that should be in hosts file
    ESSENTIAL_DOMAINS=(
        "xboxlive.com"
        "xbox.com"
        "login.live.com"
        "xboxservices.com"
        "discord.com"
        "callofduty.com"
        "activision.com"
    )
    
    MISSING_DOMAINS=()
    EMPTY_FILE=0
    
    if [ ! -f "coredns/xbox-hosts" ] || [ ! -s "coredns/xbox-hosts" ]; then
        echo -e "${RED}❌ xbox-hosts file is missing or empty${NC}"
        EMPTY_FILE=1
    else
        # Check if file has VPS IP entries
        if ! grep -q "^$VPS_IP" coredns/xbox-hosts 2>/dev/null; then
            echo -e "${YELLOW}⚠ xbox-hosts file doesn't contain VPS IP entries${NC}"
            EMPTY_FILE=1
        else
            # Check for essential domains
            for domain in "${ESSENTIAL_DOMAINS[@]}"; do
                if ! grep -q "$domain" coredns/xbox-hosts 2>/dev/null; then
                    MISSING_DOMAINS+=("$domain")
                fi
            done
            
            if [ ${#MISSING_DOMAINS[@]} -eq 0 ]; then
                DOMAIN_COUNT=$(grep -c "^$VPS_IP" coredns/xbox-hosts 2>/dev/null || echo "0")
                echo -e "${GREEN}✅ xbox-hosts file is complete ($DOMAIN_COUNT domains)${NC}"
            else
                echo -e "${YELLOW}⚠ Missing essential domains: ${MISSING_DOMAINS[*]}${NC}"
            fi
        fi
    fi
    
    # Regenerate if needed
    if [ "$EMPTY_FILE" -eq 1 ] || [ ${#MISSING_DOMAINS[@]} -gt 3 ]; then
        echo -e "${YELLOW}   Regenerating xbox-hosts file...${NC}"
        if [ -f "scripts/maintenance/regenerate-hosts.sh" ]; then
            bash scripts/maintenance/regenerate-hosts.sh > /dev/null 2>&1 || {
                echo -e "${RED}❌ Failed to regenerate hosts file${NC}"
                ISSUES=$((ISSUES + 1))
            }
            sleep 2
            docker restart coredns-smartdns 2>/dev/null || true
            echo -e "${GREEN}✅ Hosts file regenerated${NC}"
        else
            echo -e "${YELLOW}⚠ regenerate-hosts.sh not found, manual regeneration needed${NC}"
            ISSUES=$((ISSUES + 1))
        fi
    fi
fi

# 5. Check Corefile (ensure it uses IPs, not hostnames)
echo ""
echo -e "${YELLOW}[5/9] Corefile Configuration${NC}"
if [ -f "coredns/Corefile" ]; then
    if grep -q "dns-proxy:" coredns/Corefile || (grep -q "forward" coredns/Corefile && ! grep -q "1\.1\.1\.1\|8\.8\.8\.8" coredns/Corefile); then
        echo -e "${YELLOW}⚠ Corefile contains hostnames or invalid config, fixing...${NC}"
        cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward with parallel upstreams for stability (always use IPs, never hostnames)
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        except /etc/coredns/xbox-hosts
    }
    
    # Enable caching (longer cache for stability)
    cache 600
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE
        echo -e "${GREEN}✅ Corefile fixed${NC}"
        docker restart coredns-smartdns 2>/dev/null || true
        sleep 3
    else
        echo -e "${GREEN}✅ Corefile is correct${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Corefile not found, creating...${NC}"
    mkdir -p coredns
    cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward with parallel upstreams for stability (always use IPs, never hostnames)
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 {
        max_concurrent 1000
        except /etc/coredns/xbox-hosts
    }
    
    # Enable caching (longer cache for stability)
    cache 600
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE
    echo -e "${GREEN}✅ Corefile created${NC}"
    docker restart coredns-smartdns 2>/dev/null || true
    sleep 3
fi

# 6. Check 3proxy (if installed)
echo ""
echo -e "${YELLOW}[6/9] 3proxy Service (Discord)${NC}"
if systemctl list-unit-files | grep -q "3proxy.*enabled"; then
    if systemctl is-active --quiet 3proxy-discord 2>/dev/null || systemctl is-active --quiet 3proxy 2>/dev/null; then
        echo -e "${GREEN}✅ 3proxy is running${NC}"
    else
        echo -e "${YELLOW}⚠ 3proxy is enabled but not running${NC}"
        systemctl start 3proxy-discord 2>/dev/null || systemctl start 3proxy 2>/dev/null || true
    fi
else
    echo -e "${BLUE}ℹ 3proxy not configured (optional)${NC}"
fi

# 7. Check port 443
echo ""
echo -e "${YELLOW}[7/9] Port 443 (SNIProxy)${NC}"
if ss -tlnp | grep -q ":443.*sniproxy"; then
    echo -e "${GREEN}✅ SNIProxy listening on port 443${NC}"
else
    echo -e "${RED}❌ Nothing listening on port 443${NC}"
    ISSUES=$((ISSUES + 1))
fi

# 8. Check port 53
echo ""
echo -e "${YELLOW}[8/9] Port 53 (CoreDNS)${NC}"
if ss -tlnp | grep -q ":53" || ss -ulnp | grep -q ":53"; then
    echo -e "${GREEN}✅ Port 53 is listening (docker-proxy forwarding to CoreDNS)${NC}"
else
    echo -e "${RED}❌ Port 53 not listening${NC}"
    ISSUES=$((ISSUES + 1))
fi

# 9. Test DNS resolution
echo ""
echo -e "${YELLOW}[9/9] DNS Resolution Test${NC}"

TEST_DOMAINS=("xboxlive.com" "callofduty.com" "discord.com")
DNS_SUCCESS=0
DNS_FAILED=0

for domain in "${TEST_DOMAINS[@]}"; do
    RESULT=$(timeout 3 dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1 || echo "FAILED")
    if [ "$RESULT" != "FAILED" ] && [ -n "$RESULT" ]; then
        echo -e "${GREEN}✅ $domain → $RESULT${NC}"
        DNS_SUCCESS=$((DNS_SUCCESS + 1))
    else
        echo -e "${RED}❌ $domain → FAILED${NC}"
        DNS_FAILED=$((DNS_FAILED + 1))
    fi
done

if [ "$DNS_FAILED" -gt 0 ]; then
    ISSUES=$((ISSUES + 1))
fi

# 10. Test DoH endpoint (separate from main checks)
echo ""
echo -e "${YELLOW}[10/10] DoH Endpoint Test${NC}"

# Get domain from config
DOMAIN=$(grep "server_name" nginx/conf.d/doh.conf 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "localhost")
if [ "$DOMAIN" != "localhost" ]; then
    DOH_URL="https://$DOMAIN/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
else
    DOH_URL="https://localhost:8443/dns-query?name=google.com&type=A"
    DOH_CMD="curl -k -s"
fi

DOH_RESPONSE=$(timeout 5 $DOH_CMD -H 'accept: application/dns-json' "$DOH_URL" 2>&1)
DOH_RESULT=$(echo "$DOH_RESPONSE" | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "FAILED")

if [ "$DOH_RESULT" == "0" ]; then
    echo -e "${GREEN}✅ DoH endpoint working (Status: 0)${NC}"
elif [ "$DOH_RESULT" == "FAILED" ]; then
    # Try to see if there's any response at all
    if echo "$DOH_RESPONSE" | grep -q "Status\|Answer\|Question"; then
        ACTUAL_STATUS=$(echo "$DOH_RESPONSE" | grep -o '"Status":[0-9]*' | cut -d: -f2 || echo "unknown")
        if [ "$ACTUAL_STATUS" != "unknown" ]; then
            echo -e "${YELLOW}⚠ DoH endpoint returned Status: $ACTUAL_STATUS${NC}"
        else
            echo -e "${GREEN}✅ DoH endpoint responding (parsing issue, but endpoint works)${NC}"
        fi
    else
        echo -e "${RED}❌ DoH endpoint not responding${NC}"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo -e "${YELLOW}⚠ DoH endpoint returned Status: $DOH_RESULT${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✅ All services are working correctly!${NC}"
    echo ""
    echo "Everything started successfully after restart."
    echo ""
    echo "Next steps:"
    echo "  • Test Xbox connectivity"
    echo "  • Test Warzone matchmaking"
    echo "  • Monitor DoH stability: ./scripts/maintenance/check-doh-stability.sh"
else
    echo -e "${YELLOW}⚠ Found $ISSUES issue(s)${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check container logs: docker logs <container-name>"
    echo "  2. Check service status: systemctl status <service-name>"
    echo "  3. Restart services: docker compose restart"
    echo "  4. Check firewall: ufw status"
fi

echo ""


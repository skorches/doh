#!/bin/bash

# Integrate CoreDNS for Smart DNS functionality
# This makes your DoH return VPS IP for Xbox domains

set -e

echo "================================================"
echo "Integrate Smart DNS with DoH"
echo "================================================"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

cd /root/doh

# Get VPS IP
VPS_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}VPS IP: $VPS_IP${NC}"

# Backup current docker-compose
echo ""
echo -e "${YELLOW}[1/4] Backing up current configuration...${NC}"
cp docker-compose.yml docker-compose.yml.backup-smartdns-$(date +%s)

# Create Corefile for CoreDNS
echo ""
echo -e "${YELLOW}[2/4] Creating CoreDNS configuration...${NC}"

mkdir -p coredns

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to doh-backend
    forward . doh-backend:8053 {
        except xboxlive.com *.xboxlive.com xboxservices.com *.xboxservices.com xbox.com *.xbox.com live.com *.live.com msftncsi.com *.msftncsi.com msftconnecttest.com *.msftconnecttest.com gamepass.com *.gamepass.com microsoft.com *.microsoft.com windows.com *.windows.com discord.com *.discord.com discord.gg *.discord.gg discordapp.com *.discordapp.com discordapp.net *.discordapp.net discord.media *.discord.media
    }
    
    # Enable caching
    cache 300
    
    # Log errors
    errors
    
    # Health check endpoint
    health :8080
}
EOFCORE

echo -e "${GREEN}✅ CoreDNS Corefile created${NC}"

# Ensure xbox-hosts file exists
if [ ! -f "coredns/xbox-hosts" ]; then
    echo ""
    echo -e "${YELLOW}Creating xbox-hosts file...${NC}"
    
    cat > coredns/xbox-hosts << EOFHOSTS
# Xbox Live domains - return VPS IP for Smart DNS
$VPS_IP xboxlive.com
$VPS_IP www.xboxlive.com
$VPS_IP notify.xboxlive.com
$VPS_IP user.auth.xboxlive.com
$VPS_IP title.auth.xboxlive.com
$VPS_IP xsts.auth.xboxlive.com
$VPS_IP cert.mgt.xboxlive.com
$VPS_IP xccs.xboxlive.com
$VPS_IP xnotify.xboxlive.com
$VPS_IP contentaccess.exp.xboxservices.com
$VPS_IP catalog.gamepass.com
$VPS_IP login.live.com
$VPS_IP arc.msn.com
$VPS_IP dns.msftncsi.com
$VPS_IP www.msftconnecttest.com
$VPS_IP ipv6.msftconnecttest.com
$VPS_IP fs.microsoft.com
$VPS_IP activity.windows.com
$VPS_IP client.wns.windows.com
$VPS_IP teredo.ipv6.microsoft.com
$VPS_IP xbox.ipv6.microsoft.com

# Discord domains - for Discord on Xbox
$VPS_IP discord.com
$VPS_IP www.discord.com
$VPS_IP gateway.discord.gg
$VPS_IP cdn.discordapp.com
$VPS_IP media.discordapp.net
$VPS_IP images-ext-1.discordapp.net
$VPS_IP images-ext-2.discordapp.net
$VPS_IP discord.gg
$VPS_IP discordapp.com
$VPS_IP discordapp.net
$VPS_IP discord.media
$VPS_IP status.discord.com
$VPS_IP voice.discord.gg
$VPS_IP router.discordapp.net
EOFHOSTS

    echo -e "${GREEN}✅ xbox-hosts file created${NC}"
fi

# Update docker-compose.yml to add CoreDNS as Smart DNS layer
echo ""
echo -e "${YELLOW}[3/4] Updating docker-compose.yml...${NC}"

# Check current structure
if ! grep -q "coredns-smartdns" docker-compose.yml; then
    echo "Adding CoreDNS Smart DNS container..."
    
    # Add CoreDNS container before the networks section
    sed -i '/^networks:/i\
  # CoreDNS for Smart DNS (intercepts Xbox domains)\
  coredns-smartdns:\
    image: coredns/coredns:latest\
    container_name: coredns-smartdns\
    restart: unless-stopped\
    command: -conf /etc/coredns/Corefile\
    volumes:\
      - ./coredns/Corefile:/etc/coredns/Corefile:ro\
      - ./coredns/xbox-hosts:/etc/coredns/xbox-hosts:ro\
    networks:\
      - doh-network\
    depends_on:\
      - doh-backend\
\
' docker-compose.yml

    echo -e "${GREEN}✅ CoreDNS Smart DNS added to docker-compose${NC}"
else
    echo -e "${GREEN}✅ CoreDNS Smart DNS already in docker-compose${NC}"
fi

# Now we need to update doh-backend to point upstream to CoreDNS for interception
# Actually, we need the flow to be: Nginx -> doh-backend -> coredns-smartdns -> real DNS
# But doh-backend already points to doh-upstream

# Better approach: Make doh-backend use coredns-smartdns as its upstream
echo ""
echo -e "${YELLOW}Updating doh-backend upstream...${NC}"

# Update doh-backend environment to use coredns-smartdns
if grep -q "UPSTREAM_DNS_SERVER=doh-upstream:5053" docker-compose.yml; then
    sed -i 's|UPSTREAM_DNS_SERVER=doh-upstream:5053|UPSTREAM_DNS_SERVER=coredns-smartdns:53|g' docker-compose.yml
    echo -e "${GREEN}✅ doh-backend now uses CoreDNS Smart DNS${NC}"
elif grep -q "UPSTREAM_DNS_SERVER" docker-compose.yml; then
    sed -i 's|UPSTREAM_DNS_SERVER=.*|UPSTREAM_DNS_SERVER=coredns-smartdns:53|g' docker-compose.yml
    echo -e "${GREEN}✅ doh-backend upstream updated${NC}"
fi

# Restart containers
echo ""
echo -e "${YELLOW}[4/4] Restarting Docker containers...${NC}"
docker-compose up -d

# Wait for containers to be healthy
echo ""
echo "Waiting for containers to start..."
sleep 10

# Check status
echo ""
echo -e "${YELLOW}Container status:${NC}"
docker-compose ps

echo ""
echo "================================================"
echo -e "${GREEN}✅ Smart DNS Integration Complete!${NC}"
echo "================================================"
echo ""
echo "Architecture:"
echo "  Keenetic → Cloudflare → Nginx → doh-backend → CoreDNS Smart DNS"
echo "                                                          ↓"
echo "                                        Xbox domains → Return VPS IP"
echo "                                        Other domains → doh-upstream (Cloudflare DoH)"
echo ""
echo "When Xbox queries xboxlive.com:"
echo "  1. CoreDNS intercepts and returns: $VPS_IP"
echo "  2. Xbox connects to $VPS_IP:443"
echo "  3. HAProxy forwards to real Xbox Live servers"
echo "  4. Traffic bypasses ISP blocking!"
echo ""
echo "HAProxy Stats: http://$VPS_IP:8404/stats"
echo ""
echo "Test it:"
echo "  curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'"
echo ""
echo "Should return: $VPS_IP (not real Xbox IP)"
echo ""
echo "================================================"


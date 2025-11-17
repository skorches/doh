#!/bin/bash

# Fix CoreDNS Corefile - use proper upstream format

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo "================================================"
echo "Fixing CoreDNS Configuration"
echo "================================================"
echo ""

cd /root/doh

echo -e "${YELLOW}Creating fixed Corefile...${NC}"

cat > coredns/Corefile << 'EOFCORE'
. {
    # Load custom hosts for Xbox and Discord domains first
    hosts /etc/coredns/xbox-hosts {
        fallthrough
    }
    
    # Forward everything else to Cloudflare DNS
    # (doh-backend will handle the DoH encryption)
    forward . 1.1.1.1 1.0.0.1 {
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

echo -e "${GREEN}✅ Corefile fixed${NC}"

echo ""
echo -e "${YELLOW}Restarting CoreDNS container...${NC}"
docker-compose restart coredns-smartdns

sleep 5

echo ""
echo -e "${YELLOW}Checking CoreDNS status...${NC}"
docker logs coredns-smartdns --tail 10

echo ""
if docker ps | grep -q "coredns-smartdns.*Up"; then
    echo -e "${GREEN}✅ CoreDNS is running${NC}"
else
    echo -e "${RED}❌ CoreDNS still failing${NC}"
    docker logs coredns-smartdns --tail 20
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ CoreDNS Fixed!${NC}"
echo "================================================"


#!/bin/bash
# Compare how a few important names resolve on:
#   1) Cloudflare (baseline)
#   2) xbox-dns.ru public DNS (111.88.96.50)
#   3) Your CoreDNS on this machine (127.0.0.1) — run ON the VPS, or pass COREDNS_IP
#
# Usage:
#   COREDNS_IP=127.0.0.1 bash scripts/maintenance/compare-public-dns.sh
#   COREDNS_IP=151.241.227.116 bash scripts/maintenance/compare-public-dns.sh   # from your PC

set -euo pipefail

COREDNS_IP="${COREDNS_IP:-127.0.0.1}"
XBOX_DNS="${XBOX_DNS:-111.88.96.50}"
CF="${CF:-1.1.1.1}"

DOMAINS=(
  "xboxlive.com"
  "auth.xboxlive.com"
  "sessiondirectory.xboxlive.com"
  "presence.xboxlive.com"
  "displaycatalog.mp.microsoft.com"
  "licensing.mp.microsoft.com"
)

echo "Resolvers: Cloudflare=$CF  xbox-dns.ru=$XBOX_DNS  your CoreDNS=$COREDNS_IP"
echo ""

for d in "${DOMAINS[@]}"; do
  echo "=== $d ==="
  echo -n "  CF:     "; dig @"$CF" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo -n "  xbox:   "; dig @"$XBOX_DNS" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo -n "  yours:  "; dig @"$COREDNS_IP" +short "$d" A 2>/dev/null | head -3 | tr '\n' ' '; echo
  echo ""
done

echo "If \"yours\" shows your VPS IP for many names, those flows hairpin through SNIProxy."
echo "If xbox-dns and CF match real Microsoft/CDN IPs but yours shows VPS IP, that is expected for pinned hosts only."

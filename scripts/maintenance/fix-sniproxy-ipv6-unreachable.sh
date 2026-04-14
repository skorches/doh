#!/bin/bash
# Many VPSes have no working global IPv6 route. SNIProxy resolves Microsoft CDNs to
# AAAA first and then fails with: "Failed to open connection to [...]:443: Network is unreachable"
# which breaks Store / Game Pass / tiles that go through the proxy.
#
# This disables IPv6 on the host so outbound connections use IPv4 only.
# Safe for typical DoH + SNIProxy setups that only need IPv4.
#
# Revert: rm /etc/sysctl.d/99-sniproxy-ipv4-outbound.conf && sysctl -p && systemctl restart sniproxy

set -euo pipefail

if [ "${EUID:-0}" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

CONF="/etc/sysctl.d/99-sniproxy-ipv4-outbound.conf"
cat > "$CONF" << 'EOF'
# Prefer IPv4 for SNIProxy upstreams (broken IPv6 path on many VPSes)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

sysctl --system >/dev/null 2>&1 || sysctl -p "$CONF"
# Apply per-interface (docker bridges, etc.) so getaddrinfo does not return AAAA
for i in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
  echo 1 >"$i" 2>/dev/null || true
done

if systemctl is-active --quiet sniproxy 2>/dev/null; then
  systemctl restart sniproxy
fi

echo "Applied $CONF and restarted sniproxy (if installed)."
echo "Verify: journalctl -u sniproxy -n 20 --no-pager | grep -i unreachable || echo 'No IPv6 unreachable errors in recent log.'"

#!/bin/bash

################################################
# Common Functions for DoH Scripts
# Sourced by all maintenance and setup scripts
################################################

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Get VPS IP (priority: env var > .env file > network interface detection)
get_vps_ip() {
    local vps_ip=""
    
    # Method 0: Check environment variable
    if [ -n "$VPS_IP" ]; then
        echo "$VPS_IP"
        return 0
    fi
    
    # Method 0.5: Check .env file
    local project_root=$(get_project_root)
    if [ -f "$project_root/.env" ]; then
        local env_ip=$(grep '^VPS_IP=' "$project_root/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "'"'"'')
        if [ -n "$env_ip" ]; then
            echo "$env_ip"
            return 0
        fi
    fi
    
    # Method 1: Get IP from default route interface
    local default_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$default_interface" ]; then
        vps_ip=$(ip -4 addr show "$default_interface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
    
    # Method 2: If still empty, try all interfaces (excluding loopback)
    if [ -z "$vps_ip" ]; then
        vps_ip=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
    fi
    
    # Validate IP format
    if [ -n "$vps_ip" ]; then
        if echo "$vps_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "$vps_ip"
            return 0
        fi
    fi
    
    echo -e "${RED}❌ Failed to detect VPS IP${NC}" >&2
    echo -e "${YELLOW}Set VPS_IP in .env or pass as argument${NC}" >&2
    return 1
}

# Get public VPS IPv6 if available (optional).
get_vps_ipv6() {
    local vps_ipv6=""
    
    # Method 0: Check environment variable
    if [ -n "${VPS_IPV6:-}" ]; then
        if is_public_ipv6 "$VPS_IPV6"; then
            echo "$VPS_IPV6"
            return 0
        fi
        return 1
    fi
    
    # Method 0.5: Check .env file
    local project_root=$(get_project_root)
    if [ -f "$project_root/.env" ]; then
        local env_ipv6=$(grep '^VPS_IPV6=' "$project_root/.env" 2>/dev/null | cut -d'=' -f2- | tr -d ' "'"'"'')
        if [ -n "$env_ipv6" ] && is_public_ipv6 "$env_ipv6"; then
            echo "$env_ipv6"
            return 0
        fi
    fi
    
    # Method 1: Try public IPv6 check services. These fail quickly on IPv4-only VPSes.
    for service in "https://api64.ipify.org" "https://icanhazip.com" "https://ifconfig.co"; do
        vps_ipv6=$(curl -6 -s --max-time 5 "$service" 2>/dev/null | grep -oEi '([0-9a-f]{1,4}:){2,}[0-9a-f:]{1,}' | head -1)
        if is_public_ipv6 "$vps_ipv6"; then
            echo "$vps_ipv6"
            return 0
        fi
    done
    
    # Method 2: Use the default IPv6 route interface.
    local default_interface=$(ip -6 route 2>/dev/null | awk '/default/ {print $5; exit}')
    if [ -n "$default_interface" ]; then
        vps_ipv6=$(ip -6 addr show dev "$default_interface" scope global 2>/dev/null | awk '/inet6/ {split($2,a,"/"); print a[1]; exit}')
    fi
    
    # Method 3: Any non-private global IPv6 on the host.
    if [ -z "$vps_ipv6" ]; then
        vps_ipv6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {split($2,a,"/"); print a[1]; exit}')
    fi
    
    if is_public_ipv6 "$vps_ipv6"; then
        echo "$vps_ipv6"
        return 0
    fi
    
    return 1
}

is_public_ipv6() {
    local ip="${1:-}"
    if [ -z "$ip" ]; then
        return 1
    fi
    if ! echo "$ip" | grep -qiE '^([0-9a-f]{0,4}:){2,}[0-9a-f]{0,4}$'; then
        return 1
    fi
    if echo "$ip" | grep -qiE '^(::1|fe80:|f[cd][0-9a-f]{2}:)'; then
        return 1
    fi
    return 0
}

append_ipv6_hosts() {
    local hosts_file="$1"
    local vps_ipv6="${2:-}"
    local ipv6_hosts
    
    if ! is_public_ipv6 "$vps_ipv6"; then
        return 0
    fi
    
    ipv6_hosts=$(awk -v ip="$vps_ipv6" '
        /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]+[A-Za-z0-9.-]+[ \t]*$/ {
            if (!seen[$2]++) print ip " " $2
        }
    ' "$hosts_file")
    
    if [ -z "$ipv6_hosts" ]; then
        return 0
    fi
    
    {
        echo ""
        echo "# === IPv6 AAAA aliases (same pinned domains) ==="
        echo "$ipv6_hosts"
    } >> "$hosts_file"
}

write_hosts_from_template() {
    local template_file="$1"
    local hosts_file="$2"
    local vps_ip="$3"
    local vps_ipv6="${4:-}"
    local tmp_file="${hosts_file}.tmp.$$"
    
    sed -e "s/__VPS_IP__/$vps_ip/g" -e "s/__DATE__/$(date)/g" "$template_file" > "$tmp_file"
    append_ipv6_hosts "$tmp_file" "$vps_ipv6"
    mv "$tmp_file" "$hosts_file"
}

# Get project root directory
get_project_root() {
    local script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    
    # Project root: repo root (parent of scripts/)
    if [[ "$script_dir" == *"/scripts" ]]; then
        echo "$(cd "$script_dir/.." && pwd)"
    else
        echo "$script_dir"
    fi
}

# Get domain (from existing nginx config)
get_domain() {
    local project_root=$(get_project_root)
    local nginx_conf="$project_root/nginx/conf.d/doh.conf"
    
    if [ -f "$nginx_conf" ]; then
        local domain=$(grep "server_name" "$nginx_conf" 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//')
        if [ -n "$domain" ]; then
            echo "$domain"
            return 0
        fi
    fi
    
    return 1
}

# Check if running as root
require_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
}

# Print section header
print_header() {
    echo "================================================"
    echo "$1"
    echo "================================================"
    echo ""
}

# Print step
print_step() {
    echo -e "${BLUE}[$1]${NC} $2"
}

# Print success
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Print error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

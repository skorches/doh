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

# Get VPS IP from local network interface (no external services)
get_vps_ip() {
    local vps_ip=""
    
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
    
    echo -e "${RED}❌ Failed to detect VPS IP from network interface${NC}" >&2
    return 1
}

# Get project root directory
get_project_root() {
    local script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    
    # Check if we're in scripts/setup or scripts/maintenance
    if [[ "$script_dir" == *"/scripts/setup" ]] || [[ "$script_dir" == *"/scripts/maintenance" ]]; then
        echo "$(cd "$script_dir/../.." && pwd)"
    elif [[ "$script_dir" == *"/scripts" ]]; then
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

# Configuration Guide

## Auto-Detection

All scripts now automatically detect your VPS IP address (IPv4) using:
- `curl -4 ifconfig.me`
- `curl -4 icanhazip.com`
- `curl -4 ipinfo.io/ip`

If auto-detection fails, scripts will prompt you to enter your VPS IP manually.

## Generated Files

### `coredns/xbox-hosts`

This file is **automatically generated** and contains your VPS IP. It's created by:
- `scripts/setup/install.sh` (during initial installation)
- `scripts/maintenance/regenerate-hosts.sh` (to update the IP)

**To update the VPS IP:**
```bash
./scripts/maintenance/regenerate-hosts.sh
```

This script will:
1. Auto-detect your current VPS IP (IPv4)
2. Regenerate `coredns/xbox-hosts` with all domains pointing to your VPS IP
3. Restart CoreDNS to apply changes

## Domain Configuration

All domain names are configured during installation via prompts. No hardcoded domains remain in the codebase.

**During installation, you'll be asked for:**
- Your domain name (e.g., `bypass.example.com`)

This domain is used for:
- DoH server endpoint
- SSL certificate generation
- SNIProxy configuration

## IP Address Usage

Your VPS IP is used in:
- `coredns/xbox-hosts` - DNS resolution for Xbox/game domains
- Scripts that display connection information

**Note:** The `coredns/xbox-hosts` file contains your actual VPS IP. This is expected and necessary for the Smart DNS to work. When you share this project, users will generate their own `xbox-hosts` file with their own VPS IP.

## Making the Project Public

✅ **Already done:**
- All scripts use auto-detection for VPS IP
- All domain names are prompted during installation
- No hardcoded personal information in scripts
- `xbox-hosts` is a generated file (users create their own)

**Before publishing:**
1. Regenerate `coredns/xbox-hosts` on your local machine (or delete it - it will be regenerated during install)
2. Verify no personal domains/IPs in README examples (use `example.com`)
3. Test fresh installation on a new VPS

## Scripts Updated for Auto-Detection

- ✅ `scripts/setup/install.sh` - Auto-detects VPS IP
- ✅ `scripts/maintenance/regenerate-hosts.sh` - Auto-detects VPS IP (IPv4)
- ✅ `scripts/maintenance/fix-discord.sh` - Auto-detects VPS IP (IPv4)
- ✅ `scripts/setup/setup-discord-udp-proxy.sh` - Auto-detects VPS IP (IPv4)
- ✅ All other scripts already used auto-detection


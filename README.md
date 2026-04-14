# Xbox Smart DNS & DoH Server

A simple self-hosted Smart DNS solution to bypass ISP blocking for Xbox Live, Discord, and major game publishers. Routes specific domains through your VPS while keeping other traffic direct.

## What This Does

- **Smart DNS**: Returns your VPS IP for blocked domains (Xbox, Discord, games)
- **DNS over HTTPS (DoH)**: Encrypted DNS queries for your router
- **SNI Proxy**: Routes HTTPS traffic to real servers based on domain name
- **Auto-configured**: All major game publishers included by default

## Quick Start

### 1. Requirements

- VPS with Ubuntu 20.04+ (any location)
- Domain name (e.g., `bypass.example.com`)
- Router with DoH support (Keenetic, OpenWrt, or any router with DoH)
- Root access to VPS

### 2. Install on VPS

```bash
# Clone repository
git clone https://github.com/skorches/doh
cd doh

# Run installer
chmod +x scripts/setup/install.sh
sudo ./scripts/setup/install.sh
```

The installer will:
- Auto-detect your VPS IP address
- Install Docker and dependencies
- Generate `coredns/xbox-hosts` from the template with your VPS IP
- Set up CoreDNS (Smart DNS), SNIProxy, DoH server (Nginx)
- Generate SSL certificates
- Save your config to `.env` for future use

**You'll be asked for:** Your domain name (e.g., `bypass.example.com`)

**Wait 5-10 minutes** - Everything installs automatically!

> **No hardcoded IPs** — the repo ships a template (`coredns/xbox-hosts.template`).  
> Your actual hosts file is generated at install time and excluded from git.

### 3. Configure Domain DNS

Make sure your domain's DNS A record points to your VPS IP:

```
Type: A
Name: @ (or your subdomain)
Content: YOUR_VPS_IP
Proxy: OFF (if using Cloudflare)
```

### 4. Get SSL Certificate (Optional but Recommended)

```bash
# Make sure domain DNS points to VPS first!
certbot certonly --standalone -d YOUR_DOMAIN
```

Then restart Nginx:
```bash
docker restart doh-nginx
```

### 5. Configure Router

**For Keenetic routers:**
1. Open router admin: `http://192.168.1.1`
2. Go to: **Internet** → **DNS** → **Other connections**
3. Enable: **"Use DNS over HTTPS (DoH)"**
4. Enter URL: `https://YOUR_DOMAIN/dns-query`
5. Save and restart router

**For other routers:**
- Look for "DNS over HTTPS" or "DoH" settings
- Enter: `https://YOUR_DOMAIN/dns-query`

### 6. Configure Xbox

**Important:** Xbox must use your VPS as DNS server:

1. Xbox → Settings → Network → Network settings
2. Advanced settings → DNS settings
3. Manual
4. Primary DNS: `YOUR_VPS_IP`
5. Secondary DNS: `8.8.8.8` (or leave empty)
6. Restart Xbox (hold power 10 seconds, wait 30s, turn on)

### 7. Test

**Test DNS:**
```bash
# From VPS
dig @127.0.0.1 xboxlive.com
# Should return your VPS IP
```

**Test DoH:**
```bash
curl -k -H 'accept: application/dns-json' \
  'https://YOUR_DOMAIN/dns-query?name=xboxlive.com&type=A'
```

**Test Xbox:**
- Xbox → Settings → Network → Test network connection
- Should show "Connected" ✅
- Test NAT type - should show Open/Moderate/Strict (not "unavailable")

## How It Works

1. **Router** queries DoH server for DNS
2. **Smart DNS (CoreDNS)** returns VPS IP for Xbox/game domains
3. **Xbox** connects to VPS IP:443
4. **SNIProxy** reads domain name from TLS handshake
5. **SNIProxy** forwards traffic to real Xbox servers
6. **Xbox** thinks it's connecting directly, but traffic is routed through VPS

## Project Structure

```
doh/
├── README.md                 # This file
├── docker-compose.yml        # Docker services
├── .env.example              # Configuration template (copy to .env)
├── coredns/
│   ├── Corefile              # CoreDNS config
│   ├── xbox-hosts.template   # Domain mappings template (__VPS_IP__ placeholder)
│   └── xbox-hosts            # Generated at install (gitignored, has your real IP)
├── nginx/
│   └── conf.d/              # Nginx config (auto-generated)
└── scripts/
    ├── install.sh            # One-shot VPS commands (update, verify, regenerate-hosts, …)
    ├── common.sh             # Shared utilities
    ├── setup/
    │   ├── install.sh        # Main installer (first-time deploy)
    │   ├── update.sh         # Update running config
    │   ├── cleanup.sh        # Complete removal
    │   └── setup-letsencrypt.sh  # Get SSL certificate
    ├── maintenance/          # Common tasks (regenerate, fixes, health)
    │   ├── regenerate-hosts.sh
    │   ├── verify-xbox-services.sh
    │   ├── fix-xbox-nat-unavailable.sh
    │   └── fix-cod-disconnects.sh
    └── diagnostics/          # Optional checks & niche host fixes (run when troubleshooting)
        ├── compare-public-dns.sh
        ├── fix-sniproxy-ipv6-unreachable.sh
        ├── verify-excluded-domains.sh
        └── verify-scripts.sh
```

## Troubleshooting

### NAT Type Unavailable

1. **Verify NAT domains are in hosts file:**
   ```bash
   cd /root/doh
   bash scripts/maintenance/fix-xbox-nat-unavailable.sh
   ```

2. **Verify Xbox DNS is set to VPS IP:**
   - Xbox → Settings → Network → Advanced → DNS Settings
   - Must be set to your VPS IP (not automatic)

3. **Check router settings:**
   - Enable UPnP
   - Forward port 3074 (TCP/UDP) to Xbox
   - Check for double NAT

### DNS Not Resolving

1. **Check CoreDNS is running:**
   ```bash
   docker ps | grep coredns-smartdns
   ```

2. **Test DNS resolution:**
   ```bash
   dig @127.0.0.1 xboxlive.com
   # Should return VPS IP
   ```

3. **Check CoreDNS logs:**
   ```bash
   docker logs coredns-smartdns --tail 50
   ```

### DoH Not Working

1. **Test DoH endpoint:**
   ```bash
   curl -k -H 'accept: application/dns-json' \
     'https://YOUR_DOMAIN/dns-query?name=xboxlive.com&type=A'
   ```

2. **Check Nginx is running:**
   ```bash
   docker ps | grep doh-nginx
   ```

3. **Check firewall:**
   ```bash
   # Port 443 must be open
   ss -tlnp | grep :443
   ```

### Game Disconnections (NBA 2K, Call of Duty, etc.)

**Important:** Some games require **direct connections** for optimal performance:

#### Excluded Games (Connect Directly, NOT via VPS):

- **Call of Duty** (Warzone, Black Ops, Modern Warfare, etc.)
  - ❌ Routing via VPS causes: "Lost connection to host/server", connection timeouts
  - ✅ Direct connection ensures: Low latency, stable matchmaking, no disconnects
  - All `activision.com`, `callofduty.com`, `demonware.net` domains excluded

- **NBA 2K / 2K Games** (NBA 2K24, 2K25, WWE 2K, etc.)
  - ❌ Routing via VPS causes: Matchmaking failures, "Unable to connect to 2K servers"
  - ✅ Direct connection ensures: Proper CDN access, matchmaking works
  - All `2k.com`, `2ksports.com`, `take2games.com` domains excluded
  - **Why:** 2K uses Akamai/AWS CDNs with geo-located nodes for roster updates, matchmaking,
    and game assets. Routing through VPS makes the game think you're in the wrong region.
  - **If your ISP blocks 2K:** You'll need a full VPN (WireGuard/OpenVPN) for 2K games
    instead of Smart DNS, since all their domains require direct geo-local resolution.

#### Why Some Games Are Excluded:

These games use **peer-to-peer** or **low-latency game servers** that require:
- Sub-50ms latency (adding VPS hop increases latency by 50-100ms)
- Direct UDP connections for game traffic
- CDN servers geographically close to you

Routing them through VPS breaks these requirements → disconnections/timeouts.

#### Verify Excluded Domains:

Check if any excluded domains accidentally got added:

```bash
cd /root/doh
bash scripts/diagnostics/verify-excluded-domains.sh
```

If excluded domains are found, fix with:
```bash
bash scripts/maintenance/fix-cod-disconnects.sh
```

#### Other Games:

If another game disconnects, check CoreDNS logs:
```bash
docker logs coredns-smartdns --tail 100 | grep -i "error\|timeout"
```

## Maintenance

### Update Running Configuration

Apply latest optimizations and domain updates without reinstalling:

```bash
cd /root/doh
bash scripts/setup/update.sh
```

This will:
- Backup current configuration
- Update to 135 latest domains
- Apply cache optimizations (24-hour cache)
- Restart all services
- Verify everything is working

### Verify Setup

Check if everything is configured correctly:

```bash
cd /root/doh
bash scripts/maintenance/verify-xbox-services.sh
```

### Regenerate Hosts File

If your VPS IP changes or you need to update domains:

```bash
cd /root/doh

# Auto-detect VPS IP (reads from .env or network interface)
bash scripts/maintenance/regenerate-hosts.sh

# Or provide your VPS IP directly
bash scripts/maintenance/regenerate-hosts.sh 1.2.3.4
```

### Fix NAT/Teredo Issues

If NAT type becomes unavailable:

```bash
cd /root/doh
bash scripts/maintenance/fix-xbox-nat-unavailable.sh
```

## Uninstalling

To remove everything cleanly:

```bash
cd /root/doh
bash scripts/setup/cleanup.sh
```

This will remove:
- All Docker containers and volumes
- SNIProxy service
- Generated configs
- Firewall rules
- SSL certificates

To also remove the project directory:
```bash
cd ~
rm -rf doh
```

## Security Notes

- The DoH endpoint is publicly accessible - use strong SSL certificates
- Consider firewall rules to limit access if needed
- Keep your VPS and Docker images updated
- Use Let's Encrypt certificates for production

## Support

For issues:
1. Check the troubleshooting section above
2. Run maintenance scripts
3. Check CoreDNS logs: `docker logs coredns-smartdns`
4. Open an issue on GitHub

---

**Made for gamers, by gamers.** 🎮

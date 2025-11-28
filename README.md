# Xbox Smart DNS & SNI Proxy Server

A self-hosted Smart DNS and SNI Proxy solution to bypass ISP blocking for Xbox Live, Discord, and major game publishers. Works by routing specific domains through your VPS while keeping other traffic direct.

## Features

- ✅ **Smart DNS** - Returns your VPS IP for blocked domains (Xbox, Discord, games)
- ✅ **SNI Proxy** - Forwards HTTPS traffic to real servers based on domain name
- ✅ **DNS over HTTPS (DoH)** - Encrypted DNS queries
- ✅ **Pre-configured** - All major game publishers included by default
- ✅ **Automatic Setup** - One script installs everything
- ✅ **Works with any router** - As long as it supports DoH

## Supported Services

**Gaming Platforms:**
- Xbox Live (all games)
- Call of Duty / Warzone (Activision)
- Battlefield / FIFA (Electronic Arts)
- Fortnite (Epic Games)
- GTA Online (Rockstar)
- And 50+ more game publishers

**Other Services:**
- Discord
- All Microsoft services

## Requirements

- **VPS** with Ubuntu 20.04+ (any location)
- **Domain name** (e.g., `bypass.example.com`)
- **Router** with DoH support (Keenetic, OpenWrt, or any router with DoH)
- **Root access** to VPS

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/doh.git
cd doh
```

### 2. Copy to VPS

```bash
# From your computer
scp -r * root@YOUR_VPS_IP:/root/doh/
```

### 3. Run Installer

```bash
# SSH into your VPS
ssh root@YOUR_VPS_IP

# Run installer
cd /root/doh
chmod +x scripts/setup/install.sh
./scripts/setup/install.sh
```

**The installer will:**
- Install Docker and Docker Compose
- Set up CoreDNS (Smart DNS)
- Configure SNIProxy
- Set up DoH server (Nginx)
- Generate SSL certificates
- Configure all game publisher domains

**You'll be asked for:**
- Your domain name (e.g., `bypass.example.com`)

**Wait 5-10 minutes** - Everything installs automatically!

### 4. Configure Domain DNS

Before continuing, make sure your domain's DNS A record points to your VPS IP:

```
Type: A
Name: @ (or your subdomain)
Content: YOUR_VPS_IP
Proxy: OFF (gray cloud in Cloudflare, if using)
```

### 5. Get SSL Certificate (Recommended)

The installer creates a self-signed certificate. For production, get a free Let's Encrypt certificate:

```bash
# Make sure your domain DNS points to the VPS first!
./scripts/setup/setup-letsencrypt.sh
```

**Requirements:**
- Domain DNS A record must point to your VPS IP
- Port 80 must be open

### 6. Configure Router

Configure your router to use the DoH endpoint:

**For Keenetic routers:**
1. Open router admin: `http://192.168.1.1`
2. Go to: **Internet** → **DNS** → **Other connections**
3. Enable: **"Use DNS over HTTPS (DoH)"**
4. Enter URL: `https://YOUR_DOMAIN/dns-query`
5. Save and restart router

**For other routers:**
- Look for "DNS over HTTPS" or "DoH" settings
- Enter: `https://YOUR_DOMAIN/dns-query`

### 7. Test

**Test DNS:**
```bash
# From a device on your network
nslookup xboxlive.com
# Should return your VPS IP
```

**Test Xbox:**
- Xbox → Settings → Network → Test network connection
- Should show "Connected" ✅

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
├── README.md                    # This file
├── SCRIPTS_REFERENCE.md         # Complete scripts documentation
├── docker-compose.yml           # Docker services (generated)
├── coredns/
│   ├── Corefile                 # CoreDNS config (generated)
│   └── xbox-hosts               # Domain mappings (generated)
├── nginx/
│   └── conf.d/                 # Nginx config (generated)
├── ssl/                         # SSL certificates (generated)
├── docs/                        # Additional documentation
└── scripts/
    ├── setup/
    │   ├── install.sh           # Main installer
    │   ├── setup-letsencrypt.sh # Let's Encrypt certificate
    │   ├── setup-cloudflare-tunnel.sh # Cloudflare Tunnel setup
    │   └── setup-discord-udp-proxy.sh # Discord UDP proxy (3proxy)
    └── maintenance/
        ├── fix-discord.sh       # Discord connectivity fix
        ├── fix-coredns.sh       # CoreDNS fix
        ├── fix-sniproxy.sh      # SNIProxy fix
        ├── fix-xbox-connectivity.sh # Xbox troubleshooting
        ├── monitor-logs.sh      # Log monitoring
        ├── regenerate-hosts.sh  # Regenerate hosts file
        ├── add-game-domain.sh   # Add game domains
        └── [other maintenance scripts]
    │   ├── setup-letsencrypt.sh # SSL certificate setup
    │   └── setup-cloudflare-tunnel.sh  # Optional: Cloudflare Tunnel
    └── maintenance/
        ├── add-game-domain.sh   # Add new game domains
        ├── fix-xbox-connectivity.sh  # Troubleshooting
        └── ...                  # Other maintenance tools
```

## Troubleshooting

### Xbox Not Connecting

1. **Check DoH is working:**
   ```bash
   curl -H 'accept: application/dns-json' \
     'https://YOUR_DOMAIN/dns-query?name=xboxlive.com&type=A'
   ```
   Should return your VPS IP.

2. **Verify router DoH settings:**
   - Make sure DoH URL is correct
   - Check router logs for errors

3. **Check Xbox DNS:**
   - Xbox → Settings → Network → Advanced → DNS
   - Must be set to "Automatic" (uses router DNS)

4. **Run troubleshooting script:**
   ```bash
   ./scripts/maintenance/fix-xbox-connectivity.sh
   ```

### DNS Not Resolving

1. **Check CoreDNS is running:**
   ```bash
   docker ps | grep coredns-smartdns
   ```

2. **Check DNS resolution:**
   ```bash
   dig xboxlive.com @127.0.0.1
   # Should return VPS IP
   ```

3. **Check firewall:**
   ```bash
   # Port 53 (DNS) must be open
   ss -tuln | grep :53
   ```

### SNIProxy Not Working

1. **Check SNIProxy status:**
   ```bash
   systemctl status sniproxy
   ```

2. **Check port 443:**
   ```bash
   ss -tlnp | grep :443
   # Should show sniproxy
   ```

3. **Check logs:**
   ```bash
   tail -f /var/log/sniproxy/https_access.log
   ```

### Still Having Issues?

Run the comprehensive troubleshooting script:
```bash
./scripts/maintenance/fix-xbox-connectivity.sh
```

This checks:
- Firewall ports
- DNS resolution
- VPS connectivity
- SNIProxy configuration
- Container status

## Adding New Game Domains

If you discover a game that doesn't work, add its domains:

```bash
./scripts/maintenance/add-game-domain.sh example.com
```

This automatically:
- Adds domain to Smart DNS
- Configures SNIProxy
- Restarts services

## Advanced: Cloudflare Tunnel (Optional)

If your VPS IP is blocked, you can use Cloudflare Tunnel to hide it:

```bash
./scripts/setup/setup-cloudflare-tunnel.sh
```

This routes traffic through Cloudflare's network, hiding your VPS IP from Xbox servers.

**Note:** Requires Cloudflare account and domain on Cloudflare.

## Maintenance Scripts

All maintenance scripts are in `scripts/maintenance/`:

**Main Fix Scripts:**
- **`fix-discord.sh`** - Comprehensive Discord connectivity fix
- **`fix-coredns.sh`** - CoreDNS fix (ports, conflicts, connection)
- **`fix-sniproxy.sh`** - SNIProxy fix (systemd, ports, timeouts)
- **`fix-xbox-connectivity.sh`** - Xbox troubleshooting

**Utility Scripts:**
- **`monitor-logs.sh`** - Real-time log monitoring (interactive menu)
- **`regenerate-hosts.sh`** - Regenerate hosts file with all domains
- **`add-game-domain.sh`** - Add individual game domains

**See `SCRIPTS_REFERENCE.md` for complete documentation.**
- **`fix-sniproxy-systemd.sh`** - Fix SNIProxy systemd issues
- **`fix-port-443.sh`** - Fix port 443 conflicts

## Uninstalling

To remove everything:

```bash
cd /root/doh
docker-compose down
systemctl stop sniproxy
systemctl disable sniproxy
apt-get remove -y sniproxy
rm -rf /root/doh
```

## Security Notes

- The DoH endpoint is publicly accessible - use strong SSL certificates
- Consider firewall rules to limit access if needed
- Keep your VPS and Docker images updated
- Use Let's Encrypt certificates for production

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - Free to use and modify

## Support

For issues and questions:
- Check the troubleshooting section
- Run maintenance scripts
- Open an issue on GitHub

## Acknowledgments

- CoreDNS for Smart DNS functionality
- SNIProxy for SNI-based proxying
- All game publishers for making great games

---

**Made for gamers, by gamers.** 🎮

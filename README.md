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
./scripts/setup/install.sh
```

The installer will:
- Install Docker and dependencies
- Set up CoreDNS (Smart DNS)
- Configure SNIProxy
- Set up DoH server (Nginx)
- Generate SSL certificates
- Configure all game domains

**You'll be asked for:** Your domain name (e.g., `bypass.example.com`)

**Wait 5-10 minutes** - Everything installs automatically!

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
├── coredns/
│   ├── Corefile              # CoreDNS config
│   └── xbox-hosts            # Domain mappings (auto-generated)
├── nginx/
│   └── conf.d/              # Nginx config (auto-generated)
└── scripts/
    ├── setup/
    │   └── install.sh        # Main installer
    └── maintenance/
        ├── verify.sh          # Verify setup (all checks)
        ├── regenerate-hosts.sh    # Regenerate hosts file
        └── fix-nat-teredo.sh      # Fix NAT/Teredo issues
```

## Troubleshooting

### NAT Type Unavailable

1. **Verify NAT domains are in hosts file:**
   ```bash
   cd /root/doh
   bash scripts/maintenance/fix-nat-teredo.sh
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

Some games need CDN/matchmaking domains to resolve to real IPs:

- **NBA 2K**: 2k.com, 2ksports.com domains removed (must resolve to real IPs)
- **Call of Duty**: CDN and demonware domains removed (must resolve to real IPs)

If a game disconnects, check CoreDNS logs for missing domains:
```bash
docker logs coredns-smartdns --tail 100 | grep -i "error\|timeout"
```

## Maintenance

### Verify Setup

Check if everything is configured correctly:

```bash
cd /root/doh
bash scripts/maintenance/verify.sh
```

### Regenerate Hosts File

If your VPS IP changes or you need to update domains:

```bash
cd /root/doh
bash scripts/maintenance/regenerate-hosts.sh
```

### Fix NAT/Teredo Issues

If NAT type becomes unavailable:

```bash
cd /root/doh
bash scripts/maintenance/fix-nat-teredo.sh
```

## Uninstalling

To remove everything:

```bash
cd /root/doh
docker compose down
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

## Support

For issues:
1. Check the troubleshooting section above
2. Run maintenance scripts
3. Check CoreDNS logs: `docker logs coredns-smartdns`
4. Open an issue on GitHub

---

**Made for gamers, by gamers.** 🎮

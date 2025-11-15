# DoH Server for Xbox Network - Russia Geo-Block Bypass

A complete DNS-over-HTTPS (DoH) server solution to bypass Xbox Network geo-blocking in Russia while maintaining low latency for gaming.

## 🇷🇺 IMPORTANT for Russian Users

**ISP blocks Cloudflare/AWS?** This setup already uses alternative DNS providers (Quad9, OpenDNS) that bypass those blocks!

**🚨 ISP blocks third-party DNS (port 53)?** → Read **[ISP_DNS_BLOCKING.md](ISP_DNS_BLOCKING.md)** - You MUST use VPN!

**Quick Links:**
- 🚨 **[ISP_DNS_BLOCKING.md](ISP_DNS_BLOCKING.md)** - If ISP blocks third-party DNS
- 🚀 **[RUSSIA_SETUP.md](RUSSIA_SETUP.md)** - Complete guide for ISP-level blocking
- ⚡ **[QUICKSTART.md](QUICKSTART.md)** - 5-minute setup
- 🎮 **[XBOX_SETUP_GUIDE.md](XBOX_SETUP_GUIDE.md)** - Xbox configuration
- 🔐 **[VPN_SETUP_GUIDE.md](VPN_SETUP_GUIDE.md)** - If DNS alone doesn't work
- 📡 **[DNS_PROVIDERS.md](DNS_PROVIDERS.md)** - Alternative DNS options

## 🎮 What This Does

- **Bypasses Geo-Blocking**: Routes Xbox Network traffic through your VPS to avoid regional restrictions
- **Low Latency**: Optimized DNS caching and forwarding for minimal ping increase
- **Easy Setup**: One-script deployment on your VPS
- **Reliable**: Uses multiple upstream DNS providers with automatic failover

## 📋 Prerequisites

- A VPS in a region with Xbox Network access (recommended: EU/US)
  - **For Russia**: Eastern Europe (Poland, Finland) recommended for best ping
  - See **[RUSSIA_SETUP.md](RUSSIA_SETUP.md)** for VPS recommendations
- SSH access to your VPS
- Ubuntu/Debian or CentOS/RHEL (other Linux distributions work too)
- At least 512MB RAM and 10GB storage (1GB RAM recommended if using VPN)

## 🚀 Quick Start

### Step 1: Deploy on VPS

1. **SSH into your VPS:**
```bash
ssh root@your-vps-ip
```

2. **Clone or upload this repository:**
```bash
cd /opt
git clone <your-repo-url> doh-server
cd doh-server
```

Or manually upload the files via SCP:
```bash
scp -r /home/wars09/Cursor/doh root@your-vps-ip:/opt/doh-server
```

3. **Run the deployment script:**
```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

The script will:
- Install Docker and Docker Compose
- Configure firewall rules
- Optimize system for DNS performance
- Start all services

4. **Note your VPS IP address** (displayed at the end of installation)

### Step 2: Configure Your Xbox

#### Method A: Change DNS Settings (Recommended)

1. On your Xbox, go to: **Settings → General → Network Settings**
2. Select **Advanced Settings**
3. Select **DNS Settings**
4. Choose **Manual**
5. Enter your VPS IP as both Primary and Secondary DNS:
   - **Primary DNS**: `YOUR-VPS-IP`
   - **Secondary DNS**: `YOUR-VPS-IP`
6. Press **B** to save and test connection

#### Method B: Configure Your Router

If you want all devices to benefit:

1. Access your router's admin panel (usually at 192.168.1.1 or 192.168.0.1)
2. Find **DNS Settings** (usually under WAN or DHCP settings)
3. Set Primary DNS to your VPS IP: `YOUR-VPS-IP`
4. Save and restart your router
5. Your Xbox will now automatically use the VPS DNS

## 🧪 Testing

### Test from VPS

```bash
chmod +x test-dns.sh
./test-dns.sh localhost
```

### Test from Your Home Network

```bash
./test-dns.sh YOUR-VPS-IP
```

Or manually test with:
```bash
# Windows
nslookup xbox.com YOUR-VPS-IP

# Linux/Mac
dig @YOUR-VPS-IP xbox.com
```

## ⚙️ Configuration

### Change Upstream DNS Providers

To optimize for your region or preference:

```bash
chmod +x update-upstream.sh
./update-upstream.sh
```

Available options:
- **Cloudflare** (1.1.1.1) - Fast, privacy-focused
- **Google** (8.8.8.8) - Reliable, global coverage
- **Quad9** (9.9.9.9) - Security and privacy focused
- **AdGuard** (94.140.14.14) - Built-in ad-blocking
- **Custom** - Use your own DoH servers

### Performance Tuning

Edit `coredns/Corefile` to adjust cache settings:

```
cache {
    success 9984 3600  # Cache successful responses (increase for stability)
    denial 9984 60     # Cache NXDOMAIN
    prefetch 10 60s    # Prefetch popular domains
}
```

### Xbox-Specific Optimizations

Add custom DNS overrides in `coredns/xbox-hosts`:

```bash
# Force specific Xbox services to optimal IPs
40.112.72.205    xbox.com
13.107.246.45    xboxlive.com
```

## 📊 Monitoring

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f dns-proxy
docker-compose logs -f doh-server
```

### Check Service Status

```bash
docker-compose ps
```

### Performance Metrics

CoreDNS metrics are available at:
```
http://YOUR-VPS-IP:9153/metrics
```

Cloudflared metrics:
```
http://YOUR-VPS-IP:49312/metrics
```

## 🔧 Maintenance

### Restart Services

```bash
docker-compose restart
```

### Update Services

```bash
docker-compose pull
docker-compose up -d
```

### Stop Services

```bash
docker-compose down
```

### Complete Cleanup

```bash
docker-compose down -v
docker system prune -a
```

## 🛠️ Troubleshooting

### Xbox Can't Connect to Network

1. **Verify DNS server is running:**
   ```bash
   docker ps
   ```

2. **Check firewall allows port 53:**
   ```bash
   sudo ufw status
   # or
   sudo firewall-cmd --list-all
   ```

3. **Test DNS resolution:**
   ```bash
   ./test-dns.sh YOUR-VPS-IP
   ```

4. **Check logs for errors:**
   ```bash
   docker-compose logs dns-proxy
   ```

### High Latency / Slow Connection

1. **Choose a VPS closer to your location**
2. **Change upstream DNS providers:**
   ```bash
   ./update-upstream.sh
   ```

3. **Increase cache time in `coredns/Corefile`**

4. **Check VPS network performance:**
   ```bash
   ping -c 10 8.8.8.8
   ```

### Geo-Blocking Still Active

1. **Verify VPS location** - ensure it's in a region without Xbox restrictions
2. **Test from VPS directly:**
   ```bash
   curl -I https://www.xbox.com
   ```

3. **Try different upstream DNS providers:**
   ```bash
   ./update-upstream.sh
   ```

### DNS Resolution Fails

1. **Check if services are running:**
   ```bash
   docker-compose ps
   ```

2. **Restart all services:**
   ```bash
   docker-compose restart
   ```

3. **Check upstream connectivity:**
   ```bash
   docker-compose exec doh-server sh -c "apk add curl && curl -I https://1.1.1.1"
   ```

## 🔒 Security Considerations

### Recommended Practices

1. **Use firewall rules** to limit DNS access to your IP:
   ```bash
   sudo ufw allow from YOUR-HOME-IP to any port 53
   sudo ufw deny 53
   ```

2. **Enable HTTPS for DoH endpoint** (optional):
   - Set up nginx reverse proxy with Let's Encrypt
   - Configure SSL certificates
   - Update Xbox to use DoH if supported

3. **Regular updates:**
   ```bash
   docker-compose pull
   docker-compose up -d
   ```

4. **Monitor access logs** for unusual activity

### VPS Provider Recommendations

For Russia to Xbox Network, consider VPS in:
- **Western Europe**: Germany, Netherlands, UK (best ping)
- **Eastern Europe**: Poland, Romania
- **US East Coast**: New York (higher ping but reliable)

Popular providers:
- Hetzner (Germany) - Excellent performance
- DigitalOcean - Global coverage
- Vultr - Many locations
- Linode - Reliable

## 📁 File Structure

```
doh/
├── docker-compose.yml       # Main service configuration
├── deploy.sh                # One-click deployment script
├── test-dns.sh             # Testing utility
├── update-upstream.sh      # Change DNS providers
├── coredns/
│   ├── Corefile            # CoreDNS configuration
│   └── xbox-hosts          # Custom host overrides
└── README.md               # This file
```

## 🌐 Architecture

```
Xbox Console
    ↓ (DNS Query - Port 53)
Your Router
    ↓
VPS: DNS Proxy (CoreDNS)
    ↓
VPS: DoH Server (Cloudflared)
    ↓ (HTTPS)
Upstream DNS (Cloudflare/Google)
    ↓
Xbox Live Servers
```

## 📝 Technical Details

### Ports Used

- **53** (TCP/UDP) - Standard DNS for Xbox
- **5053** (TCP/UDP) - Internal DoH server
- **8053** (TCP) - HTTPS DoH endpoint
- **9153** (TCP) - CoreDNS metrics
- **49312** (TCP) - Cloudflared metrics

### Docker Images

- `cloudflare/cloudflared:latest` - DoH server
- `coredns/coredns:latest` - DNS proxy
- `satishweb/doh-server:latest` - HTTPS DoH endpoint

### DNS Query Flow

1. Xbox sends DNS query to VPS (port 53)
2. CoreDNS receives and checks cache
3. If not cached, forwards to Cloudflared (port 5053)
4. Cloudflared queries upstream via DoH (HTTPS)
5. Response cached and returned to Xbox

### Performance Optimizations

- Aggressive DNS caching (1-hour TTL)
- Prefetching of popular domains
- Multiple upstream servers with failover
- TCP Fast Open enabled
- Optimized kernel network parameters

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

MIT License - Use freely for personal or commercial projects

## ⚠️ Disclaimer

This tool is for personal use to access services that may be geo-restricted in your region. Ensure compliance with your local laws and the terms of service of Xbox Network. The authors are not responsible for any misuse or violation of terms of service.

## 📞 Support

Having issues? Check the troubleshooting section above or review the logs:

```bash
docker-compose logs -f
```

For Xbox Network status, check: https://support.xbox.com/xbox-live-status

---

**Made with ❤️ for gamers experiencing geo-blocking issues**


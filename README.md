# Xbox Smart DNS Server

**Simple setup to make Xbox work in blocked regions.**

## What You Need

- VPS (Virtual Private Server) with Ubuntu
- Domain name (like `bypass.440.info`)
- Router with DoH support (like Keenetic)

## Quick Setup (5 Minutes)

### 1. Copy Files to VPS

```bash
# From your computer
scp -r * root@YOUR_VPS_IP:/root/doh/
```

### 2. Install Everything

```bash
# On your VPS
ssh root@YOUR_VPS_IP
cd /root/doh
chmod +x scripts/setup/install.sh
./scripts/setup/install.sh
```

**Wait 5-10 minutes** - The script installs everything automatically!

### 3. Configure Router

1. Open: `http://192.168.1.1` (or your router IP)
2. Go to: **Internet** → **DNS** → **Other connections**
3. Enable: **"Use DNS over HTTPS (DoH)"**
4. Enter URL: `https://YOUR_DOMAIN/dns-query`
5. Save and restart router

### 4. Test Xbox

Xbox → Settings → Network → Test network connection

**Done!** 🎮

## What Gets Installed

- DoH Server (DNS over HTTPS)
- Smart DNS (returns VPS IP for Xbox domains)
- SNI Proxy (forwards Xbox traffic)
- All configured automatically!

## Troubleshooting

**Xbox not connecting?**

1. Check DoH is working:
   ```bash
   curl -H 'accept: application/dns-json' 'https://YOUR_DOMAIN/dns-query?name=google.com&type=A'
   ```

2. Verify router DoH settings are correct

3. Make sure Xbox DNS is set to "Automatic"

**Need help?** Check the install script output for detailed logs.

## Files Included

- `docker-compose.yml` - Docker configuration
- `coredns/` - Smart DNS settings
- `scripts/setup/install.sh` - Main installer (does everything!)

That's it! Everything else is handled by the installer.

## License

MIT License - Free to use

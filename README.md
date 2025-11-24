# Xbox Smart DNS Server

**Simple setup to make Xbox and all games work in blocked regions.**

**Works with:**
- ✅ Xbox Live games (Halo, Forza, etc.)
- ✅ Call of Duty / Warzone (Activision)
- ✅ Battlefield / FIFA (EA)
- ✅ Fortnite (Epic Games)
- ✅ GTA Online (Rockstar)
- ✅ And all major game publishers!

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

**The script will ask for:**
- Your domain name (e.g., `bypass.440.info`)

**Wait 5-10 minutes** - The script installs everything automatically!

### 3. Get SSL Certificate (Recommended)

The installer creates a self-signed certificate. For production, get a free Let's Encrypt certificate:

```bash
# Make sure your domain DNS points to the VPS first!
./scripts/setup/setup-letsencrypt.sh
```

**Requirements:**
- Domain DNS A record must point to your VPS IP
- Port 80 must be open

### 4. Configure Router

1. Open: `http://192.168.1.1` (or your router IP)
2. Go to: **Internet** → **DNS** → **Other connections**
3. Enable: **"Use DNS over HTTPS (DoH)"**
4. Enter URL: `https://YOUR_DOMAIN/dns-query`
   - Use the domain you entered during installation
5. Save and restart router

### 5. Test Xbox

Xbox → Settings → Network → Test network connection

**Done!** 🎮

## What Gets Installed

- DoH Server (DNS over HTTPS)
- Smart DNS (returns VPS IP for Xbox and game domains)
- SNI Proxy (forwards Xbox and game traffic)
- **All major game publishers pre-configured:**
  - Activision (Call of Duty, Warzone)
  - Electronic Arts (Battlefield, FIFA, etc.)
  - Ubisoft, Epic Games, Rockstar, 2K Games, and more!
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

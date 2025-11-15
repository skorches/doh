# 🇷🇺 START HERE - Russia Xbox Setup

## Your Situation

You're in Russia and:
- ✅ Have an Xbox
- ❌ Can't connect to Xbox Network (geo-blocked)
- ✅ Have access to a VPS
- ⚠️ ISP blocks Cloudflare and AWS services
- ⚠️ **ISP blocks third-party DNS** (port 53)

---

## 🚨 IMPORTANT: Does Your ISP Block Third-Party DNS?

**Quick test:** Can you use 8.8.8.8 or any non-ISP DNS on your devices?

### If NO (DNS blocked):
→ **Read [ISP_DNS_BLOCKING.md](ISP_DNS_BLOCKING.md) FIRST**
→ You MUST use VPN (DNS-only won't work)
→ Skip DNS-only setup

### If YES (DNS works):
→ Continue below with DNS-only setup
→ VPN optional (only if DNS isn't enough)

---

## ✅ This Solution Handles Your Blocks!

Your setup is **already configured** to avoid Cloudflare/AWS blocks:
- Uses **Quad9** (Switzerland)
- Uses **OpenDNS** (Cisco)
- Uses **CleanBrowsing** (USA)

These providers are NOT blocked in Russia!

---

## 🚀 Quick 3-Step Setup

### Step 1: Deploy on Your VPS (5 minutes)

```bash
# Upload files to your VPS
scp -r doh root@YOUR-VPS-IP:/opt/doh-server

# SSH and deploy
ssh root@YOUR-VPS-IP
cd /opt/doh-server
chmod +x deploy.sh
./deploy.sh

# Note the VPS IP shown at the end
```

### Step 2: Configure Xbox (2 minutes)

1. Settings → Network → Advanced → DNS Settings
2. Select **Manual**
3. Primary DNS: `YOUR-VPS-IP`
4. Secondary DNS: `YOUR-VPS-IP`
5. Test network connection

### Step 3: Test (1 minute)

Should show:
- ✅ Network: Connected
- ✅ Xbox Live: Connected
- ✅ NAT Type: Open/Moderate

**Done! You can now play!** 🎮

---

## 🤔 What If DNS Doesn't Work?

If after Step 2 you still can't connect, it means your ISP blocks Xbox Live IPs (not just DNS).

**Solution: Add VPN** (adds 10 minutes)

```bash
# On VPS
cd /opt/doh-server
./setup-vpn.sh

# Follow VPN_SETUP_GUIDE.md for client setup
```

This routes ALL traffic through your VPS, bypassing IP-level blocks.

---

## 📚 Full Documentation

Choose your guide:

1. **[QUICKSTART.md](QUICKSTART.md)** - Fastest setup (what you just read)
2. **[RUSSIA_SETUP.md](RUSSIA_SETUP.md)** - Complete Russia-specific guide
3. **[XBOX_SETUP_GUIDE.md](XBOX_SETUP_GUIDE.md)** - Detailed Xbox configuration
4. **[VPN_SETUP_GUIDE.md](VPN_SETUP_GUIDE.md)** - If DNS isn't enough
5. **[README.md](README.md)** - Full technical documentation
6. **[DNS_PROVIDERS.md](DNS_PROVIDERS.md)** - Alternative DNS options

---

## 🌍 VPS Recommendations for Russia

**Best ping locations:**
- 🥇 Finland (Helsinki) - 20-40ms
- 🥇 Poland (Warsaw) - 30-50ms
- 🥈 Germany (Frankfurt) - 50-70ms
- 🥈 Netherlands (Amsterdam) - 60-80ms

**Recommended providers:**
- **Hetzner** - Best value, great network
- **Vultr** - Many locations, reliable
- **DigitalOcean** - Stable and simple

---

## 💰 Cost

**Monthly: €4-6 (~400-600 RUB)**

For DNS-only setup (what you're deploying).

VPN adds €2-4/month if needed (larger VPS).

---

## ❓ Quick Troubleshooting

### Can't SSH to VPS
- Check VPS IP is correct
- Try: `ssh -v root@VPS-IP` for debugging

### Xbox shows "Can't resolve DNS"
- Verify VPS IP entered correctly
- Test: `ping YOUR-VPS-IP` from PC

### Services not starting on VPS
```bash
docker-compose ps  # Check status
docker-compose logs  # See errors
```

### Still can't connect after DNS setup
- Your ISP blocks IPs, not just DNS
- Follow VPN_SETUP_GUIDE.md

---

## 🎯 Success Indicators

You're set up correctly when:
- ✅ Xbox Live shows "Connected"
- ✅ Can access Xbox Store
- ✅ Can play online games
- ✅ Party chat works

---

## 📞 Need Help?

1. Check `RUSSIA_SETUP.md` troubleshooting section
2. View VPS logs: `docker-compose logs -f`
3. Test DNS: `./test-dns.sh localhost`

---

**Now go deploy and start gaming! 🚀🎮**

The hardest part is already done - your config avoids the Cloudflare/AWS blocks!


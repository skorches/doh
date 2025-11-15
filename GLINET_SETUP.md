# GL.iNet Router Setup Guide (No PC Required!)

## 🎯 Why GL.iNet Router?

**Perfect alternative to using a PC:**
- ✅ Small device (fits in palm)
- ✅ Low power (always-on, ~5W)
- ✅ Easy web interface (no technical knowledge)
- ✅ Supports OpenVPN & WireGuard
- ✅ One-time setup
- ✅ ~$30-50 one-time cost
- ✅ Works perfectly with Xbox

```
Xbox → GL.iNet Router → Your Main Router → Internet
           ↓
       VPN to VPS
       (bypass all blocks)
```

---

## 📦 Which GL.iNet Router to Buy?

### Budget Option: GL-MT300N-V2 (~$20-25)
- CPU: 580MHz
- RAM: 128MB
- WiFi: 2.4GHz only
- **Good for:** Xbox only, basic usage
- **Speed:** Up to 100Mbps through VPN

### Recommended: GL-AR750S "Slate" (~$45-55)
- CPU: 750MHz
- RAM: 128MB
- WiFi: Dual-band (2.4GHz + 5GHz)
- **Good for:** Xbox + other devices
- **Speed:** Up to 200Mbps through VPN

### Best: GL-AXT1800 "Slate AX" (~$90)
- CPU: 1.2GHz (4-core)
- RAM: 512MB
- WiFi: WiFi 6 (AX1800)
- **Good for:** Gaming, multiple devices
- **Speed:** Up to 400Mbps through VPN

### Gaming Optimized: GL-MT3000 "Beryl AX" (~$90)
- CPU: 1.3GHz (dual-core)
- RAM: 512MB
- WiFi: WiFi 6 (AX3000)
- **Good for:** Serious gaming
- **Speed:** Up to 500Mbps through VPN

**Recommendation for Xbox:** GL-AR750S ($45) - best price/performance

---

## 🛒 Where to Buy

- **Official:** https://www.gl-inet.com
- **Amazon:** Search "GL.iNet router"
- **AliExpress:** Often cheaper
- **Local:** Some computer stores carry them

---

## 📦 What's in the Box

- GL.iNet router
- USB power cable
- Ethernet cable
- Quick guide

**You'll also need:**
- Power adapter (USB 5V, or use phone charger)
- Ethernet cable for Xbox (if not using WiFi)

---

## 🚀 Setup Steps

### Step 1: First Connection (5 minutes)

1. **Power on router:**
   - Connect USB power cable
   - Wait 30 seconds for lights

2. **Connect to router WiFi:**
   - Look for WiFi: `GL-AR750S-XXX` (or similar)
   - Password is on sticker on router
   - Connect your phone or computer

3. **Access web panel:**
   - Browser: http://192.168.8.1
   - Or just open browser (auto-redirects)

4. **Set admin password:**
   - Choose strong password
   - Click "Submit"

5. **Connect router to internet:**
   - Click "Internet"
   - Choose: Cable or Repeater
   - **Cable:** Connect WAN port to your main router
   - **Repeater:** Connect to your WiFi
   - Test: Should show "Connected"

✅ **Router now has internet!**

---

### Step 2: Setup VPN on Router (10 minutes)

#### Option A: OpenVPN (Recommended for you)

1. **On VPS, generate OpenVPN config:**
   ```bash
   ssh root@YOUR-VPS-IP
   cd /opt/doh-server
   ./setup-openvpn.sh
   # Choose option 2 (port 443 TCP)
   ```

2. **Download config to your computer:**
   ```bash
   scp root@YOUR-VPS-IP:/root/xbox-client.ovpn .
   ```

3. **Upload to GL.iNet:**
   - GL.iNet panel → VPN → OpenVPN Client
   - Click "Upload Configuration"
   - Select `xbox-client.ovpn`
   - Click "Upload"

4. **Connect VPN:**
   - Click on the uploaded configuration
   - Click "Connect"
   - Wait 10 seconds
   - Should show "Connected"

5. **Verify VPN:**
   - GL.iNet panel → VPN
   - Should show your VPS IP
   - Test: Browse to https://ifconfig.me
   - Should show VPS IP, not your real IP

#### Option B: WireGuard (If you change your mind)

1. **On VPS:**
   ```bash
   ssh root@YOUR-VPS-IP
   cd /opt/doh-server
   ./setup-vpn.sh
   ```

2. **Download config:**
   ```bash
   scp root@YOUR-VPS-IP:/etc/wireguard/client.conf .
   ```

3. **Upload to GL.iNet:**
   - VPN → WireGuard Client
   - Click "Set Up Manually"
   - Paste contents of `client.conf`
   - Name: "Xbox VPS"
   - Click "Apply"

4. **Connect:**
   - Toggle VPN switch to ON
   - Should connect in 5 seconds

---

### Step 3: Configure VPN Settings (5 minutes)

1. **Enable VPN for all traffic:**
   - VPN → VPN Policies
   - Select: "VPN for all traffic" (default)
   - Click "Apply"

2. **Set DNS:**
   - More Settings → DNS
   - Manual DNS Server: `10.8.0.1` (OpenVPN) or `10.13.13.1` (WireGuard)
   - Click "Apply"

3. **Enable killswitch (optional but recommended):**
   - VPN → Advanced
   - ✅ Enable "Block non-VPN traffic"
   - This prevents bypass if VPN drops

---

### Step 4: Connect Xbox (2 minutes)

#### Option A: WiFi (Easiest)

1. **Xbox Settings:**
   - Settings → Network → Set up wireless network

2. **Connect to GL.iNet WiFi:**
   - Network: `GL-AR750S-XXX`
   - Password: (router WiFi password)

3. **Test:**
   - Test network connection
   - Should show "Connected"

#### Option B: Ethernet (Better for gaming)

1. **Physical connection:**
   - Ethernet cable: Xbox → GL.iNet LAN port
   - GL.iNet WAN port → Your main router

2. **Xbox Settings:**
   - Settings → Network
   - Should auto-detect wired connection

3. **Test:**
   - Test network connection
   - Should show "Connected"

---

### Step 5: Verify Everything Works (2 minutes)

1. **Check VPN is active:**
   - GL.iNet panel → VPN
   - Should show "Connected"

2. **Test Xbox:**
   - Settings → Network → Test connection
   - ✅ Network: Connected
   - ✅ NAT Type: Open or Moderate
   - ✅ Xbox Live: Connected

3. **Test gaming:**
   - Open Xbox Store
   - Try launching a game
   - Test online multiplayer

✅ **Everything should work now!**

---

## 🎮 Gaming Performance Tips

### Reduce Latency

1. **Use 5GHz WiFi** (if router supports):
   - GL.iNet panel → Wireless
   - Enable 5GHz band
   - Connect Xbox to 5GHz network

2. **Or use Ethernet** (best):
   - Wired connection always better for gaming
   - Reduced latency, no WiFi interference

3. **QoS Settings:**
   - More Settings → QoS
   - Enable QoS
   - Set Xbox as "High Priority"

### VPN Optimizations

1. **Choose nearest VPS location:**
   - Poland/Finland for Russia
   - Lower ping = better gaming

2. **OpenVPN TCP vs UDP:**
   - TCP (port 443): Harder to block, slightly higher latency
   - UDP (port 1194): Lower latency, might be blocked
   - **For your situation:** Use TCP 443

3. **Test different VPN protocols:**
   - Some work better with your ISP
   - Easy to switch in GL.iNet panel

---

## 🔧 Advanced Settings

### Split Tunneling

**Route only Xbox through VPN, other devices direct:**

1. **VPN → VPN Policies:**
   - Select: "Only allow the following use VPN"

2. **Add Xbox MAC address:**
   - Note Xbox MAC: Settings → Network → Advanced
   - GL.iNet → Clients
   - Find Xbox, click "Use VPN"

**Benefits:**
- Other devices get full speed (no VPN)
- Xbox gets geo-block bypass
- Saves VPS bandwidth

### Multiple VPN Servers

**Setup backup VPS:**

1. Upload second VPN config
2. GL.iNet keeps both
3. Easy switching if one fails

### Auto-Reconnect

1. **VPN → Advanced:**
   - ✅ Enable "Auto Start"
   - ✅ Enable "Auto Reconnect"

**Result:** VPN reconnects automatically if dropped

---

## 📊 Monitor Performance

### Check VPN Status

- **GL.iNet panel → VPN**
  - Connection status
  - Uptime
  - Data transferred

### Check Latency

1. **More Settings → Network Tools:**
   - Ping test to game servers
   - Should be: Your ping + VPS ping

2. **Xbox Network Test:**
   - Settings → Network → Test network speed
   - Check latency to Xbox Live

### Check Bandwidth

- **GL.iNet panel → Real-time Statistics**
  - Upload/download speed
  - Connection graph

---

## 🛠️ Troubleshooting

### VPN won't connect

1. **Check VPS is reachable:**
   - GL.iNet → Network Tools → Ping
   - Enter VPS IP
   - Should respond

2. **Check VPN config:**
   - Re-download from VPS
   - Re-upload to router

3. **Check firewall:**
   - VPS must allow VPN port
   - For OpenVPN 443: `ufw allow 443/tcp`

### VPN connects but no internet

1. **Check DNS:**
   - More Settings → DNS
   - Set to VPN DNS: `10.8.0.1` or `10.13.13.1`

2. **Check VPN policy:**
   - VPN → VPN Policies
   - Should be "All traffic through VPN"

3. **Check VPS routing:**
   ```bash
   ssh root@VPS-IP
   sysctl net.ipv4.ip_forward  # Should be 1
   ```

### Xbox can't connect

1. **Verify router WiFi/Ethernet:**
   - GL.iNet → Clients
   - Should show Xbox connected

2. **Test from computer first:**
   - Connect computer to GL.iNet
   - Check IP: https://ifconfig.me
   - Should show VPS IP

3. **Reset Xbox network:**
   - Settings → Network → Advanced → Alternate MAC address → Clear
   - Restart Xbox

### High ping / lag

1. **Check VPS location:**
   - Too far from Russia? Try closer VPS

2. **Test VPN protocol:**
   - Try WireGuard instead of OpenVPN
   - Usually lower latency

3. **Check VPS load:**
   ```bash
   ssh root@VPS-IP
   htop  # Check CPU usage
   ```

### Router randomly disconnects

1. **Update firmware:**
   - GL.iNet panel → Upgrade
   - Check for updates

2. **Check power supply:**
   - Use good quality USB adapter (2A minimum)
   - Bad power = unstable connection

3. **Reduce WiFi interference:**
   - Change WiFi channel
   - Move router away from other devices

---

## 🔄 Maintenance

### Weekly

- **Check VPN is connected:**
  - GL.iNet panel → VPN → Status

### Monthly

- **Update router firmware:**
  - System → Upgrade
  - Apply updates if available

- **Reboot router:**
  - System → Reboot
  - Clears memory, improves performance

### When Xbox Live fails

1. Check VPN status in GL.iNet panel
2. Reconnect VPN if needed
3. Restart Xbox if persistent

---

## 💰 Cost Summary

**One-time:**
- GL.iNet Router: $30-90 (depends on model)
- Ethernet cable: ~$5 (if needed)

**Monthly:**
- VPS: €6-10 (~$7-11)

**Total first month:** $37-101 + VPS
**After first month:** Just VPS (~$7-11/month)

**Compared to commercial VPN:** Much cheaper long-term!

---

## ✅ Advantages Over PC Gateway

| Aspect | GL.iNet Router | Windows PC |
|--------|----------------|------------|
| Power consumption | 5W | 100-300W |
| Noise | Silent | Fan noise |
| Size | Pocket-sized | Full PC |
| Setup complexity | Web interface | ICS setup |
| Always-on | Yes (designed for it) | Wastes power |
| Portability | Take anywhere | Stay at home |
| Monthly cost | None (after purchase) | Electricity |

---

## 🎯 Verdict

**GL.iNet router is the BEST alternative to PC gateway:**

✅ One-time $30-90 purchase
✅ Easy setup (no technical knowledge)
✅ Always-on, reliable
✅ Works with OpenVPN or WireGuard
✅ Can switch between protocols
✅ Perfect for Xbox gaming
✅ Low latency
✅ Portable (take to friend's house!)

**Recommended model for your situation:**
- **GL-AR750S ($45)** - Best bang for buck
- Or **GL-AXT1800 ($90)** if you want WiFi 6

---

## 🚀 Quick Start Checklist

**Before purchase:**
- [ ] Decided on model (recommend: GL-AR750S)
- [ ] VPS already setup with VPN server

**After receiving router:**
- [ ] Connect router to power
- [ ] Connect to router WiFi
- [ ] Access web panel (192.168.8.1)
- [ ] Set admin password
- [ ] Connect router to internet
- [ ] Upload VPN config
- [ ] Connect VPN
- [ ] Connect Xbox to router
- [ ] Test Xbox Live

**Time:** ~30 minutes total setup

---

## 📞 Support

**GL.iNet support:**
- Forum: https://forum.gl-inet.com
- Email: support@gl-inet.com

**Your VPS VPN:**
- Check VPS logs: `docker-compose logs -f`
- Or OpenVPN logs: `tail -f /var/log/openvpn.log`

---

**GL.iNet router = Perfect solution for your needs! No PC required!** 🎮🚀


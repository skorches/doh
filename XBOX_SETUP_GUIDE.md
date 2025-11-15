# Xbox Configuration Guide for Russia Geo-Block Bypass

## 🎯 Step-by-Step Xbox Setup

### Prerequisites
✅ DoH server deployed and running on your VPS  
✅ VPS IP address noted (from deploy.sh output)  
✅ Xbox connected to your home network  

---

## Option 1: Configure DNS on Xbox Directly (Easiest)

### Step 1: Open Network Settings

1. Press the **Xbox button** on your controller
2. Navigate to **Settings** (gear icon)
3. Select **General**
4. Select **Network Settings**

### Step 2: Test Current Connection

1. Select **Test network connection** 
2. Note if you're getting any Xbox Live errors
3. Go back to Network Settings

### Step 3: Configure DNS

1. Select **Advanced settings**
2. Select **DNS settings**
3. Choose **Manual**
4. You'll see two fields:

   **Primary DNS**: Enter your VPS IP (e.g., `45.76.123.45`)  
   **Secondary DNS**: Enter your VPS IP again (same as primary)

5. Press **B** to go back
6. Press **A** to confirm changes

### Step 4: Test Connection

1. Go back to **Network Settings**
2. Select **Test network connection**
3. Select **Test NAT type**

**Expected Results:**
- ✅ Network: Connected
- ✅ NAT Type: Open or Moderate (NAT Type Strict may need port forwarding)
- ✅ Xbox Live: Connected

### Troubleshooting Direct Configuration

**Issue**: "Can't connect to DNS server"
- Verify VPS IP is correct
- Test VPS from computer: `nslookup xbox.com YOUR-VPS-IP`
- Check if VPS firewall allows port 53

**Issue**: "NAT Type: Strict"
- This is a router issue, not DNS
- Configure port forwarding on your router (see Xbox Support)

---

## Option 2: Configure DNS on Router (Affects All Devices)

### Advantages
- ✅ All devices benefit (PC, Xbox, PlayStation)
- ✅ No need to configure each device individually
- ✅ Easier to manage centrally

### General Steps (Router-Specific)

1. **Access Router Admin Panel**
   - Open browser and go to router IP (usually `192.168.1.1` or `192.168.0.1`)
   - Common IPs:
     - TP-Link: `192.168.0.1`
     - ASUS: `192.168.1.1`
     - D-Link: `192.168.0.1`
     - Netgear: `192.168.1.1`
     - MikroTik: `192.168.88.1`

2. **Login**
   - Default credentials (change these after setup!):
     - TP-Link: admin/admin
     - ASUS: admin/admin
     - D-Link: admin/blank
     - Netgear: admin/password

3. **Find DNS Settings**
   - Look in: **WAN**, **Internet**, **DHCP**, or **LAN** settings
   - Location varies by brand (see specific guides below)

4. **Set DNS Servers**
   - Primary DNS: Your VPS IP
   - Secondary DNS: Your VPS IP (or 8.8.8.8 as backup)

5. **Save and Reboot Router**

### Router-Specific Guides

#### TP-Link Routers

1. Go to **Network → DHCP Server**
2. Find **Primary DNS** and **Secondary DNS**
3. Enter your VPS IP in both fields
4. Click **Save**
5. Reboot router

#### ASUS Routers

1. Go to **WAN → Internet Connection**
2. Set **WAN DNS Setting** to **Manual**
3. DNS Server 1: Your VPS IP
4. DNS Server 2: Your VPS IP
5. Click **Apply**

#### MikroTik Routers (Common in Russia)

**Via WebFig:**
1. Go to **IP → DHCP Server**
2. Click on your DHCP network
3. Find **DNS Servers** field
4. Enter your VPS IP
5. Click **OK**

**Via Terminal:**
```bash
/ip dhcp-server network set 0 dns-server=YOUR-VPS-IP
```

#### Keenetic Routers (Popular in Russia)

1. Go to **Home Network**
2. Click **Network Addresses**
3. Uncheck **Use ISP DNS**
4. DNS 1: Your VPS IP
5. DNS 2: Your VPS IP or 8.8.8.8
6. Click **Save**

### After Router Configuration

1. **Restart Xbox** (hold Xbox button, select Restart console)
2. **Test connection** on Xbox as described in Option 1
3. **Verify DNS** is being used:
   - On Windows PC: `ipconfig /all`
   - Look for DNS servers, should show your VPS IP

---

## Verification & Testing

### Test from Xbox Browser (if available)

1. Open Edge browser on Xbox
2. Go to: https://www.xbox.com
3. Should load without errors

### Test from Computer on Same Network

**Windows:**
```cmd
nslookup xbox.com
```
Should show your VPS IP as the server.

**macOS/Linux:**
```bash
dig xbox.com
nslookup xbox.com
```

### Check Xbox Connection Status

1. **Settings → General → Network Settings**
2. Look for these indicators:
   - Network: **Connected**
   - NAT Type: **Open** or **Moderate** (Strict needs router port forwarding)
   - Packet Loss: **0%**
   - Latency: **<100ms** (good), **<50ms** (excellent)

---

## Performance Optimization

### Reduce DNS Latency

If you experience slow loading:

1. **Choose closer VPS location**
   - Test different VPS regions
   - Use EU West for best Russia-to-EU ping

2. **Change upstream DNS on VPS**
   ```bash
   ssh root@your-vps-ip
   cd /opt/doh-server
   ./update-upstream.sh
   ```
   Try Google DNS (8.8.8.8) or regional DNS

3. **Adjust Xbox Settings**
   - **Settings → General → Power & Startup**
   - Set **Power mode** to **Instant-on** (keeps network active)

### Improve Download Speeds

The DoH server only affects DNS, not download speeds. For faster downloads:

1. **Use Wired Connection** (Ethernet cable)
2. **QoS Settings** on router (prioritize Xbox)
3. **Close other devices** using bandwidth

---

## Common Issues & Solutions

### Issue: "Can't connect to Xbox Live"

**Possible Causes:**
1. VPS is down or unreachable
2. Firewall blocking DNS traffic
3. Wrong VPS IP entered

**Solutions:**
```bash
# Test VPS from computer
ping YOUR-VPS-IP

# Test DNS resolution
nslookup xbox.com YOUR-VPS-IP

# Check VPS status
ssh root@YOUR-VPS-IP
docker-compose ps
```

### Issue: High Ping in Games

**This is normal** - you're routing through a VPS. To minimize:
- Choose VPS closest to game servers
- Use low-latency VPS provider (Hetzner, Vultr)
- DNS caching helps (already configured)

Expected ping increase: **10-30ms**

### Issue: Some Games Don't Work

Some games use additional geo-checks beyond DNS:
- Game-level geo-blocking (can't be bypassed with DNS alone)
- Solution: Use VPN in addition to DNS (tunnels all traffic)

### Issue: DNS Works but Downloads Are Slow

DNS doesn't affect download speed. Check:
- Your ISP connection
- Xbox network settings
- Router QoS settings
- Close bandwidth-heavy apps

---

## Advanced: Using VPN Alongside DNS

For maximum bypass (recommended for strict geo-blocking):

### Option A: VPN on Router
- Install VPN client on router (if supported)
- Connect to VPS or VPN provider
- All traffic routed through VPN + DNS

### Option B: VPN on VPS
Setup WireGuard or OpenVPN on your VPS:

1. **On VPS**, install VPN server
2. **On Router**, connect as VPN client
3. **DNS** handled automatically

### Option C: Xbox → Windows PC → VPN
1. Share VPN connection from Windows PC
2. Connect Xbox to PC via Ethernet
3. PC acts as gateway with VPN+DNS

---

## Monitoring & Maintenance

### Check if DNS is Working

**From Xbox:**
- Settings → Network Settings → Test Network Connection
- Should show "Connected" for all services

**From Computer:**
```bash
# Windows
nslookup xbox.com

# Should show your VPS IP as server
# Example output:
Server:  vps-hostname
Address: YOUR-VPS-IP
```

### VPS Maintenance (Monthly)

```bash
ssh root@YOUR-VPS-IP
cd /opt/doh-server

# Update services
docker-compose pull
docker-compose up -d

# Check logs
docker-compose logs -f
```

---

## Backup Configuration

### Save Your Settings

Write down:
- **VPS IP**: ________________
- **VPS Provider**: ________________
- **VPS Location**: ________________
- **Router Model**: ________________
- **Xbox DNS Config**: Direct / Router

### If VPS Changes

1. Deploy on new VPS
2. Update Xbox/Router with new IP
3. Test connection

---

## Need Help?

### Logs to Check

**On VPS:**
```bash
ssh root@YOUR-VPS-IP
cd /opt/doh-server
docker-compose logs dns-proxy
docker-compose logs doh-server
```

**On Xbox:**
- Settings → Network Settings → Test network connection
- Note any error codes

### Common Error Codes

- **0x87DD0006**: Xbox Live service issue (not DNS-related)
- **0x87DD0017**: DNS resolution failed (check VPS)
- **0x8007274C**: Wrong DNS server (verify VPS IP)
- **0x80072EFD**: Connection timeout (VPS firewall?)

---

## Success Indicators

✅ Xbox Live status shows "Connected"  
✅ Can access Xbox Store  
✅ Can play online multiplayer  
✅ Game downloads work  
✅ Party chat works  
✅ Streaming services accessible  

---

**You're all set! Enjoy Xbox Live from Russia! 🎮🚀**

For technical support, check the logs and main README.md troubleshooting section.


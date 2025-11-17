# WireGuard VPN Setup Guide for Xbox

## 🎯 When You Need VPN

Use VPN in addition to DNS if:
- ✅ DNS bypass alone doesn't work
- ✅ ISP blocks Xbox Live IPs directly (not just DNS)
- ✅ Cloudflare/AWS IPs are blocked
- ✅ You need full traffic encryption

## ⚠️ Trade-offs

**Advantages:**
- ✅ Complete geo-block bypass
- ✅ All traffic encrypted
- ✅ Appears as if you're in VPS location

**Disadvantages:**
- ⚠️ Higher latency (all traffic through VPS)
- ⚠️ Requires router support OR PC as gateway
- ⚠️ May affect download speeds based on VPS bandwidth

---

## 🚀 Step 1: Setup VPN on VPS

### Deploy VPN Server

```bash
# SSH into your VPS
ssh root@YOUR-VPS-IP

# Navigate to project directory
cd /opt/doh-server

# Run VPN setup
chmod +x setup-vpn.sh
./setup-vpn.sh
```

This will:
- Install WireGuard
- Generate encryption keys
- Configure VPN server
- Create client configuration
- Display QR code

**Important:** Save the displayed information!

---

## 🖥️ Step 2: Setup Client

You have **3 options** for connecting Xbox through VPN:

---

### Option A: Windows PC as Gateway (Easiest for Xbox)

#### Step 1: Setup WireGuard on Windows PC

1. **Download WireGuard for Windows:**
   - Go to: https://www.wireguard.com/install/
   - Download and install

2. **Get Client Config from VPS:**
   ```bash
   # On your local machine
   scp root@YOUR-VPS-IP:/etc/wireguard/client.conf .
   ```

3. **Import Config to WireGuard:**
   - Open WireGuard app
   - Click "Import tunnel(s) from file"
   - Select `client.conf`
   - Click "Activate"

4. **Verify Connection:**
   - Should show "Active" with data transfer
   - Check IP: https://ifconfig.me (should show VPS IP)

#### Step 2: Share VPN Connection with Xbox

**Physical Setup:**
- Connect Xbox to PC via Ethernet cable
- PC needs 2 network adapters (WiFi + Ethernet) or 2 Ethernet ports

**Configure Internet Sharing:**

1. **Open Network Connections:**
   - Press `Win + R`, type `ncpa.cpl`, press Enter

2. **Find WireGuard Adapter:**
   - Look for "WireGuard Tunnel" adapter

3. **Enable Sharing:**
   - Right-click WireGuard adapter
   - Properties → Sharing tab
   - ✅ Check "Allow other network users to connect"
   - Select the Ethernet adapter connected to Xbox
   - Click OK

4. **Configure Ethernet Adapter:**
   - Right-click Ethernet adapter (to Xbox)
   - Properties → Internet Protocol Version 4 (TCP/IPv4)
   - Set:
     - IP address: `192.168.137.1`
     - Subnet mask: `255.255.255.0`
   - Click OK

#### Step 3: Configure Xbox

1. **Xbox Network Settings:**
   - Settings → Network → Advanced settings
   - IP settings: Manual

2. **Set Static IP:**
   - IP address: `192.168.137.100`
   - Subnet mask: `255.255.255.0`
   - Gateway: `192.168.137.1` (PC IP)
   - Primary DNS: `10.13.13.1` (VPN internal DNS)
   - Secondary DNS: `10.13.13.1`

3. **Test Connection:**
   - Go back to Network settings
   - Test network connection
   - Should show connected through PC

---

### Option B: Router with WireGuard Support

#### Compatible Routers:
- MikroTik RouterOS
- OpenWRT/LEDE routers
- GL.iNet routers (has built-in WireGuard)
- Ubiquiti EdgeRouter
- pfSense/OPNsense

#### MikroTik Setup (Popular in Russia)

**Via Terminal:**

```bash
# SSH into MikroTik router
ssh admin@192.168.88.1

# Import configuration
/interface wireguard add name=wg-xbox listen-port=51820 private-key="CLIENT_PRIVATE_KEY_FROM_VPS"

/interface wireguard peers add interface=wg-xbox public-key="SERVER_PUBLIC_KEY_FROM_VPS" endpoint-address=YOUR_VPS_IP endpoint-port=51820 allowed-address=0.0.0.0/0

# Add IP address to WireGuard interface
/ip address add address=10.13.13.2/24 interface=wg-xbox

# Add route through VPN
/ip route add dst-address=0.0.0.0/0 gateway=10.13.13.1

# Configure NAT
/ip firewall nat add chain=srcnat out-interface=wg-xbox action=masquerade

# Set DNS
/ip dns set servers=10.13.13.1
```

**Via WebFig:**

1. **Interfaces → WireGuard:**
   - Add new interface
   - Name: `wg-xbox`
   - Private Key: Paste from `client.conf`

2. **Peers:**
   - Public Key: Paste server public key
   - Endpoint: `YOUR_VPS_IP:51820`
   - Allowed Addresses: `0.0.0.0/0`

3. **IP → Addresses:**
   - Add: `10.13.13.2/24` on `wg-xbox`

4. **IP → Routes:**
   - Add default route via `10.13.13.1`

5. **IP → DNS:**
   - Servers: `10.13.13.1`

#### GL.iNet Router Setup

1. **Access router panel:** http://192.168.8.1
2. **VPN → WireGuard Client**
3. **Configuration Method → Manual**
4. **Paste entire `client.conf` contents**
5. **Click Apply**
6. **Enable VPN toggle**

All connected devices (including Xbox) automatically use VPN!

#### OpenWRT Setup

1. **Install WireGuard package:**
   ```bash
   opkg update
   opkg install wireguard-tools luci-proto-wireguard
   ```

2. **Upload client.conf via SCP:**
   ```bash
   scp client.conf root@192.168.1.1:/etc/config/
   ```

3. **Configure via LuCI:**
   - Network → Interfaces → Add new interface
   - Protocol: WireGuard VPN
   - Import configuration file

---

### Option C: Android/iOS Hotspot (Mobile Workaround)

If you don't have a compatible router or PC:

1. **Install WireGuard on phone:**
   - Android: Play Store
   - iOS: App Store

2. **Import config:**
   - Scan QR code (shown during VPS setup)
   - Or manually import `client.conf`

3. **Enable VPN on phone**

4. **Create mobile hotspot:**
   - Share phone's VPN connection
   - Connect Xbox to phone's hotspot

**Limitations:**
- ⚠️ Phone must stay on
- ⚠️ May use mobile data
- ⚠️ Higher latency

---

## 🧪 Testing VPN Connection

### On Client Device

**Check IP address:**
```bash
# Linux/Mac/Windows (PowerShell)
curl ifconfig.me

# Should show VPS IP, not your real IP
```

**Test DNS through VPN:**
```bash
nslookup xbox.com 10.13.13.1
```

### On Xbox

1. **Network Settings → Test connection**
2. **Check for "Connected" status**
3. **Try accessing Xbox Store**
4. **Launch a game**

### Verify Geo-Location

Visit: https://www.xbox.com/en-US/

Should not redirect to Russian site.

---

## 📊 Performance Tuning

### Reduce VPN Latency

Edit `/etc/wireguard/wg0.conf` on VPS:

```ini
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = ...
# Add these optimizations:
MTU = 1420

[Peer]
# ... existing config ...
PersistentKeepalive = 15  # Reduce from 25 for better responsiveness
```

Restart:
```bash
systemctl restart wg-quick@wg0
```

### Optimize VPS Network

```bash
# On VPS
cat >> /etc/sysctl.conf << EOF
# WireGuard optimizations
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=2500000
net.core.wmem_max=2500000
EOF

sysctl -p
```

### Split Tunneling (Advanced)

Only route Xbox traffic through VPN, not all traffic:

**In `client.conf`:**
```ini
[Peer]
# Instead of 0.0.0.0/0, specify Xbox Live IP ranges
AllowedIPs = 13.64.0.0/11, 13.104.0.0/14, 20.34.0.0/15, 40.74.0.0/15, 52.160.0.0/11
```

This reduces latency for non-Xbox traffic.

---

## 🛠️ Troubleshooting

### VPN Connects but No Internet

**Check IP forwarding on VPS:**
```bash
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1
```

**Check iptables rules:**
```bash
iptables -t nat -L POSTROUTING -v
# Should show MASQUERADE rule
```

**Check routing:**
```bash
ip route
# Should show route through VPN
```

### Xbox Can't Connect Through VPN

1. **Verify PC gateway is correct:**
   - Xbox should point to PC IP as gateway
   - DNS should be VPN DNS (10.13.13.1)

2. **Check Windows Firewall:**
   - Allow WireGuard through firewall
   - Allow network sharing

3. **Disable Internet Connection Sharing, then re-enable**

### High Ping / Packet Loss

**Test VPS ping:**
```bash
ping YOUR-VPS-IP
```

**Test through VPN:**
```bash
# After connecting to VPN
ping 10.13.13.1  # VPS internal IP
ping 8.8.8.8     # External through VPN
```

**Solutions:**
- Choose VPS closer to Russia (Eastern Europe best)
- Use UDP VPN protocol (WireGuard default)
- Optimize MTU settings
- Check VPS provider network quality

### VPN Disconnects Frequently

**Edit client config:**
```ini
[Peer]
PersistentKeepalive = 15  # Keep connection alive
```

**Check VPS load:**
```bash
ssh root@YOUR-VPS-IP
top  # Check CPU/memory usage
```

---

## 🔐 Security Best Practices

### Change Default VPN Network

Edit VPS `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.X.X.1/24  # Change to random subnet
```

Update client configs accordingly.

### Firewall Rules

Only allow VPN from your IP:

```bash
# On VPS
ufw allow from YOUR_HOME_IP to any port 51820 proto udp
```

### Regular Updates

```bash
# Monthly maintenance
ssh root@YOUR-VPS-IP
apt update && apt upgrade -y  # Update system
systemctl restart wg-quick@wg0  # Restart VPN
```

---

## 📱 Adding More Clients

To add another device (phone, laptop):

```bash
# On VPS
cd /etc/wireguard

# Generate new keys
wg genkey | tee client2_private.key | wg pubkey > client2_public.key

# Add to server config
cat >> wg0.conf << EOF

[Peer]
PublicKey = $(cat client2_public.key)
AllowedIPs = 10.13.13.3/32
EOF

# Create client2 config
cat > client2.conf << EOF
[Interface]
PrivateKey = $(cat client2_private.key)
Address = 10.13.13.3/24
DNS = 10.13.13.1

[Peer]
PublicKey = $(cat server_public.key)
Endpoint = YOUR_VPS_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Restart WireGuard
systemctl restart wg-quick@wg0
```

---

## 🎮 Final Configuration Summary

### Complete Setup (VPN + DoH)

```
Xbox → Windows PC (gateway) → VPN → VPS → Internet
                                    ↓
                              DoH Server → Upstream DNS
                                    ↓
                              Xbox Live (unblocked)
```

**What's happening:**
1. Xbox uses PC as gateway
2. All Xbox traffic → VPN tunnel → VPS
3. DNS queries → VPS DoH server → Alternative DNS (not blocked)
4. VPS in unrestricted region accesses Xbox Live
5. Xbox Live thinks you're in VPS location

---

## 📞 Support

**Check VPN status:**
```bash
# On VPS
systemctl status wg-quick@wg0
wg show
```

**Monitor traffic:**
```bash
watch -n 1 wg show
```

**View logs:**
```bash
journalctl -u wg-quick@wg0 -f
```

---

**Your setup is ready! 🎮🔒🚀**


# Keenetic Router DoH Setup

## 🎯 Perfect Solution for You!

Since you're already using `http://xbox-dns.ru/dns-query` on your Keenetic router successfully, we'll create the **exact same setup** on your own VPS!

**Benefits:**
- ✅ Already know it works (you're using it now)
- ✅ No VPN needed
- ✅ No additional devices needed
- ✅ Just change DoH URL in Keenetic
- ✅ Simple and clean

---

## 🚀 Setup Steps

### Step 1: Clean Up Previous Configs

```bash
cd /opt/doh-server
sudo ./cleanup.sh
```

This removes all the complex VPN/WireGuard stuff we set up before.

### Step 2: Deploy Simple DoH Server

```bash
sudo ./deploy-keenetic-doh.sh
```

**Choose port 443** (recommended) or alternative port.

This creates a DoH server exactly like xbox-dns.ru.

### Step 3: Note Your DoH URL

After deployment, you'll see:
```
Your DoH URL:
  https://YOUR-VPS-IP/dns-query
```

**Save this URL!**

---

## 📱 Configure Keenetic Router

### Method 1: Web Interface (Easier)

1. **Access Router:**
   - Open browser: `http://192.168.1.1` (or `http://my.keenetic.net`)
   - Login with admin credentials

2. **Navigate to DNS Settings:**
   - Click: **Internet** (Интернет)
   - Then: **DNS** (or DNS settings)

3. **Enable DNS-over-HTTPS:**
   - Look for: "DNS-over-HTTPS" or "DoH" section
   - Enable/check the box

4. **Enter Your DoH URL:**
   ```
   https://YOUR-VPS-IP/dns-query
   ```
   (Replace YOUR-VPS-IP with your actual VPS IP)

5. **Save and Apply:**
   - Click "Apply" or "Save"
   - Router will apply settings (may take 10-30 seconds)

6. **Test:**
   - Xbox should now connect to Xbox Live!

---

### Method 2: CLI (Alternative)

If your Keenetic model doesn't show DoH in web interface:

1. **SSH to Keenetic:**
   ```bash
   ssh admin@192.168.1.1
   # Enter your router password
   ```

2. **Configure DoH:**
   ```bash
   # Install DoH component if not present
   opkg dns-over-https
   
   # Set your DoH URL
   opkg dns-over-https url https://YOUR-VPS-IP/dns-query
   
   # Save configuration
   system configuration save
   ```

3. **Verify:**
   ```bash
   opkg dns-over-https show
   ```

4. **Exit:**
   ```bash
   exit
   ```

---

## 🔍 Verify It's Working

### Test 1: From Router

SSH to Keenetic and test:
```bash
nslookup xbox.com
```

Should resolve successfully.

### Test 2: From Xbox

1. **Xbox Settings:**
   - Network → Test network connection

2. **Should show:**
   - ✅ Network: Connected
   - ✅ Xbox Live: Connected
   - ✅ NAT Type: Open or Moderate

3. **Try accessing:**
   - Xbox Store
   - Online games
   - Party chat

---

## 📊 What's Different from xbox-dns.ru

| Aspect | xbox-dns.ru | Your VPS |
|--------|-------------|----------|
| **DoH URL** | http://xbox-dns.ru/dns-query | https://YOUR-VPS-IP/dns-query |
| **Upstream DNS** | Unknown (their choice) | Quad9 (9.9.9.9) - not blocked in Russia |
| **Control** | They control it | You control it |
| **Privacy** | They see your queries | You see your queries |
| **Reliability** | Depends on them | Depends on you |
| **Cost** | Free (for now) | €6-10/month VPS |
| **Speed** | Unknown | Optimized for you |

---

## 🎮 Why This Works

**Your setup:**
```
Xbox → Keenetic Router → DoH (your VPS) → Quad9 DNS → Xbox Live
         ↓
    Uses HTTPS (port 443)
    ISP can't block (would break websites)
    Bypasses DNS restrictions
```

**What ISP sees:**
- Encrypted HTTPS traffic to your VPS
- Looks like normal web browsing
- Can't tell it's DNS
- Can't block it

---

## 🔧 Troubleshooting

### DoH URL Not Working in Keenetic

**Try different formats:**

1. With HTTPS:
   ```
   https://YOUR-VPS-IP/dns-query
   ```

2. Without HTTPS (if certificate issues):
   ```
   http://YOUR-VPS-IP/dns-query
   ```

3. With explicit port:
   ```
   https://YOUR-VPS-IP:443/dns-query
   ```

4. Alternative port (if you chose 8053):
   ```
   http://YOUR-VPS-IP:8053/dns-query
   ```

### Keenetic Not Accepting URL

**Some Keenetic models only support specific formats:**

1. **Check KeeneticOS version:**
   - System → About
   - Update if old version

2. **Try without /dns-query:**
   ```
   https://YOUR-VPS-IP
   ```

3. **Use IP directly (no domain):**
   - Keenetic requires IP, not domain name
   - ✅ Good: `https://45.76.123.45/dns-query`
   - ❌ Bad: `https://mydomain.com/dns-query`

### Xbox Still Can't Connect

1. **Check DoH server logs:**
   ```bash
   docker-compose logs -f
   ```

2. **Test DoH from another device:**
   - Connect phone to Keenetic WiFi
   - Try accessing internet
   - Should work if DoH is working

3. **Verify firewall on VPS:**
   ```bash
   sudo ufw status
   # Should show port 443 allowed
   ```

4. **Test DoH endpoint:**
   ```bash
   curl -v https://YOUR-VPS-IP/dns-query
   # Should get HTTP 400 (normal for DoH without proper query)
   ```

---

## 🔄 Switch from xbox-dns.ru to Your VPS

**Currently using:** `http://xbox-dns.ru/dns-query`

**Change to:** `https://YOUR-VPS-IP/dns-query`

**Steps:**
1. Keenetic → Internet → DNS
2. Find DoH URL field
3. Replace `http://xbox-dns.ru/dns-query` with `https://YOUR-VPS-IP/dns-query`
4. Save
5. Done!

**No reboot needed** - change takes effect immediately.

---

## 💡 Advanced: Multiple DoH Servers

**For redundancy, add both:**

Some Keenetic models support multiple DoH URLs:

1. Primary: `https://YOUR-VPS-IP/dns-query`
2. Backup: `http://xbox-dns.ru/dns-query`

If your VPS goes down, falls back to xbox-dns.ru.

---

## 📊 Performance Comparison

### Test Latency

**From Xbox or computer connected to Keenetic:**

```bash
# Test xbox-dns.ru
time nslookup xbox.com

# After switching to your VPS
time nslookup xbox.com
```

**Your VPS should be:**
- Similar or faster latency
- More reliable
- Under your control

---

## 🔐 Security & Privacy

**With xbox-dns.ru:**
- They can see all your DNS queries
- They know what sites/services you access
- You trust them with your data

**With your VPS:**
- Only you can see DNS queries
- Full control over logging
- Complete privacy

---

## 💰 Cost Comparison

**xbox-dns.ru:**
- Free (but for how long?)
- Might disappear
- Might get blocked
- No control

**Your VPS:**
- €6-10/month
- You control uptime
- Won't disappear
- Can't be easily blocked

**Worth it?** For privacy and control, yes!

---

## ✅ Quick Setup Checklist

**On VPS:**
- [ ] Run `./cleanup.sh`
- [ ] Run `./deploy-keenetic-doh.sh`
- [ ] Note your DoH URL
- [ ] Verify it's running: `docker ps`

**On Keenetic:**
- [ ] Login to router web interface
- [ ] Navigate to Internet → DNS
- [ ] Enable DNS-over-HTTPS
- [ ] Enter: `https://YOUR-VPS-IP/dns-query`
- [ ] Save and apply

**On Xbox:**
- [ ] Test network connection
- [ ] Should connect to Xbox Live
- [ ] Try opening Xbox Store
- [ ] Test online gaming

---

## 🎯 Why This is the BEST Solution for You

**You already proved it works** by using xbox-dns.ru!

**Now you get:**
- ✅ Same setup, your own server
- ✅ No VPN complexity
- ✅ No additional devices
- ✅ No PC gateway needed
- ✅ Just simple DoH URL change
- ✅ Complete control

**This is what we should have done from the start!** 🎉

---

## 📞 Need Help?

**Check logs:**
```bash
docker-compose logs -f
```

**Restart service:**
```bash
docker-compose restart
```

**Check Keenetic DoH status:**
```bash
ssh admin@192.168.1.1
opkg dns-over-https show
```

---

**Simple, clean, and exactly what you need!** 🚀


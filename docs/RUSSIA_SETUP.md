# Complete Setup Guide for Russia - ISP Level Blocking

## 🇷🇺 Understanding the Blocks

In Russia, there are **multiple levels** of blocking:

1. **DNS Blocking** - ISP redirects domain lookups ✅ Fixed by DoH
2. **IP Blocking** - ISP blocks specific IPs (Cloudflare, AWS) ⚠️ Needs VPN
3. **Third-Party DNS Blocking** - ISP blocks port 53 to non-ISP servers ⚠️ MUST use VPN
4. **DPI (Deep Packet Inspection)** - ISP analyzes traffic ⚠️ Needs VPN

🚨 **If your ISP blocks third-party DNS (port 53), read [ISP_DNS_BLOCKING.md](ISP_DNS_BLOCKING.md) first!**

---

## 🎯 Quick Decision Guide

### Test 1: Check What's Blocked

**From your home computer (not VPS):**

```bash
# Test Cloudflare
ping 1.1.1.1

# Test DNS resolution
nslookup xbox.com

# Test Xbox.com access
curl -I https://www.xbox.com
```

**Results:**

| Test Result | What's Blocked | Solution |
|------------|----------------|----------|
| Ping works, nslookup works | Nothing yet | Just DoH may work |
| Ping fails, nslookup works | Cloudflare IPs | Use alternative DNS |
| nslookup fails | DNS blocking | DoH server needed |
| curl fails/slow | IP/DPI blocking | VPN required |

---

## 📋 Solution Matrix

### Scenario 1: DNS Blocking Only (Least Restrictive)

**Symptoms:**
- ✅ Can ping 8.8.8.8
- ❌ Can't resolve xbox.com
- ✅ Can access IPs directly

**Solution:** DoH Server Only

**Setup:**
```bash
# On VPS
cd /opt/doh-server
./deploy.sh

# On Xbox
# Set DNS to VPS IP
```

**Latency Impact:** ~5-10ms (DNS only)

---

### Scenario 2: Cloudflare/Google DNS Blocked (Common)

**Symptoms:**
- ❌ Can't ping 1.1.1.1 or 8.8.8.8
- ❌ DNS resolution fails
- ✅ Other internet works

**Solution:** DoH + Alternative DNS Providers

**Setup:**
```bash
# On VPS
cd /opt/doh-server
./deploy.sh

# Change DNS providers (already configured!)
# Using Quad9, OpenDNS, CleanBrowsing
docker-compose restart

# On Xbox
# Set DNS to VPS IP
```

**This is YOUR current setup!** ✅

**Latency Impact:** ~10-15ms

---

### Scenario 3: Xbox Live IPs Blocked (Most Restrictive)

**Symptoms:**
- ❌ DNS works but Xbox Live fails
- ❌ Can't connect to Xbox services
- ❌ Error codes on Xbox

**Solution:** Full VPN Tunnel

**Setup:**
```bash
# On VPS - DoH + VPN
cd /opt/doh-server
./deploy.sh
./setup-vpn.sh

# On Windows PC
# Install WireGuard, import config
# Share connection with Xbox

# OR on Router
# Configure WireGuard client
```

**Latency Impact:** ~30-60ms (all traffic through VPS)

---

## 🚀 Recommended Setup for Russia

### Phase 1: Start with DoH + Alternative DNS (Current)

**Already done!** Your configuration uses:
- ✅ Quad9 (Switzerland)
- ✅ OpenDNS (USA)
- ✅ CleanBrowsing (USA)

These avoid blocked Cloudflare/Google/AWS.

### Phase 2: Test Xbox Connectivity

```bash
# Deploy to VPS
cd /opt/doh-server
sudo ./deploy.sh

# Note your VPS IP

# Configure Xbox DNS to VPS IP

# Test connection
./test-dns.sh localhost
```

### Phase 3: If DNS Isn't Enough, Add VPN

```bash
# On VPS
./setup-vpn.sh

# Follow VPN_SETUP_GUIDE.md for client setup
```

---

## 🌍 VPS Location Recommendations

**Best Locations for Russia → Xbox Live:**

### Tier 1: Eastern Europe (Best Ping)
- 🥇 **Poland** (Warsaw) - 30-50ms
- 🥇 **Romania** (Bucharest) - 40-60ms
- 🥈 **Finland** (Helsinki) - 20-40ms
- 🥈 **Estonia** (Tallinn) - 25-45ms

### Tier 2: Western Europe
- 🥈 **Germany** (Frankfurt) - 50-70ms
- 🥈 **Netherlands** (Amsterdam) - 60-80ms
- 🥉 **UK** (London) - 70-90ms

### Tier 3: Northern Europe
- 🥉 **Sweden** (Stockholm) - 40-60ms
- 🥉 **Norway** (Oslo) - 50-70ms

### Not Recommended:
- ❌ USA (150-200ms)
- ❌ Asia (200-300ms)
- ❌ Australia (300-400ms)

---

## 🏢 VPS Provider Recommendations

### Best for Gaming/Low Latency:

#### 1. **Hetzner** (Germany, Finland)
- **Pros:** Excellent network, cheap, great peering
- **Cons:** May require ID verification
- **Ping from Russia:** 40-60ms
- **Price:** €4-5/month
- **Link:** https://www.hetzner.com/cloud

#### 2. **Vultr** (Multiple EU locations)
- **Pros:** Many locations, instant deploy, good for Russia
- **Cons:** Slightly pricier
- **Ping:** 50-80ms
- **Price:** $5-6/month
- **Link:** https://www.vultr.com

#### 3. **DigitalOcean** (Global)
- **Pros:** Reliable, good docs, stable
- **Cons:** Average network performance
- **Ping:** 60-90ms
- **Price:** $6/month
- **Link:** https://www.digitalocean.com

#### 4. **OVH** (France, Poland)
- **Pros:** DDoS protection, EU-based
- **Cons:** Complex interface
- **Ping:** 50-70ms
- **Price:** €3-4/month
- **Link:** https://www.ovhcloud.com

#### 5. **Contabo** (Germany)
- **Pros:** Very cheap, high bandwidth
- **Cons:** Shared resources, variable performance
- **Ping:** 60-80ms
- **Price:** €5/month
- **Link:** https://contabo.com

---

## 💳 Payment Considerations

### Payment Methods That Work from Russia:

1. **Cryptocurrency** (Bitcoin, etc.)
   - Works: Vultr, DigitalOcean, some resellers
   - Anonymous and sanctions-proof

2. **Foreign Credit Cards**
   - If you have access to non-Russian cards

3. **PayPal** (if accessible)
   - Works for some providers

4. **Wire Transfer**
   - Hetzner accepts SEPA transfers

5. **Local Resellers**
   - Some local companies resell VPS
   - Pay with Russian cards

---

## 🔧 Complete Deployment Steps

### Step 1: Get VPS

1. **Choose provider** (Hetzner recommended)
2. **Select region** (Frankfurt or Helsinki)
3. **Choose plan:**
   - Minimum: 1 vCPU, 1GB RAM, 20GB disk
   - Recommended: 2 vCPU, 2GB RAM (for VPN)
4. **OS:** Ubuntu 22.04 or Debian 11
5. **Note SSH details**

### Step 2: Initial VPS Setup

```bash
# Connect to VPS
ssh root@YOUR_VPS_IP

# Update system
apt update && apt upgrade -y

# Set timezone (optional)
timedatectl set-timezone Europe/Moscow

# Install basics
apt install -y curl wget git nano htop
```

### Step 3: Upload and Deploy

```bash
# From your local machine
cd /home/wars09/Cursor/doh
tar -czf doh-server.tar.gz *
scp doh-server.tar.gz root@YOUR_VPS_IP:/opt/

# On VPS
ssh root@YOUR_VPS_IP
cd /opt
tar -xzf doh-server.tar.gz
mv /opt/home/wars09/Cursor/doh /opt/doh-server  # Adjust path as needed
cd /opt/doh-server

# Deploy DoH server
chmod +x *.sh
./deploy.sh
```

### Step 4: Configure Xbox

**See XBOX_SETUP_GUIDE.md for detailed steps**

Quick version:
1. Settings → Network → Advanced → DNS Settings → Manual
2. Primary DNS: YOUR_VPS_IP
3. Secondary DNS: YOUR_VPS_IP
4. Test connection

### Step 5: Test Everything

```bash
# On VPS
./test-dns.sh localhost

# From home PC
./test-dns.sh YOUR_VPS_IP

# On Xbox
# Network → Test connection
```

### Step 6: If Needed, Setup VPN

```bash
# On VPS
./setup-vpn.sh

# Follow prompts
# Download client.conf
# See VPN_SETUP_GUIDE.md for client setup
```

---

## 🧪 Detailed Testing Procedure

### Test 1: VPS Can Reach DNS Providers

```bash
ssh root@YOUR_VPS_IP
cd /opt/doh-server

# Test Quad9
curl -v https://dns.quad9.net/dns-query

# Test OpenDNS
curl -v https://doh.opendns.com/dns-query

# Should get HTTP 200 or 400, not timeout
```

### Test 2: DoH Server Works

```bash
# On VPS
docker-compose logs doh-server | tail -20

# Should show no errors
```

### Test 3: DNS Proxy Works

```bash
# On VPS
dig @localhost xbox.com

# Should return IP addresses
```

### Test 4: From Your Home

```bash
# Windows
nslookup xbox.com YOUR_VPS_IP

# Linux/Mac
dig @YOUR_VPS_IP xbox.com

# Should resolve
```

### Test 5: Xbox Connection

1. Configure Xbox DNS
2. Test network connection
3. Try opening Xbox Store
4. Check for any error codes

---

## 📊 Monitoring Performance

### Check DNS Query Times

```bash
# On VPS
docker-compose logs dns-proxy | grep "Query time"
```

### Monitor System Resources

```bash
ssh root@YOUR_VPS_IP
htop  # Check CPU/RAM usage

# Should be low (<20% CPU, <500MB RAM)
```

### Check Bandwidth Usage

```bash
# Install vnstat
apt install -y vnstat
vnstat -l  # Live traffic monitor
```

---

## 🛠️ Common Issues in Russia

### Issue 1: VPS SSH Connection Slow/Drops

**Cause:** Russian ISP throttling SSH

**Solutions:**
1. Use different SSH port:
```bash
# On VPS
nano /etc/ssh/sshd_config
# Change Port 22 to Port 2222
systemctl restart sshd

# Connect with
ssh -p 2222 root@YOUR_VPS_IP
```

2. Use SSH over TLS (stunnel)

### Issue 2: DNS Queries Timing Out

**Cause:** Firewall blocking UDP/53

**Solution:**
```bash
# On VPS
ufw status
ufw allow 53/udp
ufw allow 53/tcp
```

### Issue 3: VPN Connects but Slow

**Cause:** VPS location too far or poor routing

**Solutions:**
1. Change VPS to closer location
2. Try different VPS provider
3. Enable BBR congestion control (already in deploy.sh)

### Issue 4: Works Sometimes, Fails Others

**Cause:** ISP using dynamic blocking (rotating blocks)

**Solutions:**
1. Use multiple VPS locations
2. Setup automatic failover
3. Use VPN for consistent routing

---

## 🔄 Maintenance Schedule

### Daily:
- Check Xbox can connect
- Monitor for issues

### Weekly:
```bash
ssh root@YOUR_VPS_IP
docker-compose logs --tail=100
# Check for errors
```

### Monthly:
```bash
ssh root@YOUR_VPS_IP
cd /opt/doh-server

# Update system
apt update && apt upgrade -y

# Update Docker images
docker-compose pull
docker-compose up -d

# Reboot if kernel updated
reboot
```

### When Xbox Live Fails:
```bash
# Check services
docker-compose ps

# Restart services
docker-compose restart

# Check logs
docker-compose logs -f

# Test DNS
./test-dns.sh localhost
```

---

## 💰 Cost Estimation

### Monthly Costs:

**DNS Only:**
- VPS: €4-6/month
- Bandwidth: Included (DNS uses minimal data)
- **Total: €4-6/month (~400-600 RUB)**

**DNS + VPN:**
- VPS: €6-10/month (need more resources)
- Bandwidth: ~50-100GB for gaming
- **Total: €6-10/month (~600-1000 RUB)**

**Game Download Considerations:**
- Large game downloads through VPN use VPS bandwidth
- Solution: Temporarily disable VPN for downloads, use only for gameplay

---

## 🔐 Security & Privacy

### Encryption Status:

**With DoH Only:**
- ✅ DNS queries encrypted (HTTPS)
- ❌ Game traffic not encrypted (but not needed)
- ✅ ISP can't see what domains you're resolving

**With VPN:**
- ✅ All traffic encrypted
- ✅ Complete privacy from ISP
- ✅ ISP only sees encrypted tunnel to VPS

### Privacy Tips:

1. **Use DoH for daily browsing too**
2. **VPN only when needed** (for Xbox Live)
3. **Don't use VPS for illegal activities** (they have your payment info)
4. **Choose VPS in privacy-friendly countries** (Switzerland, Netherlands)

---

## 📞 Getting Help

### Check Logs First:

```bash
# DoH server logs
docker-compose logs doh-server

# DNS proxy logs
docker-compose logs dns-proxy

# System logs
journalctl -xe
```

### Common Error Messages:

| Error | Meaning | Fix |
|-------|---------|-----|
| `connection refused` | Service not running | `docker-compose up -d` |
| `timeout` | Firewall blocking | `ufw allow 53` |
| `no route to host` | Network issue | Check VPS network |
| `certificate error` | Upstream DNS issue | Change DNS provider |

---

## ✅ Success Checklist

Before considering setup complete:

- [ ] VPS accessible via SSH
- [ ] Docker containers running (`docker ps`)
- [ ] DNS test passes from VPS (`./test-dns.sh localhost`)
- [ ] DNS test passes from home (`./test-dns.sh VPS_IP`)
- [ ] Xbox DNS configured to VPS IP
- [ ] Xbox network test shows "Connected"
- [ ] Can access Xbox Store
- [ ] Can play online multiplayer
- [ ] Latency acceptable (<100ms to Xbox servers)
- [ ] Configuration backed up

---

## 🎮 Final Words

**Your current setup should work for most scenarios in Russia!**

The configuration uses:
- ✅ Non-blocked DNS providers (Quad9, OpenDNS)
- ✅ Encrypted DNS queries (DoH)
- ✅ Low latency (DNS-only routing)
- ✅ Simple Xbox configuration

**Start here, add VPN only if needed.**

Good luck and happy gaming! 🎮🚀

---

**Files Reference:**
- Main setup: `README.md`
- Xbox config: `XBOX_SETUP_GUIDE.md`
- VPN setup: `VPN_SETUP_GUIDE.md`
- DNS providers: `DNS_PROVIDERS.md`
- Quick start: `QUICKSTART.md`


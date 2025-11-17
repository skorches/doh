# Smart DNS Setup for Xbox + Discord

## 🎯 What This Does

This setup makes your DoH server work like **xbox-dns.ru** by implementing **Smart DNS + SNI Proxy**:

1. **Smart DNS**: Your DoH returns VPS IP for Xbox/Discord domains instead of real IPs
2. **SNI Proxy**: HAProxy on VPS forwards Xbox/Discord traffic to real servers
3. **Bypass Blocking**: ISP can't block Xbox/Discord because traffic goes through your VPS

```
Xbox/Discord Query → Keenetic → Cloudflare → Your DoH → Returns VPS IP
Xbox/Discord connects to VPS IP → HAProxy forwards → Real Xbox/Discord Servers
```

---

## 📋 Quick Setup

### Step 1: Setup HAProxy (SNI Proxy)

On your VPS, run:

```bash
cd /root/doh
./setup-xbox-proxy.sh
```

This will:
- ✅ Install HAProxy
- ✅ Configure SNI routing for Xbox + Discord domains
- ✅ Create hosts file pointing Xbox/Discord → VPS IP
- ✅ Open firewall ports (80, 443, 3074, 3544, 8404)

### Step 2: Integrate with DoH

```bash
cd /root/doh
./integrate-coredns-smartdns.sh
```

This will:
- ✅ Add CoreDNS Smart DNS layer
- ✅ Configure DoH to return VPS IP for Xbox/Discord
- ✅ Update docker-compose.yml
- ✅ Restart containers

### Step 3: Test

```bash
cd /root/doh
./test-smartdns.sh
```

Expected results:
- ✅ `xboxlive.com` → Returns VPS IP
- ✅ `discord.com` → Returns VPS IP
- ✅ `google.com` → Returns real IP

---

## 🔍 How It Works

### DNS Resolution Flow

```
Xbox queries xboxlive.com:

1. Keenetic DoH client
   ↓ (HTTPS)
2. Cloudflare Proxy (bypass.440.info)
   ↓
3. Nginx on VPS (port 443)
   ↓
4. doh-backend container
   ↓
5. CoreDNS Smart DNS (checks xbox-hosts file)
   ↓
6. Returns: 91.235.234.92 (VPS IP) ✅
```

### Traffic Flow

```
Xbox connects to xboxlive.com (91.235.234.92):

1. Xbox → xboxlive.com:443 → 91.235.234.92:443
   ↓
2. HAProxy on VPS (port 443)
   ↓ (SNI inspection: sees "xboxlive.com")
3. HAProxy forwards to real xboxlive.com:443
   ↓
4. Real Xbox Live servers
   ↓
5. Response back through HAProxy → Xbox
```

---

## 🎮 Supported Services

### Xbox Live
- xboxlive.com
- *.xboxservices.com
- xbox.com
- login.live.com
- catalog.gamepass.com
- All authentication and gaming services

### Discord
- discord.com
- discord.gg
- gateway.discord.gg
- cdn.discordapp.com
- media.discordapp.net
- All Discord voice and text services

### Microsoft Connectivity
- dns.msftncsi.com
- www.msftconnecttest.com
- Teredo (IPv6 tunneling)

---

## 🛠️ Management

### View HAProxy Stats

```bash
# Open in browser:
http://YOUR_VPS_IP:8404/stats
```

Shows:
- Active connections
- Backend server status
- Traffic statistics
- Error rates

### View DoH Logs

```bash
cd /root/doh
docker-compose logs -f doh-backend coredns-smartdns
```

### View HAProxy Logs

```bash
journalctl -u haproxy -f
```

---

## ✅ Verify Setup

### 1. DNS Resolution

```bash
# Should return VPS IP
curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'

# Should return VPS IP
curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=discord.com&type=A'

# Should return real IP
curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=google.com&type=A'
```

### 2. HAProxy Running

```bash
systemctl status haproxy
```

### 3. Containers Running

```bash
cd /root/doh
docker-compose ps
```

Should show:
- doh-nginx (running)
- doh-backend (running)
- doh-upstream (running)
- coredns-smartdns (running)

---

## 🔧 Adding More Services

Want to add more services (Netflix, YouTube, etc.)?

### Edit Hosts File

```bash
cd /root/doh
nano coredns/xbox-hosts
```

Add:
```
91.235.234.92 netflix.com
91.235.234.92 www.netflix.com
```

### Update HAProxy

```bash
nano /etc/haproxy/haproxy.cfg
```

Add in frontend section:
```
use_backend netflix if { req_ssl_sni -m end netflix.com }
```

Add backend:
```
backend netflix
    mode tcp
    balance roundrobin
    option tcp-check
    server-template netflix 10 netflix.com:443 check resolvers mydns resolve-prefer ipv4
```

### Restart Services

```bash
systemctl restart haproxy
docker-compose restart coredns-smartdns
```

---

## 🐛 Troubleshooting

### Xbox Still Can't Connect

1. **Check DNS Resolution**:
   ```bash
   ./test-smartdns.sh
   ```

2. **Check HAProxy**:
   ```bash
   systemctl status haproxy
   journalctl -u haproxy -n 50
   ```

3. **Check Firewall**:
   ```bash
   ufw status
   ```

4. **Check Keenetic DoH**:
   - Make sure DoH is enabled
   - URL: `https://bypass.440.info/dns-query`
   - Make sure Keenetic DNS proxy is running

### Discord Not Working

Same troubleshooting steps as Xbox.

### HAProxy Not Starting

```bash
# Test config
haproxy -c -f /etc/haproxy/haproxy.cfg

# Check logs
journalctl -u haproxy -n 100
```

### CoreDNS Not Resolving

```bash
# Check logs
docker-compose logs coredns-smartdns

# Test directly
docker exec coredns-smartdns nslookup xboxlive.com localhost
```

---

## 📊 Performance

### Expected Latency

- DoH query: ~20-50ms
- HAProxy proxy: +5-10ms
- Total added latency: ~25-60ms

### Bandwidth

HAProxy uses minimal bandwidth:
- Only proxies connection setup (TLS handshake)
- Passes through all data directly
- No performance impact on gameplay

---

## 🔐 Security

### What ISP Sees

- ❌ **Can't see**: DNS queries (encrypted via DoH)
- ❌ **Can't see**: Which Xbox/Discord services you use
- ✅ **Can see**: You're connecting to your VPS
- ✅ **Can see**: Amount of data transferred

### Cloudflare Proxy

Your VPS is behind Cloudflare proxy:
- ISP can't block your VPS IP directly
- ISP sees Cloudflare IPs (can't block without breaking internet)
- SSL certificates are valid (Origin certificates)

---

## 📝 Configuration Files

### Key Files

```
/root/doh/
├── docker-compose.yml              # Docker services
├── coredns/
│   ├── Corefile                    # CoreDNS config
│   └── xbox-hosts                  # Smart DNS mappings
├── nginx/
│   └── conf.d/
│       └── doh.conf               # Nginx HTTPS config
└── /etc/haproxy/haproxy.cfg       # HAProxy SNI proxy
```

### Backup

```bash
cd /root/doh
tar -czf smartdns-backup-$(date +%s).tar.gz docker-compose.yml coredns/ nginx/
cp /etc/haproxy/haproxy.cfg haproxy-backup-$(date +%s).cfg
```

---

## 🚀 Next Steps

1. **Test on Xbox**: Try connecting to Xbox Live
2. **Test Discord**: Open Discord app on Xbox
3. **Monitor HAProxy**: Watch stats at http://VPS_IP:8404/stats
4. **Add more services**: Netflix, YouTube, etc.

---

## ℹ️ Support

If you encounter issues:

1. Run: `./test-smartdns.sh`
2. Check: HAProxy stats
3. Review: Docker logs
4. Verify: Keenetic DoH configuration

The setup should work like xbox-dns.ru now! 🎮


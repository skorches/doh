# Alternative DNS Providers for Russia

## ⚠️ ISP Blocking Considerations

If your ISP blocks Cloudflare (1.1.1.1) and AWS services, you need alternative DNS providers.

---

## ✅ Recommended Providers (Not Blocked in Russia)

### 1. **Quad9** (Recommended)
- **DoH URL**: `https://dns.quad9.net/dns-query`
- **Regular DNS**: `9.9.9.9`, `149.112.112.112`
- **Location**: Switzerland (neutral country)
- **Features**: Security filtering, privacy-focused
- **Speed**: Good global performance

### 2. **OpenDNS** (Cisco)
- **DoH URL**: `https://doh.opendns.com/dns-query`
- **Regular DNS**: `208.67.222.222`, `208.67.220.220`
- **Location**: USA (Cisco infrastructure)
- **Features**: Fast, reliable
- **Speed**: Excellent

### 3. **CleanBrowsing**
- **DoH URL**: `https://doh.cleanbrowsing.org/doh/security-filter/`
- **Regular DNS**: `185.228.168.9`, `185.228.169.9`
- **Location**: USA
- **Features**: Family-friendly filtering
- **Speed**: Good

### 4. **AdGuard DNS** (Unfiltered)
- **DoH URL**: `https://dns-unfiltered.adguard.com/dns-query`
- **Regular DNS**: `94.140.14.140`, `94.140.14.141`
- **Location**: Cyprus
- **Features**: No filtering on unfiltered version
- **Speed**: Very good from Europe

### 5. **DNS.SB**
- **DoH URL**: `https://doh.dns.sb/dns-query`
- **Regular DNS**: `185.222.222.222`, `185.184.222.222`
- **Location**: Germany, Netherlands
- **Features**: Privacy-focused, no logs
- **Speed**: Excellent for Europe

---

## 🚫 Providers to AVOID (Likely Blocked)

### ❌ Cloudflare
- `1.1.1.1`, `1.0.0.1`
- **Status**: Blocked by many Russian ISPs

### ❌ Google DNS
- `8.8.8.8`, `8.8.4.4`
- **Status**: Often throttled or blocked

### ❌ AWS Route53
- Various IPs
- **Status**: AWS infrastructure blocked

---

## 🔧 How to Change DNS Provider

### Method 1: Use the Script (Easy)

```bash
cd /opt/doh-server
./update-upstream.sh
```

Select from menu or enter custom DoH URLs.

### Method 2: Manual Edit

Edit `docker-compose.yml`:

```yaml
environment:
  - TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query
```

Then restart:
```bash
docker-compose down
docker-compose up -d
```

---

## 🧪 Testing DNS Providers

Test which providers work from your VPS:

```bash
# Test Quad9
curl -I https://dns.quad9.net/dns-query

# Test OpenDNS
curl -I https://doh.opendns.com/dns-query

# Test AdGuard
curl -I https://dns-unfiltered.adguard.com/dns-query
```

If you get HTTP 200 or 400 (not timeout/connection refused), it works!

---

## 🌍 Regional Recommendations

### From Russia with VPS in:

**Western Europe (Germany, Netherlands):**
- Primary: Quad9 (Switzerland)
- Secondary: DNS.SB (Germany)

**Eastern Europe (Poland, Romania):**
- Primary: AdGuard (Cyprus)
- Secondary: Quad9

**USA East Coast:**
- Primary: OpenDNS (Cisco)
- Secondary: CleanBrowsing

**USA West Coast:**
- Primary: OpenDNS
- Secondary: Quad9

---

## 💡 Pro Tips

### Use Multiple Providers

Always configure 2-3 providers for redundancy:

```yaml
TUNNEL_DNS_UPSTREAM=https://dns.quad9.net/dns-query,https://doh.opendns.com/dns-query,https://doh.dns.sb/dns-query
```

### Test Latency

```bash
# From your VPS
time curl -s https://dns.quad9.net/dns-query -H "Content-Type: application/dns-message" --data-binary "$(echo -ne '\x00\x00\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x04xbox\x03com\x00\x00\x01\x00\x01')" > /dev/null
```

Lower time = better performance.

### Check for Blocks

If a provider suddenly stops working:

```bash
# Check logs
docker-compose logs doh-server | grep -i error

# Test directly
curl -v https://dns.quad9.net/dns-query
```

---

## 🔐 Privacy Comparison

| Provider | Logging | Location | Filtering |
|----------|---------|----------|-----------|
| Quad9 | Minimal | Switzerland | Malware |
| OpenDNS | Yes | USA | Optional |
| CleanBrowsing | Minimal | USA | Yes |
| AdGuard | No logs | Cyprus | Optional |
| DNS.SB | No logs | Germany | No |

**For maximum privacy**: DNS.SB or AdGuard Unfiltered

---

## 🚀 Performance Testing

Run this script on your VPS:

```bash
#!/bin/bash
echo "Testing DNS Provider Performance..."

providers=(
    "dns.quad9.net"
    "doh.opendns.com"
    "doh.dns.sb"
    "dns-unfiltered.adguard.com"
)

for provider in "${providers[@]}"; do
    echo -n "Testing $provider: "
    time=$(curl -o /dev/null -s -w '%{time_total}\n' https://$provider/dns-query)
    echo "${time}s"
done
```

---

## 📞 If Nothing Works

If all DNS providers are blocked from your VPS location, you need to:

1. **Use VPN** - Route all traffic through VPS (see `setup-vpn.sh`)
2. **Change VPS location** - Move to a region with less restrictions
3. **Use DNS over Tor** - Advanced option (not covered here)

---

## Current Configuration

Your setup is currently using:
- **Quad9**: `https://dns.quad9.net/dns-query`
- **OpenDNS**: `https://doh.opendns.com/dns-query`
- **CleanBrowsing**: `https://doh.cleanbrowsing.org/doh/security-filter/`

These should work from most VPS locations!


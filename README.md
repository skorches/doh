# Xbox Smart DNS + DoH Server

DNS over HTTPS (DoH) server with Smart DNS proxy for Xbox Live connectivity in geo-blocked regions.

## 🎯 Features

- **DoH Server**: Encrypted DNS queries over HTTPS
- **Smart DNS**: Returns VPS IP for Xbox/Discord domains (bypasses geo-blocks)
- **SNI Proxy**: Forwards Xbox traffic to real servers through your VPS
- **Bypass ISP Blocks**: Works even when ISP blocks Cloudflare/AWS

## 📁 Project Structure

```
.
├── docker-compose.yml      # Main Docker Compose config
├── coredns/                # CoreDNS Smart DNS config
├── nginx/                  # Nginx DoH frontend config
├── ssl/                    # SSL certificates
├── scripts/
│   ├── setup/             # Initial setup scripts
│   ├── maintenance/       # Maintenance scripts
│   └── analysis/          # Traffic analysis tools
├── docs/                   # Documentation
└── archive/                # Old/obsolete files
```

## 🚀 Quick Start

### 1. Initial Setup

```bash
# On your VPS
cd /root/doh
./scripts/setup/deploy-smartdns-complete.sh
```

### 2. Configure Router

**Keenetic Router:**
- Internet → DNS → Use DNS over HTTPS (DoH)
- URL: `https://bypass.440.info/dns-query`

### 3. Test

```bash
# Test Smart DNS
curl -H 'accept: application/dns-json' 'https://bypass.440.info/dns-query?name=xboxlive.com&type=A'
# Should return your VPS IP (91.235.234.92)
```

## 📚 Documentation

- [Smart DNS Setup](docs/SMART_DNS_SETUP.md)
- [Xbox Configuration](docs/XBOX_SETUP_GUIDE.md)
- [Domain Setup](docs/DOMAIN_SETUP_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## 🔧 Maintenance

### Add Xbox Domains from Wireshark

```bash
# Analyze Wireshark capture
./scripts/analysis/analyze-wireshark.sh capture.pcap

# Add domains
./scripts/maintenance/add-wireshark-domains-filtered.sh wireshark-analysis-*/xbox-domains.txt
```

### Optimize Hosts File

```bash
./scripts/maintenance/optimize-xbox-hosts.sh
```

## 🛠️ Services

- **Nginx**: DoH frontend (port 8443 internal, proxied by SNIProxy on 443)
- **DoH Backend**: satishweb/doh-server (port 8053)
- **CoreDNS**: Smart DNS layer (returns VPS IP for Xbox domains)
- **Cloudflared**: Upstream DoH (port 5053)
- **SNIProxy**: SNI proxy for Xbox traffic (port 443)

## 📝 License

MIT

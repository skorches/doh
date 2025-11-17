# 📖 Documentation Index

## 🎯 Start Here

**New user from Russia?** → **[START_HERE.md](START_HERE.md)** ⭐

This is your entry point. Everything else is reference material.

---

## 📚 Documentation Structure

### 🚀 Setup Guides (Step-by-Step)

1. **[START_HERE.md](START_HERE.md)** - Absolute beginner guide (recommended)
2. **[ISP_DNS_BLOCKING.md](ISP_DNS_BLOCKING.md)** - 🚨 If ISP blocks third-party DNS (MUST READ)
3. **[QUICKSTART.md](QUICKSTART.md)** - 5-minute quick setup
4. **[RUSSIA_SETUP.md](RUSSIA_SETUP.md)** - Complete Russia-specific guide with ISP blocking
5. **[README.md](README.md)** - Full technical documentation

### 🎮 Configuration Guides

6. **[XBOX_SETUP_GUIDE.md](XBOX_SETUP_GUIDE.md)** - Detailed Xbox configuration
   - Direct Xbox DNS setup
   - Router configuration
   - Troubleshooting Xbox issues

7. **[VPN_SETUP_GUIDE.md](VPN_SETUP_GUIDE.md)** - WireGuard VPN setup (if DNS isn't enough)
   - Windows PC as gateway
   - Router VPN configuration
   - MikroTik/OpenWRT setup

8. **[ALTERNATIVES.md](ALTERNATIVES.md)** - Alternatives to PC + WireGuard
   - DoH on port 443
   - GL.iNet routers
   - OpenVPN setup
   - Other options

9. **[GLINET_SETUP.md](GLINET_SETUP.md)** - GL.iNet router complete guide
   - No PC required
   - Step-by-step setup
   - Gaming optimizations

### 🔧 Reference Material

7. **[DNS_PROVIDERS.md](DNS_PROVIDERS.md)** - Alternative DNS providers
   - Non-blocked providers for Russia
   - Performance comparison
   - How to switch providers

8. **[Makefile](Makefile)** - Command reference
   - Quick commands for common tasks

---

## 🗺️ Setup Flow Chart

```
┌─────────────────────────────────────────────────┐
│          Do you have a VPS?                     │
│                                                 │
│  NO → Buy VPS (see RUSSIA_SETUP.md)           │
│  YES → Continue below                          │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│       Deploy DoH Server on VPS                  │
│                                                 │
│  → Upload files to VPS                         │
│  → Run: ./deploy.sh                            │
│  → Note VPS IP address                         │
│                                                 │
│  Guide: START_HERE.md or QUICKSTART.md         │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│       Configure Xbox                            │
│                                                 │
│  → Set DNS to VPS IP                           │
│  → Test connection                             │
│                                                 │
│  Guide: XBOX_SETUP_GUIDE.md                    │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│       Does Xbox Live work?                      │
│                                                 │
│  YES → ✅ Done! Enjoy gaming!                  │
│  NO  → Continue below                          │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│       Setup VPN for Full Traffic Routing        │
│                                                 │
│  → Run: ./setup-vpn.sh on VPS                  │
│  → Configure client (PC/Router)                │
│  → Route Xbox through VPN                      │
│                                                 │
│  Guide: VPN_SETUP_GUIDE.md                     │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│       ✅ Complete! Xbox Live accessible         │
└─────────────────────────────────────────────────┘
```

---

## 📁 File Structure

### Configuration Files
```
docker-compose.yml       - Main Docker services configuration
coredns/Corefile        - DNS proxy settings
coredns/xbox-hosts      - Custom DNS overrides
env.example             - Environment variables template
wireguard/wg0.conf.template - VPN configuration template
```

### Scripts
```
deploy.sh               - Main deployment script (DoH server)
setup-vpn.sh           - VPN server setup script
test-dns.sh            - DNS testing utility
update-upstream.sh     - Change DNS providers
Makefile               - Quick command shortcuts
```

### Documentation
```
START_HERE.md          - Beginner entry point ⭐
QUICKSTART.md          - Fast setup guide
RUSSIA_SETUP.md        - Russia-specific complete guide
README.md              - Full technical documentation
XBOX_SETUP_GUIDE.md    - Xbox configuration details
VPN_SETUP_GUIDE.md     - VPN setup details
DNS_PROVIDERS.md       - DNS provider reference
INDEX.md               - This file
```

---

## 🎯 Common Scenarios

### Scenario 1: "I just want to play Xbox Live"
1. Read: **START_HERE.md**
2. Deploy with: `./deploy.sh`
3. Configure Xbox DNS
4. Done!

### Scenario 2: "DNS doesn't work, still blocked"
1. Read: **VPN_SETUP_GUIDE.md**
2. Run: `./setup-vpn.sh`
3. Setup VPN client
4. Done!

### Scenario 3: "I want to understand everything"
1. Read: **RUSSIA_SETUP.md** (comprehensive)
2. Then: **README.md** (technical details)
3. Reference others as needed

### Scenario 4: "DNS is slow, want alternatives"
1. Read: **DNS_PROVIDERS.md**
2. Run: `./update-upstream.sh`
3. Choose provider
4. Done!

### Scenario 5: "Can't configure Xbox, need router setup"
1. Read: **XBOX_SETUP_GUIDE.md**
2. Find your router section
3. Configure router DNS
4. Done!

---

## 🚦 Troubleshooting Index

### VPS Issues
- **Can't SSH**: RUSSIA_SETUP.md → "Common Issues" → SSH connection
- **Services won't start**: README.md → "Troubleshooting"
- **Firewall blocking**: deploy.sh handles this automatically

### DNS Issues
- **Resolution fails**: DNS_PROVIDERS.md → "Testing DNS Providers"
- **Slow queries**: README.md → "Performance Tuning"
- **Provider blocked**: DNS_PROVIDERS.md → Full list of alternatives

### Xbox Issues
- **Can't connect**: XBOX_SETUP_GUIDE.md → "Troubleshooting"
- **NAT Type Strict**: XBOX_SETUP_GUIDE.md → Port forwarding
- **High latency**: RUSSIA_SETUP.md → VPS location recommendations

### VPN Issues
- **Connection fails**: VPN_SETUP_GUIDE.md → "Troubleshooting"
- **No internet through VPN**: VPN_SETUP_GUIDE.md → IP forwarding
- **High ping**: VPN_SETUP_GUIDE.md → "Performance Tuning"

---

## 💡 Quick Commands Reference

```bash
# Deploy everything
make deploy

# Start services
make start

# Stop services
make stop

# View logs
make logs

# Test DNS
make test

# Update services
make update

# Show service status
make status
```

See **[Makefile](Makefile)** for all commands.

---

## 📞 Getting Help

### Check logs first:
```bash
docker-compose logs -f
```

### Test DNS:
```bash
./test-dns.sh localhost
```

### Check service status:
```bash
docker-compose ps
```

### Common error solutions:
- See specific guide's troubleshooting section
- RUSSIA_SETUP.md has comprehensive troubleshooting

---

## ✅ Success Checklist

Before considering setup complete:

- [ ] VPS deployed and accessible
- [ ] Docker containers running
- [ ] DNS resolves from VPS
- [ ] DNS resolves from home
- [ ] Xbox configured
- [ ] Xbox Live connects
- [ ] Online gaming works
- [ ] Acceptable latency

---

## 🔄 Maintenance

### Daily
- Verify Xbox Live works

### Weekly
- Check logs: `make logs`

### Monthly
- Update system: `make update`
- Review RUSSIA_SETUP.md maintenance section

---

## 📊 Documentation Stats

- **Total Guides**: 8 documents
- **Setup Scripts**: 4 scripts
- **Configuration Files**: 4 files
- **Total Lines**: ~2500+ lines of documentation
- **Languages**: English
- **Difficulty**: Beginner to Advanced

---

## 🎓 Learning Path

### Beginner
1. START_HERE.md
2. QUICKSTART.md
3. XBOX_SETUP_GUIDE.md

### Intermediate
1. RUSSIA_SETUP.md
2. DNS_PROVIDERS.md
3. README.md

### Advanced
1. VPN_SETUP_GUIDE.md
2. docker-compose.yml
3. coredns/Corefile

---

## 🌟 Recommended Reading Order

**For most users:**
1. START_HERE.md ⭐
2. XBOX_SETUP_GUIDE.md
3. Done!

**If issues arise:**
4. RUSSIA_SETUP.md (troubleshooting)
5. DNS_PROVIDERS.md (if DNS issues)
6. VPN_SETUP_GUIDE.md (if DNS alone doesn't work)

**For deep understanding:**
7. README.md (technical details)

---

**Ready? Start with [START_HERE.md](START_HERE.md)! 🚀**


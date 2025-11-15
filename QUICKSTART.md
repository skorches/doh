# 🚀 Quick Start Guide - 5 Minutes to Xbox Live

## For Users in Russia Wanting Xbox Network Access

This guide will get you up and running in 5 minutes.

---

## ⚡ Super Quick Setup

### On Your VPS (Linux server):

```bash
# 1. Upload files to VPS
scp -r /home/wars09/Cursor/doh root@YOUR-VPS-IP:/opt/doh-server

# 2. SSH into VPS
ssh root@YOUR-VPS-IP

# 3. Run one command
cd /opt/doh-server && chmod +x deploy.sh && ./deploy.sh
```

**That's it for the server!** 

Copy the VPS IP shown at the end.

---

### On Your Xbox:

1. **Settings → General → Network Settings**
2. **Advanced Settings → DNS Settings → Manual**
3. **Primary DNS**: `YOUR-VPS-IP`
4. **Secondary DNS**: `YOUR-VPS-IP`
5. **Test network connection**

**Done!** You should now be able to access Xbox Live.

---

## 🧪 Quick Test

On your computer (same network as Xbox):

```bash
# Windows
nslookup xbox.com YOUR-VPS-IP

# Linux/Mac
dig @YOUR-VPS-IP xbox.com
```

Should return an IP address = Working! ✅

---

## ❓ Not Working?

### Check VPS is running:
```bash
ssh root@YOUR-VPS-IP
docker ps
```

Should see 3 containers running.

### Check Xbox can reach VPS:
On Xbox, test network connection. If fails:
- Double-check VPS IP is correct
- Verify VPS firewall allows port 53

### View logs:
```bash
ssh root@YOUR-VPS-IP
cd /opt/doh-server
docker-compose logs -f
```

---

## 📚 Full Documentation

- **Complete Setup**: See `README.md`
- **Xbox Configuration**: See `XBOX_SETUP_GUIDE.md`
- **Troubleshooting**: See README.md troubleshooting section

---

## 💡 Tips

- **Lower ping**: Choose VPS in Western Europe (Germany, Netherlands)
- **Faster DNS**: Run `./update-upstream.sh` to change DNS provider
- **Check status**: Run `make status` to see if services are running

---

## 🎮 What This Does

- Your Xbox sends DNS requests to your VPS instead of local DNS
- VPS resolves domains via DNS-over-HTTPS (encrypted, hard to block)
- Xbox gets responses and connects to Xbox Live normally
- Bypasses Russian geo-blocking at DNS level

---

**Enjoy gaming! 🎮🚀**


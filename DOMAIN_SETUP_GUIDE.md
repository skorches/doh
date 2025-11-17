# Domain Setup Guide for DoH Server

## 🛒 Step 1: Buy a Domain

### Recommended Registrars

**Cheapest Options:**
- **Cloudflare** - $2-3/year (.xyz, .site, .online)
  - https://www.cloudflare.com/products/registrar/
  - Also provides DNS management (needed)

- **Namecheap** - $3-9/year
  - https://www.namecheap.com
  - Easy to use, good support

- **Porkbun** - $3-5/year
  - https://porkbun.com
  - Very cheap, simple interface

### Domain Suggestions

**Pick any of these cheap extensions:**
- `.xyz` - $2-3/year
- `.site` - $2-3/year
- `.online` - $3-5/year
- `.space` - $3-5/year
- `.com` - $9-12/year (more professional)

**Example domain names:**
- `mydoh.xyz`
- `xboxdns.site`
- `gaming.online`
- `privateDNS.xyz`
- Anything you like!

---

## 📋 Step 2: Configure Domain DNS

After buying domain, you need to point it to your VPS.

### Your VPS IP
```
91.235.234.92
```

### In Your Domain Registrar Panel

**Create an A record:**

| Type | Name | Content/Value | TTL |
|------|------|---------------|-----|
| A | doh | 91.235.234.92 | 300 |

**This creates:** `doh.yourdomain.com → 91.235.234.92`

---

### Example: Cloudflare DNS Setup

1. **Login to Cloudflare**
2. **Click your domain**
3. **DNS → Records**
4. **Add record:**
   - Type: `A`
   - Name: `doh`
   - IPv4 address: `91.235.234.92`
   - Proxy status: **DNS only** (grey cloud, NOT orange)
   - TTL: Auto
5. **Save**

---

### Example: Namecheap DNS Setup

1. **Login to Namecheap**
2. **Domain List → Manage**
3. **Advanced DNS**
4. **Add New Record:**
   - Type: `A Record`
   - Host: `doh`
   - Value: `91.235.234.92`
   - TTL: Automatic
5. **Save**

---

## ⏱️ Step 3: Wait for DNS Propagation

**Wait 5-15 minutes** for DNS to propagate worldwide.

### Test if DNS is working:

```bash
# From your local computer
ping doh.yourdomain.com

# Should show 91.235.234.92
```

**Or use online tool:**
- https://dnschecker.org
- Enter: `doh.yourdomain.com`
- Should show `91.235.234.92`

---

## 🚀 Step 4: Run Setup Script on VPS

Once DNS is working (ping resolves to your VPS IP):

```bash
# SSH to VPS
ssh root@91.235.234.92

# Navigate to directory
cd /root/doh

# Make script executable
chmod +x setup-letsencrypt.sh

# Run setup (replace with YOUR domain)
sudo ./setup-letsencrypt.sh doh.yourdomain.com
```

**Replace `doh.yourdomain.com` with YOUR actual domain!**

---

## ✅ Step 5: Configure Keenetic

After setup completes, in Keenetic:

**DoH URL:**
```
https://doh.yourdomain.com/dns-query
```

**Save and test!**

---

## 📝 Complete Example

**Let's say you bought: `mygaming.xyz`**

### 1. DNS Configuration:
```
A record: doh → 91.235.234.92
Creates: doh.mygaming.xyz
```

### 2. Test DNS:
```bash
ping doh.mygaming.xyz
# Should respond from 91.235.234.92
```

### 3. Run setup:
```bash
cd /root/doh
sudo ./setup-letsencrypt.sh doh.mygaming.xyz
```

### 4. Keenetic URL:
```
https://doh.mygaming.xyz/dns-query
```

---

## 🔧 Troubleshooting

### DNS not resolving after 15 minutes?

**Check:**
1. A record points to correct IP (91.235.234.92)
2. Cloudflare proxy is OFF (grey cloud, not orange)
3. No typos in domain name

**Fix:**
- Update A record
- Wait another 15 minutes
- Try `nslookup doh.yourdomain.com 8.8.8.8`

### Let's Encrypt setup fails?

**Common causes:**
1. DNS not propagating yet (wait longer)
2. Port 80 blocked (need to open it temporarily)
3. Domain typo

**Check:**
```bash
# Test if port 80 is accessible
curl http://doh.yourdomain.com
```

---

## 💰 Cost Summary

**One-time:**
- Domain: $2-12/year (depending on extension)

**Monthly:**
- VPS: $6-10/month (you already have this)

**SSL Certificate:**
- Let's Encrypt: FREE (auto-renews every 90 days)

**Total new cost: ~$0.20-1/month for the domain**

---

## 🎯 Quick Checklist

Before running setup script:

- [ ] Domain purchased
- [ ] DNS A record created (doh → 91.235.234.92)
- [ ] Waited 15+ minutes
- [ ] `ping doh.yourdomain.com` works
- [ ] Shows correct IP (91.235.234.92)
- [ ] Ready to run setup script

---

## 📞 Need Help?

**If stuck:**

1. Send me:
   - Your domain name
   - Screenshot of DNS records
   - Result of `ping doh.yourdomain.com`

2. I'll help troubleshoot!

---

**Once DNS is working and pointing to your VPS, the setup script does everything automatically!** 🚀


# Cloudflare Tunnel Setup Guide

## Step-by-Step Cloudflare Dashboard Configuration

### Prerequisites
- Cloudflare account
- Domain added to Cloudflare (e.g., `bypass.440.info` or your domain)
- VPS with SNIProxy running on port 443

---

## Method 1: Using Cloudflare Dashboard (Easier)

### Step 1: Create a Tunnel

1. **Log in to Cloudflare Dashboard**
   - Go to: https://dash.cloudflare.com
   - Select your domain (e.g., `440.info`)

2. **Navigate to Zero Trust / Tunnels**
   - Click **"Zero Trust"** in the left sidebar
   - Or go directly to: https://one.dash.cloudflare.com/
   - Click **"Networks"** → **"Tunnels"**

3. **Create a New Tunnel**
   - Click **"Create a tunnel"** button
   - Select **"Cloudflared"** (not "WARP Connector")
   - Enter tunnel name: `xbox-bypass` (or any name you prefer)
   - Click **"Save tunnel"**

4. **Copy the Tunnel Token**
   - After creating, you'll see a **"Quick Start"** section
   - Copy the **command** that looks like:
     ```
     cloudflared service install <TOKEN>
     ```
   - **IMPORTANT**: Save this token - you'll need it on your VPS

---

### Step 2: Configure Tunnel on Your VPS

On your VPS, run:

```bash
# Install cloudflared (if not already installed)
cd /tmp
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/

# Install the tunnel using the token from Cloudflare dashboard
sudo cloudflared service install <PASTE_YOUR_TOKEN_HERE>
```

---

### Step 3: Configure Public Hostname (Route Traffic)

**Back in Cloudflare Dashboard:**

1. **In the Tunnel page**, find your tunnel (`xbox-bypass`)
2. Click **"Configure"** button
3. Click **"Public Hostname"** tab
4. Click **"Add a public hostname"**

5. **Fill in the details:**
   ```
   Subdomain: xbox-proxy
   Domain: 440.info (or your domain)
   Service Type: TCP
   URL: 127.0.0.1:443
   ```

   **Detailed breakdown:**
   - **Subdomain**: `xbox-proxy` (or any subdomain you want)
   - **Domain**: Select your domain from dropdown (e.g., `440.info`)
   - **Service Type**: Select **"TCP"** (important!)
   - **URL**: `127.0.0.1:443` (SNIProxy is listening on localhost:443)

6. Click **"Save hostname"**

**Result**: Traffic to `xbox-proxy.440.info` will be routed through Cloudflare Tunnel to your VPS on port 443.

---

### Step 4: Update DNS Records

**In Cloudflare Dashboard:**

1. Go to **"DNS"** → **"Records"**
2. For each Xbox domain you want to route through the tunnel:

   **Option A: Use CNAME (Recommended)**
   - Click **"Add record"**
   - Type: **CNAME**
   - Name: `xboxlive` (or `@` for root domain)
   - Target: `xbox-proxy.440.info` (your tunnel subdomain)
   - Proxy status: **Proxied** (orange cloud) ✅
   - Click **"Save"**

   **Option B: Use A Record (If CNAME doesn't work)**
   - You'll need to get the Cloudflare IP for your tunnel
   - This is more complex - use CNAME if possible

3. **Repeat for other Xbox domains:**
   - `notify.xboxlive.com` → CNAME → `xbox-proxy.440.info`
   - `xccs.xboxlive.com` → CNAME → `xbox-proxy.440.info`
   - etc.

---

## Method 2: Using Cloudflare API Token (Advanced)

If you prefer using API tokens:

### Step 1: Create API Token

1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Click **"Create Token"**
3. Use **"Edit zone DNS"** template
4. Select your zone (domain)
5. Copy the token

### Step 2: Use the Setup Script

On your VPS:

```bash
cd /root/doh
./scripts/setup/setup-cloudflare-tunnel.sh
```

When prompted:
- Enter your API token
- Enter your Account ID (found in Cloudflare dashboard → Right sidebar → Account ID)
- Enter tunnel domain (e.g., `xbox-proxy.440.info`)

---

## Important Configuration Details

### Cloudflare Dashboard Fields Explained

| Field | Value | Explanation |
|-------|-------|-------------|
| **Subdomain** | `xbox-proxy` | The subdomain for your tunnel |
| **Domain** | `440.info` | Your Cloudflare-managed domain |
| **Service Type** | `TCP` | Must be TCP for SNIProxy |
| **URL** | `127.0.0.1:443` | Local SNIProxy port |
| **Proxy Status** | `Proxied` (Orange) | Must be ON (orange cloud) |

### DNS Record Configuration

For each Xbox domain in Cloudflare DNS:

```
Type: CNAME
Name: xboxlive (or subdomain)
Target: xbox-proxy.440.info
Proxy: ON (orange cloud)
TTL: Auto
```

---

## Verification Steps

1. **Check Tunnel Status**
   - In Cloudflare Dashboard → Zero Trust → Tunnels
   - Your tunnel should show **"Healthy"** status

2. **Test DNS Resolution**
   ```bash
   nslookup xboxlive.com
   # Should return Cloudflare IPs, not your VPS IP
   ```

3. **Test Connection**
   ```bash
   curl -v --resolve xboxlive.com:443:xbox-proxy.440.info https://xboxlive.com
   ```

4. **Check SNIProxy Logs**
   ```bash
   tail -f /var/log/sniproxy/https_access.log
   # Should show connections coming through tunnel
   ```

---

## Troubleshooting

### Tunnel Not Connecting
- Check tunnel token is correct
- Verify `cloudflared` service is running: `systemctl status cloudflared`
- Check Cloudflare dashboard shows tunnel as "Healthy"

### DNS Not Resolving
- Verify DNS records are set to "Proxied" (orange cloud)
- Wait 5-10 minutes for DNS propagation
- Check DNS records point to tunnel subdomain

### Traffic Not Routing
- Verify Service Type is **TCP** (not HTTP)
- Check URL is `127.0.0.1:443` (not `localhost:443`)
- Verify SNIProxy is running: `systemctl status sniproxy`

---

## Summary

**What You Need to Enter in Cloudflare Dashboard:**

1. **Tunnel Name**: `xbox-bypass`
2. **Public Hostname**:
   - Subdomain: `xbox-proxy`
   - Domain: `440.info` (your domain)
   - Service Type: `TCP`
   - URL: `127.0.0.1:443`
3. **DNS Records**:
   - Type: `CNAME`
   - Name: `xboxlive` (or subdomain)
   - Target: `xbox-proxy.440.info`
   - Proxy: `ON` (orange cloud)

That's it! Traffic will flow:
Xbox → Cloudflare IP → Tunnel → VPS (127.0.0.1:443) → SNIProxy → Xbox Servers


# Discord Proxy Setup - How SNIProxy and 3proxy Work Together

## Overview

This setup uses **two different proxies** that work together without conflicts:

1. **SNIProxy** (port 443) - Handles HTTPS/TCP automatically
2. **3proxy** (port 1080) - Handles SOCKS5 TCP + UDP (requires Discord config)

## How They Work

### Scenario 1: Discord WITHOUT Proxy Settings (Current)

```
Discord Client
    ↓
HTTPS (TCP) → Port 443 → SNIProxy → Real Discord Servers ✅
UDP (Voice) → No proxy → Direct connection ❌ (blocked)
```

**Result:**
- ✅ Text chat works (via SNIProxy)
- ❌ Voice chat doesn't work (UDP not proxied)

### Scenario 2: Discord WITH SOCKS5 Proxy Settings

```
Discord Client
    ↓
All Traffic → Port 1080 → 3proxy → Real Discord Servers ✅
    ├─ HTTPS (TCP) ✅
    └─ UDP (Voice) ✅
```

**Result:**
- ✅ Text chat works (via 3proxy)
- ✅ Voice chat works (via 3proxy)

## No Conflicts Because:

1. **Different Ports:**
   - SNIProxy: 443
   - 3proxy: 1080

2. **Different Protocols:**
   - SNIProxy: SNI-based HTTPS proxy (transparent)
   - 3proxy: SOCKS5 proxy (explicit configuration)

3. **Different Use Cases:**
   - SNIProxy: Automatic for all HTTPS traffic
   - 3proxy: Only used when Discord is configured to use it

## Configuration

### For Text Chat Only (Current Setup)
- No Discord configuration needed
- SNIProxy handles it automatically
- Voice won't work

### For Text + Voice Chat
1. Run: `./scripts/setup/setup-discord-docker.sh`
2. Configure Discord:
   - Settings → Connections → Proxy
   - Enable proxy
   - Proxy: `YOUR_VPS_IP:1080`
   - Type: `SOCKS5`
3. Restart Discord

## Traffic Flow

### Without Discord Proxy Config:
```
Discord HTTPS → Port 443 → SNIProxy → Discord Servers
Other HTTPS   → Port 443 → SNIProxy → Real Servers
Discord UDP   → Direct   → Blocked ❌
```

### With Discord Proxy Config:
```
Discord All   → Port 1080 → 3proxy → Discord Servers ✅
Other HTTPS   → Port 443  → SNIProxy → Real Servers
```

## Important Notes

- **SNIProxy and 3proxy do NOT interfere** - they use different ports
- When Discord uses 3proxy, it bypasses SNIProxy (which is fine)
- Other services (Xbox, Activision, etc.) continue using SNIProxy
- You can use both simultaneously for different services

## Troubleshooting

If you see conflicts:

1. **Check ports:**
   ```bash
   ss -tlnp | grep -E "443|1080"
   ```
   Should show:
   - Port 443: sniproxy
   - Port 1080: 3proxy (or docker-proxy)

2. **Check services:**
   ```bash
   systemctl status sniproxy
   docker ps | grep 3proxy
   ```

3. **Test connectivity:**
   ```bash
   # Test SNIProxy
   curl -I --resolve discord.com:443:YOUR_VPS_IP https://discord.com
   
   # Test 3proxy (requires SOCKS5 client)
   curl --socks5 YOUR_VPS_IP:1080 https://discord.com
   ```

## Summary

✅ **No conflicts** - Different ports and protocols
✅ **Can use both** - SNIProxy for automatic HTTPS, 3proxy for Discord voice
✅ **Recommended** - Use 3proxy for Discord to get both text and voice


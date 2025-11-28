# Discord Voice on Xbox - Limitations and Solutions

## The Problem

Xbox doesn't have Discord proxy settings. Discord voice chat on Xbox uses **UDP** with **dynamic server IPs**, making transparent proxying difficult.

## Current Setup

### What Works ✅
- **Discord text chat**: Works via SNIProxy (automatic, no config)
- **Xbox Live**: Works via SNIProxy
- **Game services**: Works via SNIProxy

### What Doesn't Work ❌
- **Discord voice chat**: Requires UDP, which SNIProxy doesn't handle

## Why It's Difficult

1. **No client configuration**: Xbox can't be configured to use a proxy
2. **UDP protocol**: SNIProxy only handles TCP/HTTPS
3. **Dynamic IPs**: Discord voice servers have changing IPs
4. **Connection tracking**: Need to know destination IP to forward UDP

## Solutions

### Option 1: Use Discord on PC/Phone (Recommended)
- Configure Discord to use SOCKS5 proxy (`VPS_IP:1080`)
- Both text and voice work
- Easy to set up

### Option 2: VPN on Router
- Set up VPN on your router
- Routes all traffic (TCP + UDP) through VPN
- Works for everything including Discord voice
- More complex setup

### Option 3: Keep Current Setup
- Text chat works
- Voice chat doesn't work
- Simplest option

## Technical Details

### How Discord Voice Works
1. Client connects to `gateway.discord.gg` (HTTPS) to get voice server info
2. Client receives IP:port of voice server
3. Client connects directly to that IP:port (UDP)

### Why Transparent UDP Proxy is Hard
- Need to intercept UDP packets
- Need to know destination IP (which is dynamic)
- Need to forward to correct Discord voice server
- Requires connection tracking and stateful inspection

## Recommendation

**For Xbox Discord voice:**
- Use Discord on PC/Phone with SOCKS5 proxy (easiest)
- Or set up VPN on router (most comprehensive)

**For everything else:**
- Current SNIProxy setup works perfectly
- No changes needed

## Summary

| Feature | Status | Solution |
|---------|--------|----------|
| Discord text (Xbox) | ✅ Works | SNIProxy (automatic) |
| Discord voice (Xbox) | ❌ Doesn't work | Use PC/Phone or VPN |
| Discord text (PC/Phone) | ✅ Works | SNIProxy or SOCKS5 |
| Discord voice (PC/Phone) | ✅ Works | SOCKS5 proxy |
| Xbox Live | ✅ Works | SNIProxy |
| Game services | ✅ Works | SNIProxy |


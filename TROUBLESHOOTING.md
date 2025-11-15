# Troubleshooting Guide

## Common Errors and Solutions

### Error: "dns-proxy error" during deployment

**What happened:** The DNS proxy container failed to start or conflicts with existing services.

**Solution 1: Use the simple deployment**
```bash
./fix-dns-proxy.sh
./deploy-doh-443-simple.sh
```

**Solution 2: Manual cleanup**
```bash
# Stop all Docker containers
docker stop $(docker ps -aq)

# Remove all containers
docker rm $(docker ps -aq)

# Try again
./deploy-doh-443.sh
```

**Solution 3: Check port conflicts**
```bash
# See what's using port 53
sudo lsof -i :53

# Stop systemd-resolved if it's running
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Try again
./deploy-doh-443.sh
```

---

### Error: "Port 443 already in use"

**Cause:** Web server (nginx/apache) running on port 443

**Solution:**
```bash
# Stop web servers
sudo systemctl stop nginx
sudo systemctl stop apache2
sudo systemctl disable nginx
sudo systemctl disable apache2

# Or use the fix script
./fix-dns-proxy.sh

# Try again
./deploy-doh-443-simple.sh
```

---

### Error: "Cannot connect to Docker daemon"

**Cause:** Docker not running or not installed

**Solution:**
```bash
# Check if Docker is running
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# If not installed, run
./deploy.sh  # This installs Docker first
```

---

### Error: "Permission denied" when running scripts

**Cause:** Scripts not executable

**Solution:**
```bash
# Make all scripts executable
chmod +x *.sh

# Try again
sudo ./deploy-doh-443.sh
```

---

### Error: "docker-compose: command not found"

**Cause:** Docker Compose not installed

**Solution:**
```bash
# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify
docker-compose --version
```

---

### Error: Container starts then immediately stops

**Check logs:**
```bash
# For port 443 deployment
docker-compose -f docker-compose.port443.yml logs

# For simple deployment
docker-compose -f docker-compose.simple443.yml logs

# For standard deployment
docker-compose logs
```

**Common causes:**
1. **Port already in use** - See solutions above
2. **DNS upstream unreachable** - Check VPS internet connection
3. **Memory insufficient** - Need at least 512MB RAM

---

### Error: "network doh-network not found"

**Solution:**
```bash
# Remove old networks
docker network prune -f

# Recreate
docker-compose up -d
```

---

### Xbox Can't Connect to VPS DNS

**Test from VPS first:**
```bash
# Test DNS resolution locally
dig @localhost xbox.com

# Test on port 53
dig @127.0.0.1 xbox.com

# If these fail, service isn't running
docker ps  # Check running containers
```

**Test from your computer:**
```bash
# Test if VPS is reachable
ping YOUR_VPS_IP

# Test DNS port
nc -vz YOUR_VPS_IP 53

# Test DNS resolution
nslookup xbox.com YOUR_VPS_IP
```

**If VPS tests work but home tests fail:**
- Your ISP is blocking port 53 to VPS
- Solution: Use VPN (GL.iNet router or OpenVPN)
- See: `ALTERNATIVES.md`

---

### High Latency / Slow DNS

**Check DNS resolution time:**
```bash
# On VPS
time dig @localhost xbox.com

# Should be < 100ms
```

**Solutions:**
1. **Change DNS upstream:**
```bash
./update-upstream.sh
# Choose provider closer to VPS location
```

2. **Increase cache:**
Edit `coredns/Corefile`:
```
cache {
    success 9984 7200  # Increase to 2 hours
    denial 9984 300    # Increase to 5 minutes
}
```
Then: `docker-compose restart`

---

### Services Start but DNS Doesn't Resolve

**Check container networking:**
```bash
# List containers
docker ps

# Check if they can communicate
docker exec doh-server ping -c 2 dns-proxy

# Check DNS internally
docker exec dns-proxy nslookup xbox.com doh-server
```

**Check firewall:**
```bash
# UFW
sudo ufw status
sudo ufw allow 53/udp
sudo ufw allow 53/tcp
sudo ufw allow 443/tcp

# Iptables
sudo iptables -L -n | grep -E '53|443'
```

---

### VPN Won't Connect

**For WireGuard:**
```bash
# Check if running
sudo systemctl status wg-quick@wg0

# Check logs
sudo journalctl -u wg-quick@wg0 -n 50

# Restart
sudo systemctl restart wg-quick@wg0
```

**For OpenVPN:**
```bash
# Check status
sudo systemctl status openvpn@server

# Check logs
sudo tail -f /var/log/openvpn.log

# Restart
sudo systemctl restart openvpn@server
```

**Check VPN port is open:**
```bash
# WireGuard (51820 UDP)
sudo nc -vzu YOUR_VPS_IP 51820

# OpenVPN (1194 UDP or 443 TCP)
sudo nc -vz YOUR_VPS_IP 443
```

---

### "Can't pull Docker image"

**Cause:** No internet on VPS or Docker Hub unreachable

**Solution:**
```bash
# Test internet
ping 8.8.8.8
ping google.com

# If DNS fails but ping works
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Try pulling manually
docker pull cloudflare/cloudflared:latest
docker pull coredns/coredns:latest
```

---

### Out of Disk Space

**Check disk usage:**
```bash
df -h
```

**Clean up Docker:**
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Remove everything unused
docker system prune -a --volumes
```

---

### Deployment Script Hangs

**If script stops responding:**

1. **Press Ctrl+C** to stop
2. **Check what's running:**
```bash
docker ps
docker-compose ps
```
3. **Clean up:**
```bash
./fix-dns-proxy.sh
```
4. **Try simple deployment:**
```bash
./deploy-doh-443-simple.sh
```

---

## Quick Diagnostic Commands

### Check Everything Status
```bash
# Are containers running?
docker ps

# Are services accessible?
dig @localhost xbox.com
curl -I https://localhost:443/dns-query

# Are ports open?
sudo netstat -tulpn | grep -E '53|443|51820|1194'

# System resources
free -h
df -h
htop
```

### View All Logs
```bash
# All Docker logs
docker-compose logs -f

# Specific service
docker logs dns-proxy -f
docker logs doh-server -f

# System logs
sudo journalctl -xe
```

### Restart Everything
```bash
# Restart all containers
docker-compose restart

# Or stop and start fresh
docker-compose down
docker-compose up -d

# Reboot VPS (last resort)
sudo reboot
```

---

## Still Having Issues?

### Collect Information

Run these and save output:
```bash
# System info
uname -a
cat /etc/os-release

# Docker info
docker --version
docker-compose --version
docker ps -a
docker network ls

# Services
docker-compose ps
docker-compose logs --tail=100

# Network
ip addr
sudo netstat -tulpn
sudo iptables -L -n

# Disk
df -h
free -h
```

### Try Minimal Setup

```bash
# Clean everything
./fix-dns-proxy.sh

# Use absolute minimum
./deploy-doh-443-simple.sh

# If this works, add features one by one
```

### Consider Alternatives

If DNS-based solutions keep failing:
1. **Use VPN instead** - See `ALTERNATIVES.md`
2. **Try GL.iNet router** - See `GLINET_SETUP.md`
3. **Use OpenVPN on port 443** - Run `./setup-openvpn.sh`

---

## Error Messages Reference

| Error Message | Meaning | Solution |
|---------------|---------|----------|
| "Address already in use" | Port conflict | Stop service using that port |
| "network not found" | Docker network issue | `docker network prune -f` |
| "permission denied" | Need root access | Use `sudo` |
| "command not found" | Software not installed | Run `./deploy.sh` first |
| "timeout" | Network/firewall issue | Check firewall, test connectivity |
| "no space left" | Disk full | Clean up: `docker system prune -a` |
| "cannot connect" | Service not running | Check `docker ps` |

---

## Prevention

### Regular Maintenance
```bash
# Weekly
docker-compose logs --tail=100  # Check for errors

# Monthly
apt update && apt upgrade       # Update system
docker-compose pull             # Update images
docker system prune             # Clean unused resources
```

### Monitoring
```bash
# Add to crontab for daily checks
0 0 * * * docker ps | grep -q dns-proxy || systemctl restart docker
```

---

## Need More Help?

1. **Check specific guide:**
   - DNS issues → `DNS_PROVIDERS.md`
   - VPN issues → `VPN_SETUP_GUIDE.md`
   - Xbox issues → `XBOX_SETUP_GUIDE.md`
   - ISP blocking → `ISP_DNS_BLOCKING.md`

2. **Try alternatives:**
   - See `ALTERNATIVES.md` for other approaches

3. **Start over cleanly:**
```bash
# Nuclear option - remove everything and start fresh
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)
docker system prune -a --volumes
./deploy.sh
```

---

**Most issues can be fixed with `./fix-dns-proxy.sh` followed by `./deploy-doh-443-simple.sh`**


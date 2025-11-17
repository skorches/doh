# Manual Cleanup Steps

## Run These Commands on Your VPS

Copy and paste these commands one by one:

### 1. Stop Everything

```bash
# Stop all Docker containers
sudo docker stop $(sudo docker ps -aq)

# Remove all containers
sudo docker rm $(sudo docker ps -aq)
```

### 2. Remove Docker Compose Services

```bash
# Navigate to your directory
cd /root/doh  # or cd ~/doh

# Stop all compose services
sudo docker-compose -f docker-compose.yml down
sudo docker-compose -f docker-compose.port443.yml down
sudo docker-compose -f docker-compose.simple443.yml down
sudo docker-compose -f docker-compose.openvpn-doh.yml down
```

### 3. Clean Docker

```bash
# Remove networks
sudo docker network prune -f

# Remove all unused images
sudo docker image prune -a -f

# Remove volumes
sudo docker volume prune -f
```

### 4. Restore OpenVPN (if modified)

```bash
# Check if backup exists
ls -la /etc/openvpn/server.conf.backup*

# If exists, restore it
sudo cp /etc/openvpn/server.conf.backup.20251115 /etc/openvpn/server.conf
sudo systemctl restart openvpn@server
```

### 5. Remove Config Files

```bash
cd /root/doh  # or your directory

# Remove old configs
rm -f docker-compose.port443.yml
rm -f docker-compose.simple443.yml
rm -f docker-compose.openvpn-doh.yml
rm -rf coredns-443
```

### 6. Verify Everything is Clean

```bash
# Should show nothing
sudo docker ps -a

# Should show minimal or no images
sudo docker images

# OpenVPN should still be running (if you want it)
sudo systemctl status openvpn@server
```

---

## Alternative: Use Cleanup Script

Or just run the automated cleanup:

```bash
cd /root/doh  # or wherever your files are

# Make executable
chmod +x COMPLETE_CLEANUP.sh

# Run it
sudo ./COMPLETE_CLEANUP.sh
```

Type `yes` when prompted.

---

## After Cleanup

Your system will be clean with:
- ✓ No Docker containers
- ✓ No leftover configurations
- ✓ OpenVPN restored (if you had it)
- ✓ Ready for fresh simple setup

Then run:
```bash
sudo ./deploy-keenetic-doh.sh
```

---

## What NOT to Remove

**Keep these running:**
- OpenVPN (if you use it for other things)
- SSH
- System services
- Your VPS provider stuff

**Only removing:**
- Our DoH attempts
- WireGuard setups
- Complex integrations
- Test configurations


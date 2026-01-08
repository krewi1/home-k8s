# DNS Configuration for .home Domain

This directory contains DNS configuration for the Raspberry Pi 4 that provides internal DNS resolution for the Kubernetes cluster.

## Overview

The DNS server on the Raspberry Pi 4:
- Resolves all `*.home` domains to the nginx server (same Pi 4)
- Provides DNS resolution for all cluster services
- Integrates with the existing network DNS for external queries
- Uses dnsmasq for lightweight, efficient DNS serving

## Architecture

```
Client Request (grafana.home)
    ↓
DNS Server (Pi 4 / dnsmasq)
    ↓
Returns: nginx Pi 4 IP
    ↓
nginx (Pi 4)
    ↓
Kourier NodePort (K8s Cluster)
    ↓
Service (e.g., Grafana)
```

## Service Examples

All these domains point to nginx, which routes based on Host header:

- `grafana.home` → Grafana dashboard
- `prometheus.home` → Prometheus UI
- `loki.home` → Loki API
- `minio.home` → MinIO console
- `hello.home` → Example Knative service
- `*.home` → Any service you deploy

## Configuration Files

### `dnsmasq.conf`
Main dnsmasq configuration file with:
- DNS server settings
- Upstream DNS servers
- Cache configuration
- Logging options

### `home-domain.conf`
Domain-specific configuration for `.home` TLD:
- Wildcard DNS for `*.home`
- Specific service entries
- CNAME aliases

### `hosts.home`
Static host entries for cluster infrastructure:
- Kubernetes nodes
- Infrastructure services
- Management interfaces

## Installation Instructions

### 1. Install dnsmasq

On the Raspberry Pi 4:

```bash
sudo apt update
sudo apt install dnsmasq
```

### 2. Backup Existing Configuration

```bash
sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
sudo cp /etc/resolv.conf /etc/resolv.conf.backup
```

### 3. Deploy Configuration

```bash
# Copy configuration files to Pi 4
scp dnsmasq.conf pi@<pi4-ip>:~/
scp home-domain.conf pi@<pi4-ip>:~/
scp hosts.home pi@<pi4-ip>:~/

# SSH to Pi 4
ssh pi@<pi4-ip>

# Install configurations
sudo cp dnsmasq.conf /etc/dnsmasq.conf
sudo cp home-domain.conf /etc/dnsmasq.d/
sudo cp hosts.home /etc/hosts.home

# Create dnsmasq.d directory if it doesn't exist
sudo mkdir -p /etc/dnsmasq.d

# Restart dnsmasq
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

### 4. Update Network Configuration

#### Option A: Set Pi 4 as Primary DNS for DHCP Server

Configure your router to advertise the Pi 4 as the primary DNS server:
- Router Admin → DHCP Settings
- Primary DNS: `<pi4-ip>`
- Secondary DNS: `8.8.8.8` (fallback)

#### Option B: Set DNS Manually on Client Devices

On Linux/Mac:
```bash
# Edit /etc/resolv.conf or use NetworkManager
nameserver <pi4-ip>
nameserver 8.8.8.8
```

On Windows:
```powershell
# Network Settings → Change Adapter Settings → Properties
# Set Preferred DNS: <pi4-ip>
# Set Alternate DNS: 8.8.8.8
```

### 5. Configure Pi 4 to Use Itself for DNS

On the Pi 4:

```bash
# Edit /etc/dhcpcd.conf
sudo nano /etc/dhcpcd.conf

# Add or modify:
static domain_name_servers=127.0.0.1 8.8.8.8

# Restart networking
sudo systemctl restart dhcpcd
```

## Configuration Customization

### Update IP Addresses

Edit `home-domain.conf` and replace `<nginx-ip>` with your actual Pi 4 IP:

```bash
# Before deployment
sed -i 's/<nginx-ip>/192.168.1.100/g' home-domain.conf
```

### Add New Services

To add a new service DNS entry:

```bash
# Edit home-domain.conf
sudo nano /etc/dnsmasq.d/home-domain.conf

# Add entry:
# address=/myservice.home/<nginx-ip>

# Restart dnsmasq
sudo systemctl restart dnsmasq
```

### Update Kubernetes Node IPs

Edit `hosts.home` with your actual node IP addresses:

```bash
# Edit before deployment
nano hosts.home

# Replace placeholders:
# <master-ip> → 192.168.1.10
# <worker1-ip> → 192.168.1.11
# etc.
```

## Testing

### Test DNS Resolution

From any client on the network:

```bash
# Test wildcard resolution
nslookup grafana.home <pi4-ip>
nslookup test.home <pi4-ip>

# Should return nginx IP address

# Test with dig (more detailed)
dig @<pi4-ip> grafana.home

# Test external DNS still works
nslookup google.com <pi4-ip>
```

### Test Service Access

```bash
# Test that nginx receives requests
curl -v http://grafana.home

# Test with specific service
curl -H "Host: grafana.home" http://<pi4-ip>

# Should route through nginx → Kourier → Grafana
```

### Test DNS from K8s Pods

```bash
# Create test pod
kubectl run test-dns --image=busybox --rm -it --restart=Never -- sh

# Inside pod:
nslookup grafana.home
# Should resolve to nginx IP

# Test external DNS
nslookup google.com
```

## Monitoring

### Check dnsmasq Status

```bash
# Service status
sudo systemctl status dnsmasq

# View logs
sudo journalctl -u dnsmasq -f

# View query log (if enabled)
sudo tail -f /var/log/dnsmasq.log
```

### Check DNS Statistics

```bash
# Send SIGUSR1 to dump stats to syslog
sudo killall -USR1 dnsmasq

# View stats
sudo journalctl -u dnsmasq | tail -20
```

### Test DNS Performance

```bash
# Query time
time nslookup grafana.home <pi4-ip>

# Check cache hits
sudo journalctl -u dnsmasq | grep "cached"
```

## Troubleshooting

### DNS Not Resolving

```bash
# Check if dnsmasq is running
sudo systemctl status dnsmasq

# Check if port 53 is listening
sudo netstat -tulpn | grep :53

# Check configuration syntax
sudo dnsmasq --test

# View detailed logs
sudo dnsmasq --no-daemon --log-queries
```

### Conflict with systemd-resolved

On some systems, systemd-resolved may conflict with dnsmasq:

```bash
# Disable systemd-resolved
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved

# Remove symlink
sudo rm /etc/resolv.conf

# Create new resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# Restart dnsmasq
sudo systemctl restart dnsmasq
```

### Queries Not Being Forwarded

```bash
# Check upstream DNS servers
cat /etc/resolv.conf

# Test upstream resolution
dig @8.8.8.8 google.com

# Check dnsmasq forwards
sudo journalctl -u dnsmasq | grep "forwarded"
```

### Cache Issues

```bash
# Clear DNS cache
sudo systemctl restart dnsmasq

# Or send HUP signal
sudo killall -HUP dnsmasq

# On client (Linux/Mac)
sudo systemd-resolve --flush-caches  # systemd
sudo dscacheutil -flushcache          # macOS
```

## Security Considerations

### Restrict DNS Queries

Limit DNS queries to local network:

```conf
# Add to dnsmasq.conf
interface=eth0
bind-interfaces
listen-address=127.0.0.1,<pi4-ip>
```

### Enable DNSSEC

```conf
# Add to dnsmasq.conf
dnssec
trust-anchor=.,20326,8,2,E06D44B80B8F1D39A95C0B0D7C65D08458E880409BBC683457104237C7F8EC8D
```

### Rate Limiting

Prevent DNS amplification attacks:

```conf
# Add to dnsmasq.conf
dns-forward-max=150
cache-size=10000
```

## Advanced Configuration

### Split DNS Horizon

Route different domains to different upstream servers:

```conf
# In dnsmasq.conf
server=/internal.company.com/10.0.0.1
server=/home/127.0.0.1
server=8.8.8.8
```

### DNS Blacklist

Block unwanted domains:

```conf
# Create blocklist
address=/ads.example.com/0.0.0.0
address=/tracker.example.com/0.0.0.0
```

### Conditional Forwarding

Forward specific subnets to specific DNS:

```conf
# For reverse DNS
rev-server=192.168.1.0/24,<gateway-ip>
```

## Integration with Kubernetes Services

### Automatic Service Discovery

When you deploy a new Knative service:

1. Service gets URL: `hello.default.home`
2. DNS already resolves `*.home` to nginx
3. nginx forwards to Kourier
4. Kourier routes based on Host header
5. No DNS changes needed!

### Example Service URLs

```yaml
# Knative service
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
spec:
  template:
    spec:
      containers:
      - image: gcr.io/knative-samples/helloworld-go
```

Accessible at: `http://hello.default.home`

### Custom Domain Mapping

For custom domains:

```yaml
# Knative DomainMapping
apiVersion: serving.knative.dev/v1beta1
kind: DomainMapping
metadata:
  name: hello.home
  namespace: default
spec:
  ref:
    name: hello
    kind: Service
    apiVersion: serving.knative.dev/v1
```

Then access at: `http://hello.home`

## Backup and Recovery

### Backup DNS Configuration

```bash
# Create backup
sudo tar czf dnsmasq-backup-$(date +%Y%m%d).tar.gz \
  /etc/dnsmasq.conf \
  /etc/dnsmasq.d/ \
  /etc/hosts.home

# Copy backup off-device
scp dnsmasq-backup-*.tar.gz user@backup-server:~/
```

### Restore Configuration

```bash
# Extract backup
sudo tar xzf dnsmasq-backup-*.tar.gz -C /

# Restart service
sudo systemctl restart dnsmasq
```

## Performance Tuning

### Increase Cache Size

```conf
# In dnsmasq.conf
cache-size=10000  # Default is 150
```

### Reduce Query Time

```conf
# Disable negative caching for faster failover
no-negcache

# Increase DNS timeout
dns-forward-max=150
```

## References

- [dnsmasq Documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html)
- [DNS Best Practices](https://www.rfc-editor.org/rfc/rfc1912)
- [Knative Custom Domains](https://knative.dev/docs/serving/using-a-custom-domain/)

# K8s Initialization Scripts

This directory contains scripts for installing and initializing the K3s Kubernetes cluster on Raspberry Pi nodes.

## Overview

K3s is a lightweight Kubernetes distribution perfect for edge computing and ARM devices like Raspberry Pi. These scripts automate the installation and cluster setup process.

## Scripts

### `setup-ssd.sh`
Partitions and mounts the 1TB SSD on the master node for optimal storage allocation.

**Usage:**
```bash
sudo ./setup-ssd.sh
```

**What it does:**
- Detects available storage devices
- Creates two partitions on the SSD:
  - **Partition 1**: 200GB for K3s etcd database
  - **Partition 2**: ~800GB for MinIO object storage
- Formats partitions with ext4 filesystem
- Creates mount points:
  - `/var/lib/rancher/k3s/server/db` for etcd
  - `/mnt/minio-data` for MinIO
- Updates `/etc/fstab` for persistent mounts
- Sets appropriate permissions

**Safety Features:**
- Displays device information before partitioning
- Requires explicit "YES" confirmation
- Creates backup of `/etc/fstab`
- Checks and unmounts existing partitions
- Validates device existence

**Important Notes:**
- ⚠️ This will DESTROY all data on the target device
- Must be run as root (sudo)
- Should be run BEFORE installing K3s
- Only needs to be run on the master node

### `install-master.sh`
Installs K3s on the master node (Raspberry Pi 5) and initializes the cluster.

**Usage:**
```bash
sudo ./install-master.sh
```

**What it does:**
- Checks prerequisites:
  - Verifies etcd partition is mounted (from setup-ssd.sh)
  - Confirms internet connectivity
  - Checks for existing K3s installation
- Prepares the system:
  - Disables swap (required for K8s)
  - Enables cgroups in boot configuration
- Installs K3s with optimized settings:
  - Uses SSD partition for etcd storage automatically
  - Disables Traefik (we use Kourier for Knative)
  - Disables ServiceLB (we use NodePort + external nginx)
  - Configures proper TLS certificates
- Sets up kubeconfig for kubectl access
- Verifies etcd is using SSD storage
- Displays:
  - Master node IP and token
  - Worker join command
  - Kubeconfig copy instructions
  - Installation verification commands

**Configuration:**
- etcd storage: `/var/lib/rancher/k3s/server/db` (SSD)
- Data directory: `/var/lib/rancher/k3s`
- Kubeconfig: `/etc/rancher/k3s/k3s.yaml`

**Important Notes:**
- Must be run as root (sudo)
- Requires setup-ssd.sh to be run first
- May require reboot if cgroups were not enabled
- Saves the node token needed for workers

### `install-worker.sh`
Installs K3s on worker nodes and joins them to the cluster.

**Usage:**
```bash
./install-worker.sh <MASTER_IP> <NODE_TOKEN>
```

**Parameters:**
- `MASTER_IP`: IP address of the master node
- `NODE_TOKEN`: Token from master node (found in `/var/lib/rancher/k3s/server/node-token`)

**What it does:**
- Installs K3s in agent mode
- Joins the node to the cluster
- Registers with the master node

### `init-cluster.sh`
Complete cluster initialization script that orchestrates the entire setup process.

**Usage:**
```bash
./init-cluster.sh
```

**What it does:**
- Validates prerequisites
- Installs K3s on master node
- Retrieves node token
- Installs K3s on all worker nodes
- Verifies cluster health

## Prerequisites

- All Raspberry Pi devices must be:
  - Running Raspberry Pi OS (64-bit)
  - Connected to the same network
  - Accessible via SSH (for remote installation)
  - Have static IP addresses configured

## Installation Steps

### Step 0: Setup SSD on Master Node (Required First!)

Before installing K3s, partition and mount the 1TB SSD on the master node:

```bash
# Copy script to master node
scp setup-ssd.sh pi@<master-ip>:~/

# SSH to master node
ssh pi@<master-ip>

# Run SSD setup script
sudo ./setup-ssd.sh

# Verify mounts
df -h | grep -E 'etcd|minio'
```

The script will guide you through:
- Selecting the correct disk device (e.g., `/dev/sda` or `/dev/nvme0n1`)
- Confirming the operation (type "YES" to proceed)
- Automatic partitioning, formatting, and mounting

### Option 1: Automated Installation

Run the complete initialization script from your local machine:

```bash
cd k8s-init

# First setup SSD on master node (see Step 0 above)
# Then run cluster initialization
./init-cluster.sh
```

### Option 2: Manual Installation

1. **On Master Node (Raspberry Pi 5):**
   ```bash
   # FIRST: Setup SSD (see Step 0 above)
   # Then proceed with K3s installation

   # Copy script to master node
   scp install-master.sh pi@<master-ip>:~/

   # SSH to master node
   ssh pi@<master-ip>

   # Run installation (will use SSD for etcd automatically)
   sudo ./install-master.sh

   # The script will display the node token and join command
   # Or retrieve it manually:
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```

2. **On Each Worker Node (2x Pi 5, 1x Pi 4):**
   ```bash
   # Copy script to worker node
   scp install-worker.sh pi@<worker-ip>:~/

   # SSH to worker node
   ssh pi@<worker-ip>

   # Run installation
   ./install-worker.sh <master-ip> <node-token>
   ```

3. **Verify Cluster:**
   ```bash
   # On master node or local machine with kubeconfig
   kubectl get nodes
   kubectl get pods -A
   ```

## Configuration

### Master Node Configuration

Default K3s master installation options:
- Disable Traefik (we use nginx): `--disable traefik`
- Disable ServiceLB: `--disable servicelb`
- Enable specific features as needed

### Worker Node Configuration

- Automatically detects and uses available resources
- Configures container runtime
- Registers with master node

## Storage Architecture

### Master Node SSD Configuration

The 1TB SSD on the master node is partitioned for optimal performance:

```
┌─────────────────────────────────────────┐
│         1TB SSD on Master Node          │
├─────────────────────────────────────────┤
│  Partition 1: 200GB                     │
│  Mount: /var/lib/rancher/k3s/server/db  │
│  Purpose: K3s etcd database             │
│  - Fast I/O for cluster state           │
│  - Critical data redundancy via backups │
├─────────────────────────────────────────┤
│  Partition 2: ~800GB                    │
│  Mount: /mnt/minio-data                 │
│  Purpose: MinIO object storage          │
│  - Application data storage             │
│  - Loki log retention                   │
│  - General purpose S3 storage           │
└─────────────────────────────────────────┘
```

### Why This Configuration?

**etcd (200GB):**
- Stores all Kubernetes cluster state
- Benefits from SSD's low latency
- 200GB provides plenty of room for growth
- Separate partition protects from storage exhaustion

**MinIO (800GB):**
- Distributed object storage for applications
- Stores logs from Loki
- General purpose S3-compatible storage
- Can be expanded to additional worker nodes

### How K3s Uses the SSD

When you run `setup-ssd.sh`, it mounts the first partition to `/var/lib/rancher/k3s/server/db`, which is the default location where K3s stores its etcd database.

The `install-master.sh` script:
1. Verifies this mount point exists and has sufficient space
2. Installs K3s with `--data-dir=/var/lib/rancher/k3s`
3. K3s automatically places etcd data in `/var/lib/rancher/k3s/server/db`
4. Since this directory is on the SSD mount, etcd automatically uses fast storage

No additional configuration is needed - it works automatically!

## Ingress Architecture

This cluster uses a multi-layer ingress approach optimized for Knative:

```
Internet
    ↓
┌─────────────────────────────────┐
│  External nginx (Pi 4)          │
│  - SSL/TLS termination          │
│  - DNS resolution               │
│  - Routes to NodePort           │
└─────────────────────────────────┘
    ↓ (routes to NodePort)
┌─────────────────────────────────┐
│  Kourier Ingress (in cluster)   │
│  - NodePort Service             │
│  - Knative gateway              │
│  - Lightweight & fast           │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│  Knative Services               │
│  - Auto-scaling                 │
│  - Serverless workloads         │
└─────────────────────────────────┘
```

### Why This Architecture?

**External nginx (Pi 4):**
- Single entry point for all traffic
- Handles DNS and SSL/TLS termination
- Can route to different services based on domain/path
- Separates infrastructure from cluster

**Kourier (in cluster):**
- Lightweight ingress controller designed for Knative
- Exposed via NodePort for external access
- Handles Knative-specific routing and features
- Much lighter than Traefik or nginx-ingress

**NodePort:**
- No cloud load balancer needed
- External nginx routes directly to NodePort
- Works perfectly in homelab environment

### Configuration Steps

After deploying Knative with Kourier (see k8s-infrastructure):

1. **Find Kourier NodePort:**
   ```bash
   kubectl get svc -n knative-serving kourier
   # Note the NodePort (e.g., 30080 for HTTP, 30443 for HTTPS)
   ```

2. **Configure nginx on Pi 4:**
   ```nginx
   # /etc/nginx/sites-available/k8s-ingress
   upstream k8s_cluster {
       server <master-ip>:<nodeport>;
       server <worker1-ip>:<nodeport>;
       server <worker2-ip>:<nodeport>;
   }

   server {
       listen 80;
       server_name *.example.com;

       location / {
           proxy_pass http://k8s_cluster;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

3. **DNS Configuration:**
   - Point your domain/subdomains to nginx Pi 4 IP
   - Kourier will handle routing based on Host header

## Post-Installation

After successful installation:

1. **Copy kubeconfig from master:**
   ```bash
   scp pi@<master-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
   # Update server IP in the config file
   sed -i 's/127.0.0.1/<master-ip>/g' ~/.kube/config
   ```

2. **Verify cluster status:**
   ```bash
   kubectl get nodes -o wide
   kubectl cluster-info
   ```

3. **Verify SSD mounts:**
   ```bash
   ssh pi@<master-ip>
   df -h | grep -E 'etcd|minio'
   lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
   ```

4. **Label nodes (optional):**
   ```bash
   kubectl label nodes <node-name> node-role.kubernetes.io/worker=worker
   ```

## Troubleshooting

### Common Issues

**SSD not detected or wrong device:**
```bash
# List all block devices
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL

# Check device information
sudo fdisk -l

# Identify SSD by interface (should show "sata" or "nvme")
lsblk -o NAME,SIZE,TYPE,TRAN
```

**Partition mounting fails:**
```bash
# Check if partitions exist
lsblk

# Verify filesystem
sudo blkid | grep -E 'sda|nvme'

# Check fstab syntax
sudo mount -a

# View mount errors
sudo dmesg | tail -20
```

**etcd mount point already exists with data:**
```bash
# Check what's in the directory
ls -la /var/lib/rancher/k3s/server/db/

# If K3s is already installed, backup and move data:
sudo systemctl stop k3s
sudo mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db.backup
sudo mkdir -p /var/lib/rancher/k3s/server/db
# Then re-run setup-ssd.sh
```

**SSD performance is slow:**
```bash
# Test write speed
sudo dd if=/dev/zero of=/mnt/minio-data/test.img bs=1M count=1000 oflag=direct

# Test read speed
sudo dd if=/mnt/minio-data/test.img of=/dev/null bs=1M iflag=direct

# Check if TRIM is enabled (for SSD longevity)
sudo fstrim -v /var/lib/rancher/k3s/server/db
sudo fstrim -v /mnt/minio-data
```

**K3s fails to start on master:**
- Check system requirements: `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="check-config" sh -`
- Verify etcd mount is accessible: `df -h | grep etcd`
- Verify port 6443 is available
- Check logs: `sudo journalctl -u k3s -f`

**Worker cannot join cluster:**
- Verify network connectivity: `ping <master-ip>`
- Check firewall rules
- Verify node token is correct
- Ensure master node is fully running

**Nodes show as NotReady:**
- Check CNI plugin: `kubectl get pods -n kube-system`
- Verify network connectivity between nodes
- Check node resources: `kubectl describe node <node-name>`

## Uninstallation

### On Master Node:
```bash
/usr/local/bin/k3s-uninstall.sh
```

### On Worker Nodes:
```bash
/usr/local/bin/k3s-agent-uninstall.sh
```

## Network Requirements

### Required Ports

**Master Node:**
- 6443/tcp - Kubernetes API
- 8472/udp - Flannel VXLAN
- 10250/tcp - Kubelet metrics
- 2379-2380/tcp - etcd

**Worker Nodes:**
- 8472/udp - Flannel VXLAN
- 10250/tcp - Kubelet metrics

## References

- [K3s Official Documentation](https://docs.k3s.io/)
- [K3s GitHub Repository](https://github.com/k3s-io/k3s)
- [Raspberry Pi Kubernetes Setup Guide](https://docs.k3s.io/installation/requirements)

# MinIO Expansion Guide: Standalone to Distributed Mode

This guide covers migrating from standalone MinIO (single node) to distributed mode (4+ nodes) for improved performance, redundancy, and automatic data healing.

## Why Expand to Distributed Mode?

**Benefits:**
- ✅ **High Availability**: Survives node failures
- ✅ **Better Performance**: Parallel operations across nodes
- ✅ **Automatic Healing**: Detects and repairs corrupted data
- ✅ **Erasure Coding**: Built-in data protection (like RAID)
- ✅ **Scalability**: Add more nodes for more capacity

**Requirements:**
- Minimum 4 nodes (or 4 drives)
- Each node needs an SSD with MinIO data partition
- All drives should be similar size for best results

## Pre-Migration Checklist

### 1. Current State Verification

```bash
# Check current MinIO deployment
kubectl get all -n minio

# Check data size
kubectl exec -n minio deployment/minio -- du -sh /data

# Backup configuration
kubectl get all,pvc,pv,ingress,secret -n minio -o yaml > minio-standalone-backup.yaml

# Export all buckets list
kubectl exec -n minio deployment/minio -- ls /data
```

### 2. Hardware Preparation

For each new node you're adding:

```bash
# On each NEW worker node (e.g., worker-01, worker-02, worker-03):

# 1. Run setup-ssd.sh (modified for worker nodes)
sudo ./setup-ssd-worker.sh /dev/sda  # or your SSD device

# 2. Verify mount
df -h | grep minio-data

# 3. Check permissions
ls -la /mnt/minio-data
# Should be: drwxr-xr-x 1000 1000

# 4. Label the node
kubectl label node worker-01 minio-server=true
kubectl label node worker-02 minio-server=true
kubectl label node worker-03 minio-server=true
kubectl label node master-01 minio-server=true
```

### 3. Create Worker SSD Setup Script

Since you'll need to set up SSDs on worker nodes, create this script:

```bash
# cluster-infra/minio/docs/setup-ssd-worker.sh
#!/bin/bash
# Simplified SSD setup for MinIO worker nodes
# Only creates /mnt/minio-data partition (no etcd or PVC partitions)

set -e

DEVICE=$1
MINIO_MOUNT="/mnt/minio-data"

if [[ -z "$DEVICE" ]]; then
    echo "Usage: $0 <device>"
    echo "Example: $0 /dev/sda"
    exit 1
fi

echo "Setting up MinIO storage on $DEVICE"
echo "This will DESTROY all data on $DEVICE!"
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    exit 0
fi

# Wipe and create single partition
wipefs -a "$DEVICE"
parted -s "$DEVICE" mklabel gpt
parted -s "$DEVICE" mkpart primary ext4 0% 100%
partprobe "$DEVICE"
sleep 2

# Format
PART="${DEVICE}1"
if [[ $DEVICE == /dev/nvme* ]]; then
    PART="${DEVICE}p1"
fi

mkfs.ext4 -F -L "minio-data" "$PART"

# Create mount point and mount
mkdir -p "$MINIO_MOUNT"
mount "$PART" "$MINIO_MOUNT"

# Set permissions
chown -R 1000:1000 "$MINIO_MOUNT"
chmod 755 "$MINIO_MOUNT"

# Update fstab
UUID=$(blkid -s UUID -o value "$PART")
cp /etc/fstab /etc/fstab.backup
echo "UUID=$UUID  $MINIO_MOUNT  ext4  defaults,noatime  0  2" >> /etc/fstab

echo "Done! MinIO storage ready at $MINIO_MOUNT"
df -h "$MINIO_MOUNT"
```

## Migration Strategy

You have two options:

### Option A: With Downtime (Recommended)

Cleanest approach with data migration.

**Steps:**
1. Backup all data from standalone MinIO
2. Uninstall standalone deployment
3. Deploy distributed mode
4. Restore data

**Downtime:** ~30 minutes to a few hours (depends on data size)

### Option B: Blue-Green Deployment

Run both systems temporarily, migrate data, then switch.

**Steps:**
1. Deploy distributed MinIO alongside standalone
2. Migrate data between them
3. Switch applications to distributed
4. Remove standalone

**Downtime:** Near-zero, but more complex

---

## Migration Process: Option A (With Downtime)

### Step 1: Backup Data

```bash
# Install MinIO Client
wget https://dl.min.io/client/mc/release/linux-arm64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Configure mc for current standalone MinIO
mc alias set standalone http://minio-api.home admin changeme123

# Backup all buckets to local storage
mc mirror --preserve standalone/ /backup/minio-data/

# Verify backup
ls -lah /backup/minio-data/

# Also backup MinIO metadata
kubectl get all,pvc,pv,secret -n minio -o yaml > /backup/minio-k8s-config.yaml
```

### Step 2: Prepare New Nodes

```bash
# On each worker node (worker-01, worker-02, worker-03):
# Copy and run the setup-ssd-worker.sh script

# From your workstation
scp setup-ssd-worker.sh worker-01:/tmp/
ssh worker-01 'sudo bash /tmp/setup-ssd-worker.sh /dev/sda'

scp setup-ssd-worker.sh worker-02:/tmp/
ssh worker-02 'sudo bash /tmp/setup-ssd-worker.sh /dev/sda'

scp setup-ssd-worker.sh worker-03:/tmp/
ssh worker-03 'sudo bash /tmp/setup-ssd-worker.sh /dev/sda'

# Verify all mounts
for node in master-01 worker-01 worker-02 worker-03; do
    echo "=== $node ==="
    ssh $node 'df -h | grep minio-data'
done
```

### Step 3: Create PersistentVolumes for Each Node

```bash
# Create PVs for distributed mode
cat > /tmp/minio-distributed-pvs.yaml <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-0
  labels:
    app: minio
    minio-server: "0"
spec:
  storageClassName: local-storage
  capacity:
    storage: 800Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - master-01

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-1
  labels:
    app: minio
    minio-server: "1"
spec:
  storageClassName: local-storage
  capacity:
    storage: 800Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-01

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-2
  labels:
    app: minio
    minio-server: "2"
spec:
  storageClassName: local-storage
  capacity:
    storage: 800Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-02

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-3
  labels:
    app: minio
    minio-server: "3"
spec:
  storageClassName: local-storage
  capacity:
    storage: 800Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-03
EOF

# Apply PVs
kubectl apply -f /tmp/minio-distributed-pvs.yaml
```

### Step 4: Uninstall Standalone MinIO

```bash
# Stop standalone MinIO
cd /path/to/cluster-infra/minio
./uninstall.sh

# Verify everything is removed
kubectl get all -n minio
# Should show nothing

# Keep the namespace and secret
kubectl apply -f standalone/namespace.yaml
kubectl apply -f standalone/secret.yaml
```

### Step 5: Deploy Distributed MinIO

```bash
# Apply distributed configuration
kubectl apply -f distributed/statefulset.yaml

# Apply services (use the same service definitions)
kubectl apply -f standalone/service.yaml

# Apply ingress
kubectl apply -f standalone/ingress.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=minio -n minio --timeout=600s

# Check status
kubectl get pods -n minio -o wide
# Should show 4 pods across 4 nodes
```

### Step 6: Restore Data

```bash
# Configure mc for new distributed MinIO
mc alias set distributed http://minio-api.home admin changeme123

# Restore data
mc mirror --preserve /backup/minio-data/ distributed/

# Verify data
mc ls distributed/
```

### Step 7: Verify and Test

```bash
# Check cluster status
kubectl exec -n minio minio-0 -- mc admin info local

# Test data access
mc ls distributed/your-bucket/

# Test from application
# Update application configs to use new endpoint (same endpoint works!)
```

## Post-Migration Verification

### Health Checks

```bash
# Check all pods running
kubectl get pods -n minio

# Check distributed cluster status
kubectl exec -n minio minio-0 -- mc admin info local

# Expected output shows 4 servers online with erasure set info
```

### Performance Test

```bash
# Upload test
mc cp /path/to/large-file distributed/test-bucket/

# Download test
mc cp distributed/test-bucket/large-file /tmp/

# Check metrics
kubectl exec -n minio minio-0 -- mc admin prometheus metrics local
```

### Failure Test

```bash
# Simulate node failure (optional, be careful!)
kubectl cordon worker-01
kubectl delete pod minio-1 -n minio

# MinIO should continue operating with 3 nodes
# Data should auto-heal when node returns

# Uncordon node
kubectl uncordon worker-01
```

## Rollback Plan

If something goes wrong:

```bash
# 1. Stop distributed deployment
kubectl delete statefulset minio -n minio

# 2. Reapply standalone
kubectl apply -f standalone/

# 3. Restore from backup if needed
mc mirror /backup/minio-data/ standalone/
```

## Expansion Beyond 4 Nodes

Once you have 4 nodes running, you can add more in increments of 4:

```bash
# Add 4 more nodes (8 total)
# 1. Prepare 4 more nodes with SSDs
# 2. Create 4 more PVs (minio-pv-4 through minio-pv-7)
# 3. Update StatefulSet replicas to 8
kubectl scale statefulset minio -n minio --replicas=8

# 4. Update args in statefulset.yaml:
#    - server
#    - http://minio-{0...7}.minio-headless.minio.svc.cluster.local/data
```

## Troubleshooting

### Pods Not Starting

```bash
# Check PVC binding
kubectl get pvc -n minio

# Check node affinity
kubectl describe pv minio-pv-0

# Check mount on nodes
for node in master-01 worker-01 worker-02 worker-03; do
    ssh $node 'mount | grep minio'
done
```

### Cluster Not Forming

```bash
# Check pod logs
kubectl logs -n minio minio-0

# Common issues:
# - Time not synchronized between nodes (check with: timedatectl)
# - Network issues between pods (check with: kubectl exec -n minio minio-0 -- ping minio-1.minio-headless)
# - Different MinIO versions on nodes
```

### Data Healing Issues

```bash
# Check healing status
kubectl exec -n minio minio-0 -- mc admin heal local --verbose

# Force heal
kubectl exec -n minio minio-0 -- mc admin heal local --recursive
```

## Performance Tuning

### Optimize for Raspberry Pi

```yaml
# In statefulset.yaml, adjust resources:
resources:
  requests:
    memory: "1Gi"    # Increased for distributed mode
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

### Network Optimization

```bash
# Ensure nodes have good network connectivity
# Test bandwidth between nodes:
iperf3 -s  # On one node
iperf3 -c <node-ip>  # From another node

# Should see > 1Gbit/s for good performance
```

## Best Practices

1. **Keep nodes balanced**: Try to keep similar storage sizes on all nodes
2. **Monitor health**: Regularly check cluster status with `mc admin info`
3. **Enable versioning**: Protect against accidental deletes
4. **Set up monitoring**: Use Prometheus to track metrics
5. **Regular backups**: Even with redundancy, maintain offsite backups
6. **Document changes**: Keep track of node additions/removals

## References

- [MinIO Distributed Setup](https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-multi-node-multi-drive.html)
- [MinIO Erasure Coding](https://min.io/docs/minio/linux/operations/concepts/erasure-coding.html)
- [MinIO Healing](https://min.io/docs/minio/linux/operations/data-recovery/heal-objects-using-bitrot-protection.html)

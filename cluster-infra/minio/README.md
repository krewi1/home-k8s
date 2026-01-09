# MinIO Object Storage

S3-compatible object storage for the Kubernetes cluster. Currently deployed in standalone mode with expansion capability to distributed mode.

## Current Setup

**Mode:** Standalone (Single Node)
**Storage:** `/mnt/minio-data` on master node (~800GB SSD)
**Access:** Via nginx-ingress on `*.home` domain

## Architecture

### Standalone Mode (Current)

```
Client Request
    ↓
nginx-ingress (*.home)
    ↓
MinIO Pod (master node)
    ↓
/mnt/minio-data (SSD partition)
```

### Distributed Mode (Future)

```
Client Request
    ↓
nginx-ingress (*.home)
    ↓
MinIO StatefulSet (4+ nodes)
    ├─ minio-0 → /mnt/minio-data (master)
    ├─ minio-1 → /mnt/minio-data (worker-01)
    ├─ minio-2 → /mnt/minio-data (worker-02)
    └─ minio-3 → /mnt/minio-data (worker-03)
```

## Installation

### Prerequisites

1. **SSD Setup**: Run setup-ssd.sh on master node first
   ```bash
   cd ../k8s-init
   sudo ./setup-ssd.sh
   ```

2. **Verify Mount**:
   ```bash
   df -h | grep minio
   # Should show /mnt/minio-data mounted
   ```

3. **Check Permissions**:
   ```bash
   ls -la /mnt/minio-data
   # Should be owned by 1000:1000
   ```

### Deploy MinIO

```bash
./install.sh
```

The installation script will:
- Create namespace and resources
- Deploy MinIO in standalone mode
- Create Ingress for web access
- Configure PersistentVolume using local SSD

## Access

### Web Console

```bash
# Via domain (through nginx-ingress)
http://minio.home

# Or with /etc/hosts entry
echo "192.168.0.221 minio.home" | sudo tee -a /etc/hosts
```

### API Endpoint

```bash
# For S3-compatible applications
http://minio-api.home
```

### Port Forward (Alternative)

```bash
# Console
kubectl port-forward -n minio svc/minio-console 9001:9001

# API
kubectl port-forward -n minio svc/minio 9000:9000
```

## Configuration

### Change Credentials

**Before Installation:**
```bash
# Edit secret.yaml
nano standalone/secret.yaml
```

**After Installation:**
1. Access web console at http://minio.home
2. Navigate to: Identity → Users
3. Change root password
4. Create additional users/policies

### Create Buckets

#### Via Web Console:
1. Login to http://minio.home
2. Go to "Buckets" → "Create Bucket"
3. Enter bucket name and create

#### Via mc CLI:
```bash
# Install MinIO Client
kubectl run -it --rm mc --image=minio/mc --restart=Never -- sh

# Configure alias
mc alias set myminio http://minio.minio:9000 admin changeme123

# Create bucket
mc mb myminio/my-bucket

# List buckets
mc ls myminio/
```

## Usage Examples

### Python (boto3)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://minio-api.home',
    aws_access_key_id='admin',
    aws_secret_access_key='changeme123'
)

# Upload file
s3.upload_file('local-file.txt', 'my-bucket', 'remote-file.txt')

# Download file
s3.download_file('my-bucket', 'remote-file.txt', 'downloaded.txt')
```

### Node.js (aws-sdk)

```javascript
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
    endpoint: 'http://minio-api.home',
    accessKeyId: 'admin',
    secretAccessKey: 'changeme123',
    s3ForcePathStyle: true,
    signatureVersion: 'v4'
});

// List buckets
s3.listBuckets((err, data) => {
    console.log(data.Buckets);
});
```

### From within Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-minio
spec:
  containers:
  - name: test
    image: amazon/aws-cli
    command:
    - sh
    - -c
    - |
      aws configure set aws_access_key_id admin
      aws configure set aws_secret_access_key changeme123
      aws --endpoint-url http://minio.minio:9000 s3 ls
```

## Monitoring

### Check Status

```bash
# Pod status
kubectl get pods -n minio

# Service status
kubectl get svc -n minio

# PVC usage
kubectl get pvc -n minio

# Storage usage
kubectl exec -n minio deployment/minio -- df -h /data
```

### View Logs

```bash
# Real-time logs
kubectl logs -n minio -f deployment/minio

# Last 100 lines
kubectl logs -n minio deployment/minio --tail=100
```

### Metrics

MinIO exposes Prometheus metrics at `/minio/v2/metrics/cluster`:

```bash
# Access metrics
kubectl port-forward -n minio svc/minio 9000:9000
curl http://localhost:9000/minio/v2/metrics/cluster
```

## Backup & Restore

### Backup Strategy

1. **Data Backup** (via MinIO replication or mc mirror):
   ```bash
   # Mirror to another MinIO instance
   mc mirror myminio/source-bucket otherminio/backup-bucket
   ```

2. **Metadata Backup**:
   ```bash
   # Export configuration
   kubectl get all,pvc,pv,ingress -n minio -o yaml > minio-backup.yaml
   ```

3. **SSD Snapshot** (at OS level):
   ```bash
   # Create LVM snapshot or rsync backup
   rsync -av /mnt/minio-data/ /backup/minio-data/
   ```

### Restore

```bash
# Restore from backup location
rsync -av /backup/minio-data/ /mnt/minio-data/

# Redeploy MinIO
./install.sh
```

## Expansion to Distributed Mode

When you add more Raspberry Pi nodes with SSDs, you can migrate to distributed mode for better performance, redundancy, and automatic healing.

**See:** `docs/expansion-guide.md` for detailed migration instructions.

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n minio

# Common issues:
# 1. PVC not bound - check PV node affinity
# 2. Mount permission denied - check ownership (1000:1000)
# 3. Port conflict - check if 9000/9001 already in use
```

### Cannot Access Web Console

```bash
# Check ingress
kubectl get ingress -n minio
kubectl describe ingress minio-console -n minio

# Test service directly
kubectl port-forward -n minio svc/minio-console 9001:9001
# Access http://localhost:9001

# Check nginx-ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### PVC Pending

```bash
# Check PV and PVC
kubectl get pv,pvc -n minio

# Check if PV node matches pod node
kubectl get pv minio-pv -o yaml | grep hostname
kubectl get pod -n minio -o wide

# Ensure /mnt/minio-data exists and is mounted
ssh master-01 'df -h | grep minio'
```

### Storage Full

```bash
# Check usage
kubectl exec -n minio deployment/minio -- df -h /data

# Clean up old versions (if versioning enabled)
mc rm --recursive --force --older-than 30d myminio/bucket-name

# Expand to distributed mode (see expansion guide)
```

## Security

### Best Practices

1. **Change default credentials** immediately after installation
2. **Create separate users** for each application
3. **Use bucket policies** to restrict access
4. **Enable versioning** for important buckets
5. **Enable encryption** for sensitive data

### Create Application User

```bash
# Via web console:
# Identity → Users → Create User

# Via mc CLI:
mc admin user add myminio myapp secretpassword
mc admin policy attach myminio readwrite --user myapp
```

### Bucket Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["arn:aws:iam:::user/myapp"]},
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::my-bucket/*"]
    }
  ]
}
```

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes MinIO from Kubernetes but does NOT delete data from `/mnt/minio-data`.

## Resources

- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [MinIO Client (mc)](https://min.io/docs/minio/linux/reference/minio-mc.html)
- [S3 API Compatibility](https://min.io/docs/minio/linux/developers/python/API.html)
- [Expansion Guide](docs/expansion-guide.md)

## Version Information

- **MinIO**: latest (pulled from minio/minio:latest)
- **Storage**: ~800GB local SSD on master node
- **Mode**: Standalone (expandable to distributed)
- **Ingress**: nginx-ingress on *.home domain

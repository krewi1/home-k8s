# Garage Object Storage

Lightweight, self-hosted S3-compatible object storage for the Kubernetes cluster. Currently deployed in standalone mode with expansion capability to distributed mode.

## Current Setup

**Mode:** Standalone (Single Node)
**Storage:** `/mnt/garage-data` on master node (~800GB SSD)
**Access:** Via nginx-ingress on `*.home` domain

## Why Garage?

Garage is a lightweight, open-source, geo-distributed S3-compatible object storage system specifically designed for self-hosted deployments. Unlike MinIO, it:
- Has no enterprise upselling
- Is truly lightweight and efficient
- Designed for self-hosted and homelab scenarios
- Active open-source community
- Better resource efficiency on Raspberry Pi

## Architecture

### Standalone Mode (Current)

```
Client Request
    ↓
nginx-ingress (*.home)
    ↓
Garage Pod (master node)
    ↓
/mnt/garage-data (SSD partition)
```

### Distributed Mode (Future)

```
Client Request
    ↓
nginx-ingress (*.home)
    ↓
Garage StatefulSet (3+ nodes)
    ├─ garage-0 → /mnt/garage-data (master)
    ├─ garage-1 → /mnt/garage-data (worker-01)
    └─ garage-2 → /mnt/garage-data (worker-02)
```

## Installation

### Prerequisites

1. **SSD Setup**: Ensure SSD is formatted and mounted
   ```bash
   # On master node
   sudo mkdir -p /mnt/garage-data
   sudo chown 1000:1000 /mnt/garage-data
   sudo chmod 755 /mnt/garage-data
   ```

2. **Verify Mount**:
   ```bash
   df -h | grep garage
   # Should show /mnt/garage-data mounted
   ```

3. **Check Permissions**:
   ```bash
   ls -la /mnt/garage-data
   # Should be owned by 1000:1000
   ```

### Deploy Garage

```bash
./install.sh
```

The installation script will:
- Create namespace and resources
- Deploy Garage in standalone mode
- Create Ingress for web access
- Configure PersistentVolume using local SSD

## Access

### S3 API Endpoint

```bash
# Via domain (through nginx-ingress)
http://garage-api.home

# Or with /etc/hosts entry
echo "192.168.0.221 garage-api.home" | sudo tee -a /etc/hosts
```

### Web UI

```bash
# Via domain
http://garage.home
```

### Port Forward (Alternative)

```bash
# S3 API
kubectl port-forward -n garage svc/garage 3900:3900

# Admin API
kubectl port-forward -n garage svc/garage 3903:3903
```

## Configuration

### Initial Setup

After installation, you need to configure Garage:

```bash
# 1. Get the node ID
kubectl exec -n garage deployment/garage -- sh -c "garage status"

# 2. Assign the node to a zone with capacity 1
NODE_ID=$(kubectl exec -n garage deployment/garage -- sh -c "garage status" | grep 'Node ID' | awk '{print $3}')
kubectl exec -n garage deployment/garage -- sh -c "garage layout assign -z dc1 -c 1 $NODE_ID"

# 3. Apply the layout
kubectl exec -n garage deployment/garage -- sh -c "garage layout apply --version 1"

# 4. Verify the layout
kubectl exec -n garage deployment/garage -- sh -c "garage status"
```

### Create Keys and Buckets

#### Automated Setup (Recommended)

For automated bucket setup (especially useful for Thanos), see the helper script:

```bash
cd examples
./setup-thanos-bucket.sh
```

See [examples/README.md](examples/README.md) for more details.

#### Manual Setup

```bash
# Create a key
kubectl exec -n garage deployment/garage -- sh -c "garage key create my-app-key"

# Save the access key and secret key from output

# Create a bucket
kubectl exec -n garage deployment/garage -- sh -c "garage bucket create my-bucket"

# Allow the key to access the bucket
kubectl exec -n garage deployment/garage -- sh -c "garage bucket allow --read --write my-bucket --key my-app-key"

# List buckets
kubectl exec -n garage deployment/garage -- sh -c "garage bucket list"
```

### Change RPC Secret

**Before Installation:**
```bash
# Edit secret.yaml and change the rpc_secret value
nano standalone/secret.yaml
```

**After Installation:**
```bash
# Update the secret (base64 encode your new config)
kubectl edit secret garage-config -n garage
# Then restart the deployment
kubectl rollout restart deployment/garage -n garage
```

## Usage Examples

### Python (boto3)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://garage-api.home',
    aws_access_key_id='<your-access-key>',
    aws_secret_access_key='<your-secret-key>',
    region_name='garage'
)

# Upload file
s3.upload_file('local-file.txt', 'my-bucket', 'remote-file.txt')

# Download file
s3.download_file('my-bucket', 'remote-file.txt', 'downloaded.txt')

# List objects
response = s3.list_objects_v2(Bucket='my-bucket')
for obj in response.get('Contents', []):
    print(obj['Key'])
```

### Node.js (aws-sdk)

```javascript
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
    endpoint: 'http://garage-api.home',
    accessKeyId: '<your-access-key>',
    secretAccessKey: '<your-secret-key>',
    region: 'garage',
    s3ForcePathStyle: true,
    signatureVersion: 'v4'
});

// List buckets
s3.listBuckets((err, data) => {
    if (err) console.log(err);
    else console.log(data.Buckets);
});

// Upload file
s3.putObject({
    Bucket: 'my-bucket',
    Key: 'file.txt',
    Body: 'Hello from Garage!'
}, (err, data) => {
    if (err) console.log(err);
    else console.log(data);
});
```

### From within Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-garage
spec:
  containers:
  - name: test
    image: amazon/aws-cli
    command:
    - sh
    - -c
    - |
      aws configure set aws_access_key_id <your-access-key>
      aws configure set aws_secret_access_key <your-secret-key>
      aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 ls
```

### Using garage CLI

```bash
# Execute commands inside the pod
kubectl exec -n garage deployment/garage -- sh -c "garage [command]"

# Common commands:
garage status                          # Show cluster status
garage key list                        # List all keys
garage key info <key-id>               # Show key details
garage bucket list                     # List all buckets
garage bucket info <bucket-name>       # Show bucket details
garage layout show                     # Show current layout
```

## Monitoring

### Check Status

```bash
# Pod status
kubectl get pods -n garage

# Service status
kubectl get svc -n garage

# PVC usage
kubectl get pvc -n garage

# Storage usage
kubectl exec -n garage deployment/garage -- df -h /data

# Garage cluster status
kubectl exec -n garage deployment/garage -- sh -c "garage status"
```

### View Logs

```bash
# Real-time logs
kubectl logs -n garage -f deployment/garage

# Last 100 lines
kubectl logs -n garage deployment/garage --tail=100
```

### Metrics

Garage exposes metrics for Prometheus:

```bash
# Access metrics
kubectl port-forward -n garage svc/garage 3903:3903
curl http://localhost:3903/metrics
```

## Backup & Restore

### Backup Strategy

1. **Data Backup** (filesystem level):
   ```bash
   # Snapshot or rsync backup
   rsync -av /mnt/garage-data/ /backup/garage-data/
   ```

2. **Metadata Backup**:
   ```bash
   # Export Garage configuration
   kubectl exec -n garage deployment/garage -- sh -c "garage key list > garage-keys-backup.txt"
   kubectl exec -n garage deployment/garage -- sh -c "garage bucket list > garage-buckets-backup.txt"

   # Export Kubernetes resources
   kubectl get all,pvc,pv,ingress,secret -n garage -o yaml > garage-k8s-backup.yaml
   ```

### Restore

```bash
# Restore data from backup
rsync -av /backup/garage-data/ /mnt/garage-data/

# Redeploy Garage
./install.sh

# Recreate keys and buckets using backup files
```

## Expansion to Distributed Mode

When you add more Raspberry Pi nodes with SSDs, you can migrate to distributed mode for better performance, redundancy, and automatic healing.

**See:** `docs/expansion-guide.md` for detailed migration instructions.

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n garage

# Common issues:
# 1. PVC not bound - check PV node affinity
# 2. Mount permission denied - check ownership (1000:1000)
# 3. Configuration error - check garage.toml in ConfigMap
```

### Cannot Access S3 API

```bash
# Check ingress
kubectl get ingress -n garage
kubectl describe ingress garage-api -n garage

# Test service directly
kubectl port-forward -n garage svc/garage 3900:3900
# Test: curl http://localhost:3900

# Check nginx-ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### PVC Pending

```bash
# Check PV and PVC
kubectl get pv,pvc -n garage

# Check if PV node matches pod node
kubectl get pv garage-pv -o yaml | grep hostname
kubectl get pod -n garage -o wide

# Ensure /mnt/garage-data exists and is mounted
ssh master-01 'df -h | grep garage'
```

### Storage Full

```bash
# Check usage
kubectl exec -n garage deployment/garage -- df -h /data

# Clean up old objects
# Implement bucket lifecycle policies or manually delete old objects

# Expand to distributed mode (see expansion guide)
```

### Garage Not Accepting Requests

```bash
# Check if layout is applied
kubectl exec -n garage deployment/garage -- sh -c "garage status"

# If layout shows version 0 or not configured:
NODE_ID=$(kubectl exec -n garage deployment/garage -- sh -c "garage status | grep 'Node ID' | awk '{print $3}')"
kubectl exec -n garage deployment/garage -- sh -c "garage layout assign -z dc1 -c 1 $NODE_ID"
kubectl exec -n garage deployment/garage -- sh -c "garage layout apply --version 1"
```

## Security

### Best Practices

1. **Change default RPC secret** immediately after installation
2. **Create separate keys** for each application
3. **Use bucket permissions** to restrict access
4. **Rotate keys regularly**
5. **Use HTTPS** for production (cert-manager + Let's Encrypt)

### Create Application Key

```bash
# Create a key with limited permissions
kubectl exec -n garage deployment/garage -- sh -c "garage key create app-name"

# Grant read-only access
kubectl exec -n garage deployment/garage -- sh -c "garage bucket allow --read my-bucket --key app-name"

# Grant read-write access
kubectl exec -n garage deployment/garage -- sh -c "garage bucket allow --read --write my-bucket --key app-name"
```

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes Garage from Kubernetes but does NOT delete data from `/mnt/garage-data`.

To fully clean up:

```bash
# Remove data
sudo rm -rf /mnt/garage-data
```

## Comparison: Garage vs MinIO

| Feature | Garage | MinIO |
|---------|--------|-------|
| License | AGPLv3 (fully open) | AGPLv3 (features locked behind enterprise) |
| Resource Usage | Very lightweight | Heavier |
| Target Use Case | Self-hosted, homelab | Enterprise |
| Distributed Mode | Designed for it | Requires many nodes |
| Community | Active FOSS community | Enterprise-focused |
| Complexity | Simple | More complex |

## Resources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/)
- [Garage GitHub](https://git.deuxfleurs.fr/Deuxfleurs/garage)
- [S3 API Compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [Garage Admin Guide](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/)

## Version Information

- **Garage**: v1.0.0 (dxflrs/garage:v1.0.0)
- **Storage**: ~800GB local SSD on master node
- **Mode**: Standalone (expandable to distributed)
- **Ingress**: nginx-ingress on *.home domain

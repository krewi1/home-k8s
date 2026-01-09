# MinIO Quick Start Guide

## Prerequisites

Ensure SSD is set up on master node:

```bash
# Check if mounted
ssh master-01 'df -h | grep minio'

# Should show:
# /dev/sda3  ~800G  ... /mnt/minio-data

# If not mounted, run setup
cd ../../k8s-init
sudo ./setup-ssd.sh
```

## Installation

```bash
cd cluster-infra/minio
./install.sh
```

Installation takes ~2-3 minutes.

## Access

### Web Console

```
http://minio.home
```

**Default Credentials:**
- Username: `admin`
- Password: `changeme123`

⚠️ **Change these immediately after first login!**

### API Endpoint

For applications using S3 API:

```
http://minio-api.home
```

## Quick Test

```bash
# Install MinIO client
kubectl run -it --rm mc --image=minio/mc --restart=Never -- sh

# Inside the pod:
mc alias set myminio http://minio.minio:9000 admin changeme123
mc mb myminio/test-bucket
mc ls myminio/
echo "hello minio" > test.txt
mc cp test.txt myminio/test-bucket/
mc cat myminio/test-bucket/test.txt
```

## Usage in Applications

### Python

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://minio-api.home',
    aws_access_key_id='admin',
    aws_secret_access_key='changeme123'
)

s3.upload_file('file.txt', 'my-bucket', 'file.txt')
```

### Node.js

```javascript
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
    endpoint: 'http://minio-api.home',
    accessKeyId: 'admin',
    secretAccessKey: 'changeme123',
    s3ForcePathStyle: true
});
```

### Kubernetes Pod

```yaml
env:
- name: S3_ENDPOINT
  value: "http://minio.minio:9000"
- name: S3_ACCESS_KEY
  value: "admin"
- name: S3_SECRET_KEY
  value: "changeme123"
```

## Common Operations

### Create Bucket

```bash
# Via web console: Buckets → Create Bucket
# Or via CLI:
mc mb myminio/bucket-name
```

### Upload File

```bash
mc cp local-file.txt myminio/bucket-name/
```

### List Files

```bash
mc ls myminio/bucket-name/
```

### Download File

```bash
mc cp myminio/bucket-name/file.txt downloaded.txt
```

## Monitoring

```bash
# Check pod status
kubectl get pods -n minio

# Check storage usage
kubectl exec -n minio deployment/minio -- df -h /data

# View logs
kubectl logs -n minio -f deployment/minio
```

## Troubleshooting

### Cannot Access Web Console

```bash
# Check ingress
kubectl get ingress -n minio

# Port-forward as alternative
kubectl port-forward -n minio svc/minio-console 9001:9001
# Then access: http://localhost:9001
```

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n minio

# Common fix: Check permissions on master node
ssh master-01 'sudo chown -R 1000:1000 /mnt/minio-data'
```

## Next Steps

- **Security**: Change default credentials
- **Buckets**: Create buckets for your applications
- **Users**: Create application-specific users with restricted permissions
- **Expansion**: See `docs/expansion-guide.md` when adding more nodes

## Uninstall

```bash
./uninstall.sh
```

**Note:** Data at `/mnt/minio-data` is preserved.

## More Information

- Full Documentation: [README.md](README.md)
- Expansion Guide: [docs/expansion-guide.md](docs/expansion-guide.md)
- MinIO Docs: https://min.io/docs/minio/kubernetes/upstream/

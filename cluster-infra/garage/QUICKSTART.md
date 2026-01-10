# Garage Quick Start Guide

## Prerequisites

Ensure SSD is set up on master node:

```bash
# Check if mounted
ssh master-01 'df -h | grep garage'

# If not mounted, create the directory
ssh master-01 'sudo mkdir -p /mnt/garage-data'
ssh master-01 'sudo chown 1000:1000 /mnt/garage-data'
ssh master-01 'sudo chmod 755 /mnt/garage-data'
```

## Installation

```bash
cd cluster-infra/garage
./install.sh
```

Installation takes ~2-3 minutes.

## Initial Configuration

After installation, configure Garage cluster:

```bash
# 1. Get the node ID
kubectl exec -n garage deployment/garage -- garage status

# 2. Assign node to zone with capacity 1
NODE_ID=$(kubectl exec -n garage deployment/garage -- garage status | grep 'Node ID' | awk '{print $3}')
kubectl exec -n garage deployment/garage -- garage layout assign -z dc1 -c 1 $NODE_ID

# 3. Apply the layout
kubectl exec -n garage deployment/garage -- garage layout apply --version 1

# 4. Verify
kubectl exec -n garage deployment/garage -- garage status
```

## Access

### S3 API Endpoint

```
http://garage-api.home
```

**Internal (from pods):**
```
http://garage.garage.svc.cluster.local:3900
```

### Web UI

```
http://garage.home
```

## Create Keys and Buckets

### Option 1: Automated Script (Recommended for Thanos)

For setting up the Thanos bucket, use the automated script:

```bash
cd examples
./setup-thanos-bucket.sh
```

This will create the bucket and display credentials to copy to `observability/prometheus/garage-secret.yaml`.

### Option 2: Manual Setup

```bash
# Create a key for your application
kubectl exec -n garage deployment/garage -- sh -c "garage key create my-app"

# Save the Access Key ID and Secret Access Key from output

# Create a bucket
kubectl exec -n garage deployment/garage -- sh -c "garage bucket create my-bucket"

# Grant permissions
kubectl exec -n garage deployment/garage -- sh -c "garage bucket allow --read --write my-bucket --key my-app"

# List buckets
kubectl exec -n garage deployment/garage -- sh -c "garage bucket list"
```

## Quick Test

```bash
# Test with AWS CLI
kubectl run -it --rm aws-test --image=amazon/aws-cli --restart=Never -- sh

# Inside the pod:
aws configure set aws_access_key_id <your-access-key>
aws configure set aws_secret_access_key <your-secret-key>
aws configure set region garage
aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 ls

# Upload a file
echo "hello garage" > test.txt
aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 cp test.txt s3://my-bucket/

# List objects
aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 ls s3://my-bucket/

# Download file
aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 cp s3://my-bucket/test.txt downloaded.txt
cat downloaded.txt
```

## Usage in Applications

### Python

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://garage-api.home',
    aws_access_key_id='<your-access-key>',
    aws_secret_access_key='<your-secret-key>',
    region_name='garage'
)

# Create bucket
s3.create_bucket(Bucket='my-bucket')

# Upload file
s3.upload_file('file.txt', 'my-bucket', 'file.txt')

# Download file
s3.download_file('my-bucket', 'file.txt', 'downloaded.txt')

# List objects
response = s3.list_objects_v2(Bucket='my-bucket')
for obj in response.get('Contents', []):
    print(obj['Key'])
```

### Node.js

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

// Upload file
s3.putObject({
    Bucket: 'my-bucket',
    Key: 'file.txt',
    Body: 'Hello from Garage!'
}, (err, data) => {
    if (err) console.log(err);
    else console.log('Upload successful:', data);
});
```

### Kubernetes Pod

```yaml
env:
- name: S3_ENDPOINT
  value: "http://garage.garage.svc.cluster.local:3900"
- name: S3_REGION
  value: "garage"
- name: S3_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: s3-credentials
      key: access-key
- name: S3_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: s3-credentials
      key: secret-key
```

## Common Operations

### List All Keys

```bash
kubectl exec -n garage deployment/garage -- garage key list
```

### Get Key Info

```bash
kubectl exec -n garage deployment/garage -- garage key info <key-id>
```

### Create Bucket

```bash
kubectl exec -n garage deployment/garage -- garage bucket create bucket-name
```

### List Buckets

```bash
kubectl exec -n garage deployment/garage -- garage bucket list
```

### Grant Bucket Permissions

```bash
# Read-only
kubectl exec -n garage deployment/garage -- garage bucket allow --read bucket-name --key key-name

# Read-write
kubectl exec -n garage deployment/garage -- garage bucket allow --read --write bucket-name --key key-name
```

### Revoke Bucket Permissions

```bash
kubectl exec -n garage deployment/garage -- garage bucket deny --read --write bucket-name --key key-name
```

### Delete Key

```bash
kubectl exec -n garage deployment/garage -- garage key delete key-name
```

### Delete Bucket

```bash
# First, ensure bucket is empty
kubectl exec -n garage deployment/garage -- garage bucket delete bucket-name
```

## Monitoring

```bash
# Check pod status
kubectl get pods -n garage

# Check cluster status
kubectl exec -n garage deployment/garage -- garage status

# Check storage usage
kubectl exec -n garage deployment/garage -- df -h /data

# View logs
kubectl logs -n garage -f deployment/garage

# Check metrics (Prometheus format)
kubectl port-forward -n garage svc/garage 3903:3903
curl http://localhost:3903/metrics
```

## Troubleshooting

### Cannot Access S3 API

```bash
# Check ingress
kubectl get ingress -n garage

# Port-forward as alternative
kubectl port-forward -n garage svc/garage 3900:3900
# Then test: curl http://localhost:3900
```

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n garage

# Common fix: Check permissions on master node
ssh master-01 'sudo chown -R 1000:1000 /mnt/garage-data'
ssh master-01 'sudo chmod 755 /mnt/garage-data'
```

### Garage Not Accepting Requests

```bash
# Check if layout is applied
kubectl exec -n garage deployment/garage -- garage status

# If no layout configured:
NODE_ID=$(kubectl exec -n garage deployment/garage -- garage status | grep 'Node ID' | awk '{print $3}')
kubectl exec -n garage deployment/garage -- garage layout assign -z dc1 -c 1 $NODE_ID
kubectl exec -n garage deployment/garage -- garage layout apply --version 1
```

### 403 Forbidden Errors

```bash
# Check bucket permissions
kubectl exec -n garage deployment/garage -- garage bucket info bucket-name

# Grant missing permissions
kubectl exec -n garage deployment/garage -- garage bucket allow --read --write bucket-name --key key-name
```

## Next Steps

- **Security**: Change default RPC secret (`rpc_secret` field) in `standalone/secret.yaml`
- **Keys**: Create application-specific keys with limited permissions
- **Buckets**: Create buckets for your applications
- **Monitoring**: Configure Prometheus to scrape Garage metrics
- **Expansion**: See `docs/expansion-guide.md` when adding more nodes

## Uninstall

```bash
./uninstall.sh
```

**Note:** Data at `/mnt/garage-data` is preserved.

To completely remove:
```bash
sudo rm -rf /mnt/garage-data
```

## More Information

- Full Documentation: [README.md](README.md)
- Expansion Guide: [docs/expansion-guide.md](docs/expansion-guide.md)
- Garage Docs: https://garagehq.deuxfleurs.fr/
- S3 Compatibility: https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/

## Garage CLI Reference

```bash
# Cluster management
garage status                              # Show cluster status
garage layout show                         # Show current layout
garage layout assign -z <zone> -c <cap> <node-id>  # Assign node to zone
garage layout apply --version <n>          # Apply layout changes

# Key management
garage key list                            # List all keys
garage key create <name>                   # Create new key
garage key info <key-id>                   # Show key details
garage key delete <key-id>                 # Delete key

# Bucket management
garage bucket list                         # List all buckets
garage bucket create <name>                # Create bucket
garage bucket info <name>                  # Show bucket details
garage bucket delete <name>                # Delete bucket (must be empty)
garage bucket allow [--read] [--write] <bucket> --key <key>   # Grant permissions
garage bucket deny [--read] [--write] <bucket> --key <key>    # Revoke permissions
```

# Garage Examples

This directory contains example scripts and configurations for working with Garage.

## Scripts

### setup-thanos-bucket.sh

Automated script to create and configure a bucket for Thanos metrics storage.

**What it does:**
1. Creates a Garage key named `thanos-key`
2. Creates a bucket named `thanos`
3. Grants read/write permissions
4. Displays the credentials needed for Prometheus configuration

**Prerequisites:**
```bash
# macOS
brew install awscli

# Linux
sudo apt install awscli
```

**Usage:**
```bash
./setup-thanos-bucket.sh
```

The script will:
- Port-forward to Garage S3 API (localhost:3900)
- Create the key and bucket using a combination of `garage` CLI and AWS CLI
- Display the credentials you need to copy to `observability/prometheus/garage-secret.yaml`

**Example Output:**
```
=========================================
Thanos Bucket Configuration
=========================================

Bucket Name: thanos
Access Key ID: GK1234567890abcdef...
Secret Access Key: 0123456789abcdef...
Endpoint: http://garage.garage.svc.cluster.local:3900
Region: garage

Next Steps:
1. Update observability/prometheus/garage-secret.yaml with these credentials
2. Apply the secret:
   kubectl apply -f observability/prometheus/garage-secret.yaml
=========================================
```

## Manual Setup (Alternative)

If you prefer to do it manually:

### Using kubectl exec

```bash
# Get a shell in the Garage container
kubectl exec -it -n garage deployment/garage -- sh

# Inside the container:
garage status
garage key create thanos-key
garage bucket create thanos
garage bucket allow --read --write thanos --key thanos-key
garage key info thanos-key
```

### Using AWS CLI from host

```bash
# Port-forward
kubectl port-forward -n garage svc/garage 3900:3900 &

# Configure AWS CLI
export AWS_ACCESS_KEY_ID="<from garage key create>"
export AWS_SECRET_ACCESS_KEY="<from garage key create>"
export AWS_DEFAULT_REGION="garage"

# Create bucket
aws --endpoint-url http://localhost:3900 s3 mb s3://thanos

# List buckets
aws --endpoint-url http://localhost:3900 s3 ls

# Upload test file
echo "test" > test.txt
aws --endpoint-url http://localhost:3900 s3 cp test.txt s3://thanos/

# List objects
aws --endpoint-url http://localhost:3900 s3 ls s3://thanos/
```

## Common Operations

### List all buckets
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage bucket list"
```

### Get bucket info
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage bucket info thanos"
```

### List all keys
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage key list"
```

### Get key info
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage key info thanos-key"
```

### Delete bucket (must be empty)
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage bucket delete thanos"
```

### Delete key
```bash
kubectl exec -n garage deployment/garage -- sh -c "garage key delete thanos-key"
```

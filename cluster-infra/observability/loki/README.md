# Loki Log Aggregation

Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. This deployment uses the official Grafana Helm chart and stores logs in Garage S3-compatible storage.

## Current Setup

**Deployment:** Helm chart (SingleBinary mode - monolithic)
**Short-term Retention:** 7 days (20Gi local storage)
**Long-term Storage:** Garage bucket `loki`
**Total Retention:** 7 days (all in Garage)
**Access:** Internal service endpoint + port-forward for debugging

## Architecture

```
Log Sources (Alloy/Promtail)
    ↓
Loki Gateway (loki-gateway service)
    ↓
Loki SingleBinary
    ├─ Local cache (20Gi)
    └─ Chunks + Indexes → Garage bucket 'loki' (S3)
         ↓
    Compactor (cleanup old data after 7 days)
         ↓
Grafana (query and visualization)
```

## Installation

### Prerequisites

1. **Helm 3** installed
2. **Garage** running with available storage
3. **kubectl** configured

### Deploy Loki

```bash
# Make the script executable
chmod +x install.sh

# Run installation
./install.sh
```

The installation will:
1. Check prerequisites (kubectl, helm)
2. Check Garage availability
3. Prompt you to create `loki` bucket in Garage
4. Prompt for Garage credentials
5. Add Grafana Helm repository
6. Install Loki via Helm with custom values
7. Wait for deployment to be ready

## Manual Setup Steps

If you prefer manual installation:

### 1. Create Garage Bucket and Key

```bash
# Create key
kubectl exec -n garage deployment/garage -- sh -c "garage key create loki-key"

# Create bucket
kubectl exec -n garage deployment/garage -- sh -c "garage bucket create loki"

# Grant permissions
kubectl exec -n garage deployment/garage -- sh -c "garage bucket allow --read --write loki --key loki-key"

# Get credentials
kubectl exec -n garage deployment/garage -- sh -c "garage key info loki-key"
```

### 2. Update values.yaml

Edit `values.yaml` and replace the placeholder credentials:

```yaml
loki:
  storage:
    s3:
      accessKeyId: <your-garage-access-key-id>
      secretAccessKey: <your-garage-secret-access-key>
```

### 3. Install via Helm

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace observability

# Install Loki
helm install loki grafana/loki \
  --namespace observability \
  --values values.yaml \
  --wait
```

## Access

### Internal (from Grafana)

```
http://loki-gateway.observability.svc.cluster.local:80
```

### Port Forward (debugging)

```bash
kubectl port-forward -n observability svc/loki-gateway 3100:80
# Access: http://localhost:3100
```

## Configuration

### Current Settings (values.yaml)

- **Deployment Mode:** SingleBinary (monolithic)
- **Retention Period:** 7 days (168h)
- **Local Storage:** 20Gi
- **S3 Storage:** Garage bucket 'loki'
- **S3 Endpoint:** garage.garage.svc.cluster.local:3900
- **S3 Path Style:** Forced (required for Garage)
- **Compaction:** Enabled with retention

### Adjust Retention

Edit `values.yaml`:

```yaml
loki:
  limits_config:
    retention_period: 336h  # Change to 14 days
```

Then upgrade:
```bash
helm upgrade loki grafana/loki -n observability -f values.yaml
```

### Change Storage Size

Edit `values.yaml`:

```yaml
singleBinary:
  persistence:
    size: 30Gi  # Increase from 20Gi
```

Then upgrade:
```bash
helm upgrade loki grafana/loki -n observability -f values.yaml
```

## Grafana Integration

### Add Loki Data Source

1. Go to **Configuration → Data Sources → Add data source**
2. Select **Loki**
3. Configure:
   - **Name**: Loki
   - **URL**: `http://loki-gateway.observability.svc.cluster.local:80`
   - **Access**: Server (default)
4. Click **Save & Test**

### Query Logs

LogQL examples:

```logql
# All logs from a namespace
{namespace="default"}

# Logs from specific pod
{pod="my-pod-name"}

# Filter by app label
{app="nginx"}

# Search for error messages
{namespace="default"} |= "error"

# Count errors per minute
sum(rate({namespace="default"} |= "error" [1m])) by (pod)
```

## Log Collection

Loki doesn't collect logs itself. You need a log collector like:

- **Grafana Alloy** (recommended, will be deployed later)
- **Promtail**
- **Fluentd with Loki output**
- **Vector**

These will be configured separately to ship logs to Loki.

## Monitoring

### Check Status

```bash
# Helm release status
helm status loki -n observability

# Pod status
kubectl get pods -n observability -l app.kubernetes.io/name=loki

# Service status
kubectl get svc -n observability -l app.kubernetes.io/name=loki

# PVC usage
kubectl get pvc -n observability
```

### View Logs

```bash
# Real-time logs
kubectl logs -n observability -f -l app.kubernetes.io/name=loki

# Specific component (e.g., gateway)
kubectl logs -n observability -f -l app.kubernetes.io/component=gateway
```

### Metrics

Loki exposes Prometheus metrics:

```bash
# Access metrics
kubectl port-forward -n observability svc/loki-gateway 3100:80
curl http://localhost:3100/metrics
```

### Health Check

```bash
kubectl port-forward -n observability svc/loki-gateway 3100:80
curl http://localhost:3100/ready
```

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n observability -l app.kubernetes.io/name=loki

# Common issues:
# 1. PVC not bound - check storage class availability
# 2. Garage credentials wrong - check values.yaml
# 3. Garage not accessible - check network connectivity
```

### Cannot Connect to Garage

```bash
# Check Loki logs
kubectl logs -n observability -l app.kubernetes.io/name=loki | grep -i garage

# Common issues:
# 1. Garage credentials wrong - check values.yaml and reinstall
# 2. Bucket doesn't exist - create it with garage CLI
# 3. Network issue - check Garage service accessibility

# Test Garage connection from Loki pod
kubectl exec -n observability -l app.kubernetes.io/name=loki -- wget -O- http://garage.garage.svc.cluster.local:3900
```

### No Logs Appearing

```bash
# Check if Loki is receiving logs
kubectl logs -n observability -l app.kubernetes.io/name=loki | grep "POST /loki/api/v1/push"

# If no logs, check:
# 1. Log collector (Alloy/Promtail) is running
# 2. Log collector is configured to send to loki-gateway
# 3. Network connectivity between collector and Loki
```

### Helm Upgrade Issues

```bash
# Check Helm release status
helm list -n observability

# View release history
helm history loki -n observability

# Rollback if needed
helm rollback loki -n observability
```

## Backup & Restore

### Backup Strategy

**1. Garage Data (Most Important)**
- All log chunks and indexes are in Garage bucket `loki`
- Use Garage backup mechanisms

**2. Helm Values**
- Keep `values.yaml` in version control
- This contains all configuration

```bash
# Backup Helm values
cp values.yaml values.yaml.backup
```

**3. Helm Release Configuration**

```bash
# Export Helm release values
helm get values loki -n observability > loki-values-backup.yaml
```

### Restore

```bash
# Garage data is already there (no restore needed)

# Restore Helm release
helm install loki grafana/loki \
  --namespace observability \
  --values values.yaml \
  --wait
```

## Upgrade Loki

```bash
# Update Helm repo
helm repo update grafana

# Upgrade to latest version
helm upgrade loki grafana/loki \
  --namespace observability \
  --values values.yaml \
  --wait

# Or upgrade to specific version
helm upgrade loki grafana/loki \
  --namespace observability \
  --values values.yaml \
  --version 6.0.0 \
  --wait
```

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes Loki Helm release but does NOT delete:
- PVC in observability namespace
- Data in Garage bucket `loki`

To fully clean up:

```bash
# Remove PVC
kubectl delete pvc -n observability -l app.kubernetes.io/name=loki

# Remove Garage bucket
kubectl exec -n garage deployment/garage -- sh -c "garage bucket delete loki"
```

## Resources

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Loki Helm Chart](https://github.com/grafana/loki/tree/main/production/helm/loki)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Loki with S3](https://grafana.com/docs/loki/latest/operations/storage/s3/)

## Version Information

- **Loki Helm Chart**: Latest (from Grafana Helm repository)
- **Deployment Mode**: SingleBinary (monolithic)
- **Local Storage**: 20Gi
- **Object Storage**: Garage bucket 'loki'
- **Retention**: 7 days
- **Access**: Internal service endpoint (loki-gateway)

## Next Steps

1. ✅ Loki installed via Helm with Garage storage
2. ⬜ **Install Grafana** (if not already installed)
3. ⬜ Configure Grafana to use Loki as data source
4. ⬜ Install log collector (Alloy/Promtail)
5. ⬜ Configure log collector to ship logs to Loki
6. ⬜ Create Grafana dashboards for log visualization
7. ⬜ Set up log-based alerts

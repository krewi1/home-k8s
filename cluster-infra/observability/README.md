# Observability Stack

Monitoring and metrics collection for the Kubernetes cluster using **Prometheus + Thanos** with long-term storage in Garage.

## Current Setup

**Components:** Prometheus + Thanos (Sidecar, Query, Store Gateway, Compactor)
**Namespace:** observability
**Short-term Storage:** `/mnt/k8s-pvc/prometheus` (20Gi SSD - 7 days)
**Long-term Storage:** Garage bucket `thanos` (unlimited - 1 year+)
**Access:** Grafana for visualization, port-forward for debugging

## Architecture

```
Metrics Collection & Storage Flow:

Kubernetes Resources
    ├─ API Server
    ├─ Nodes
    ├─ Pods
    └─ cAdvisor
         ↓ (scrape every 15s)
    Prometheus
    (stores 7 days locally on SSD)
         ↓
    Thanos Sidecar
    (uploads 2h blocks to Garage)
         ↓
    Garage (thanos bucket)
    (long-term storage)
         ↓
    Thanos Compactor
    (downsamples: 5m for 90d, 1h for 365d)

Query Flow:

    User Query
         ↓
    Thanos Query
         ├─ Prometheus (recent 7 days) → fast SSD access
         └─ Thanos Store Gateway (older data) → reads from Garage
              ↓
         Unified Results
```

## Why Thanos?

**Problem:** Raspberry Pi nodes only have SD card storage (limited)
**Solution:** Keep recent metrics on master node's SSD, store everything else in Garage

**Benefits:**
- Query years of metrics without filling up SSD
- Automatic downsampling reduces storage cost
- High availability (can run multiple Prometheus instances)
- Global query view across all metrics
- Deduplication of metrics

## Installation

### Prerequisites

1. **Kubernetes cluster** running (K3s)
2. **kubectl** configured
3. **nginx-ingress** controller installed
4. **Garage** installed and running
5. **Master node** with `/mnt/k8s-pvc` mounted (100GB SSD partition)

### Deploy Prometheus + Thanos

You can install components together or separately:

**Option 1: Install Everything (Recommended)**
```bash
./install.sh
```

**Option 2: Install Step-by-Step**
```bash
# Step 1: Install Prometheus first
cd prometheus
./install.sh

# Step 2: Install Thanos components
cd ../thanos
./install.sh
```

The installation will:
1. Check Garage availability
2. Create `thanos` bucket in Garage
3. Create observability namespace
4. Deploy Prometheus with Thanos sidecar
5. Deploy Thanos components (Query, Store Gateway, Compactor)
6. Configure storage

## Access

### Grafana (Recommended)

Install Grafana and configure it to use Thanos Query as the data source:
- **Data Source Type**: Prometheus
- **URL**: `http://thanos-query.observability.svc.cluster.local:9090`

This provides the best visualization experience with dashboards.

### Port-Forward for Debugging

For debugging or direct access to the UIs:

```bash
# Thanos Query UI (shows recent + historical data)
kubectl port-forward -n observability svc/thanos-query 9090:9090
# Access http://localhost:9090

# Prometheus UI (shows only recent 7 days)
kubectl port-forward -n observability svc/prometheus 9091:9090
# Access http://localhost:9091
```

## Configuration

### Storage Retention

Current configuration:
- **Prometheus local**: 7 days on SSD (20Gi)
- **Garage raw data**: 30 days
- **Garage 5m downsampled**: 90 days
- **Garage 1h downsampled**: 365 days

To change retention, edit `thanos/compactor.yaml`:

```yaml
args:
  - --retention.resolution-raw=30d      # Raw metrics
  - --retention.resolution-5m=90d       # 5-minute downsampled
  - --retention.resolution-1h=365d      # 1-hour downsampled
```

### Garage Credentials

Update `prometheus/garage-secret.yaml` with your Garage credentials:

```yaml
config:
  bucket: thanos
  endpoint: garage.garage.svc.cluster.local:3900
  access_key: <your-garage-access-key>     # Change this
  secret_key: <your-garage-secret-key>     # Change this
```

### Scrape Configuration

Prometheus is configured to automatically discover and scrape:

1. **Kubernetes API Server** - Control plane metrics
2. **Kubernetes Nodes** - Node-level metrics
3. **Kubernetes Pods** - Application metrics (with annotations)
4. **cAdvisor** - Container resource metrics
5. **Service Endpoints** - Service-level metrics

### Annotating Services/Pods for Auto-Discovery

Add these annotations to enable automatic metrics scraping:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    prometheus.io/scrape: "true"    # Enable scraping
    prometheus.io/port: "8080"      # Metrics port
    prometheus.io/path: "/metrics"  # Metrics path (optional, default: /metrics)
spec:
  # ... service spec
```

## Usage

### Querying Metrics

**Recommended**: Use **Grafana** with Thanos Query as the data source for the best visualization experience.

For debugging/testing, use port-forward to access:
- **Thanos Query UI** - provides unified view of recent and historical data
- **Prometheus UI** - only shows recent 7 days of data

### Basic PromQL Queries

#### CPU Usage

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{pod!=""}[5m])) by (pod)

# CPU usage by namespace
sum(rate(container_cpu_usage_seconds_total{namespace!=""}[5m])) by (namespace)
```

#### Memory Usage

```promql
# Memory usage by pod
sum(container_memory_working_set_bytes{pod!=""}) by (pod)

# Memory usage by namespace
sum(container_memory_working_set_bytes{namespace!=""}) by (namespace)
```

#### Query Historical Data

Thanos automatically selects the best resolution based on query time range:

```promql
# Last 2 hours (uses raw data from Prometheus)
container_memory_usage_bytes{namespace="default"}[2h]

# Last 7 days (uses raw data from Prometheus/Garage)
container_memory_usage_bytes{namespace="default"}[7d]

# Last 30 days (uses raw data from Garage)
container_memory_usage_bytes{namespace="default"}[30d]

# Last 90 days (uses 5m downsampled data from Garage)
container_memory_usage_bytes{namespace="default"}[90d]

# Last 365 days (uses 1h downsampled data from Garage)
container_memory_usage_bytes{namespace="default"}[365d]
```

### Export Metrics from Your Application

#### Go (Prometheus Client)

```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "net/http"
)

func main() {
    http.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":8080", nil)
}
```

#### Python (prometheus_client)

```python
from prometheus_client import start_http_server, Counter

# Create metric
requests_total = Counter('requests_total', 'Total requests')

# Start metrics server
start_http_server(8080)

# Increment metric
requests_total.inc()
```

#### Node.js (prom-client)

```javascript
const client = require('prom-client');
const express = require('express');

const app = express();
const register = new client.Registry();

// Collect default metrics
client.collectDefaultMetrics({ register });

// Expose metrics endpoint
app.get('/metrics', (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(register.metrics());
});

app.listen(8080);
```

## Monitoring

### Check Component Status

```bash
# All components
kubectl get pods -n observability

# Specific components
kubectl get pods -n observability -l app=prometheus
kubectl get pods -n observability -l app=thanos-query
kubectl get pods -n observability -l app=thanos-store-gateway
kubectl get pods -n observability -l app=thanos-compactor

# Services
kubectl get svc -n observability

# Storage
kubectl get pvc -n observability
kubectl exec -n observability deployment/prometheus -- df -h /prometheus
```

### View Logs

```bash
# Prometheus
kubectl logs -n observability -f deployment/prometheus -c prometheus

# Thanos Sidecar
kubectl logs -n observability -f deployment/prometheus -c thanos-sidecar

# Thanos Query
kubectl logs -n observability -f deployment/thanos-query

# Thanos Store Gateway
kubectl logs -n observability -f deployment/thanos-store-gateway

# Thanos Compactor
kubectl logs -n observability -f deployment/thanos-compactor
```

### Check Thanos Stores

Port-forward to Thanos Query and visit `http://localhost:9090/stores` to see all connected data sources:
- Sidecar (recent data from Prometheus)
- Store Gateway (historical data from Garage)

### Verify Data in Garage

```bash
# Check Garage bucket
garage bucket info thanos

# List objects in bucket
garage bucket list thanos
```

## Backup & Restore

### Backup Strategy

**1. Garage Data (Most Important)**
- All historical metrics are in Garage bucket `thanos`
- Use Garage replication or backup mechanisms

```bash
# Backup Garage bucket (example with rclone)
rclone sync garage:thanos backup:thanos-backup
```

**2. Prometheus Local Data (Optional)**
- Only 7 days of data, already backed up to Garage
- Can be recreated from Garage if needed

```bash
# Backup local Prometheus data (optional)
rsync -av /mnt/k8s-pvc/prometheus/ /backup/prometheus/
```

**3. Configuration Backup**

```bash
# Export all resources
kubectl get all,cm,secret,pvc,pv,ingress -n observability -o yaml > observability-backup.yaml
```

### Restore

```bash
# Restore Garage data
rclone sync backup:thanos-backup garage:thanos

# Restore Prometheus (optional)
rsync -av /backup/prometheus/ /mnt/k8s-pvc/prometheus/

# Redeploy stack
./install.sh
```

## Troubleshooting

### Prometheus Pod Not Starting

```bash
# Check events
kubectl describe pod -n observability -l app=prometheus

# Common issues:
# 1. PVC not bound - check PV matches node
# 2. Directory not created - run setup commands on master node
# 3. Permission denied - check ownership (65534:65534)
```

### Thanos Sidecar Not Uploading to Garage

```bash
# Check sidecar logs
kubectl logs -n observability deployment/prometheus -c thanos-sidecar

# Common issues:
# 1. Garage credentials wrong - check prometheus/garage-secret.yaml
# 2. Bucket doesn't exist - create it with: garage bucket create thanos
# 3. Network issue - check Garage service accessibility

# Test Garage connection
kubectl run -n observability test-garage --image=amazon/aws-cli --rm -i --command -- sh -c "
  export AWS_ACCESS_KEY_ID=<your-key>
  export AWS_SECRET_ACCESS_KEY=<your-secret>
  aws --endpoint-url http://garage.garage.svc.cluster.local:3900 s3 ls s3://thanos
"
```

### No Historical Data in Thanos Query

```bash
# Check Store Gateway
kubectl logs -n observability deployment/thanos-store-gateway

# Verify data in Garage
# Check http://localhost:9090/stores - should show Store Gateway

# Check if blocks are uploaded
# Wait at least 2 hours after installation for first upload
```

### Compactor Not Running

```bash
# Check compactor logs
kubectl logs -n observability deployment/thanos-compactor

# Compactor only runs when there's data to compact
# Wait for multiple 2h blocks to accumulate
```

### High Memory Usage

```bash
# Check memory usage
kubectl top pod -n observability

# Reduce retention if needed
# Edit thanos/compactor.yaml and redeploy

# Or increase memory limits
kubectl edit deployment prometheus -n observability
kubectl edit deployment thanos-query -n observability
```

### Query Performance Issues

```bash
# For recent data (<7 days), query Prometheus directly via port-forward
kubectl port-forward -n observability svc/prometheus 9091:9090

# For historical data, use Thanos Query via port-forward
kubectl port-forward -n observability svc/thanos-query 9090:9090

# Enable downsampling
# Edit thanos/compactor.yaml to enable compaction
# Downsampled queries are much faster for long time ranges
```

## Performance Tuning

### Adjust Scrape Interval

Edit `prometheus/configmap.yaml`:

```yaml
global:
  scrape_interval: 30s  # Increase from 15s to reduce load
```

### Adjust Retention

For less storage usage:

```yaml
# prometheus/deployment.yaml
--storage.tsdb.retention.time=5d  # Reduce from 7d

# thanos/compactor.yaml
--retention.resolution-raw=15d     # Reduce from 30d
--retention.resolution-5m=60d      # Reduce from 90d
--retention.resolution-1h=180d     # Reduce from 365d
```

### Resource Limits

Current limits are conservative for Raspberry Pi:

```yaml
# Prometheus
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"

# Thanos components
resources:
  requests:
    memory: "128-256Mi"
    cpu: "100-200m"
  limits:
    memory: "512Mi-1Gi"
    cpu: "500m-1000m"
```

## Integration with Grafana

### Add Prometheus Data Source in Grafana

1. Go to **Configuration → Data Sources → Add data source**
2. Select **Prometheus**
3. Configure:
   - **Name**: Thanos (or Prometheus)
   - **URL**: `http://thanos-query.observability.svc.cluster.local:9090`
   - **Access**: Server (default)
4. Click **Save & Test**

### Recommended Dashboards

Import these dashboards from grafana.com:
- **Kubernetes Cluster Monitoring** (Dashboard ID: 315)
- **Kubernetes Pods** (Dashboard ID: 747)
- **Node Exporter Full** (Dashboard ID: 1860)
- **Thanos Overview** (Dashboard ID: 11752)

### Query Tips in Grafana

Grafana will automatically query Thanos, which provides:
- Fast queries for recent data (from Prometheus)
- Seamless access to historical data (from Garage)
- Automatic downsampling for long time ranges

## Security Best Practices

1. **Change Garage credentials** in `prometheus/garage-secret.yaml`
2. **Use NetworkPolicies** to restrict access to Prometheus/Thanos
3. **Enable TLS** for ingress (cert-manager + Let's Encrypt)
4. **Limit RBAC** to minimum required permissions
5. **Encrypt** Garage bucket (server-side encryption)
6. **Regular updates** of Prometheus and Thanos versions

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes components from Kubernetes but does NOT delete:
- Data at `/mnt/k8s-pvc/prometheus` on master node
- Data in Garage bucket `thanos`

To fully clean up:

```bash
# Remove local data
sudo rm -rf /mnt/k8s-pvc/prometheus

# Remove Garage bucket
garage bucket delete --yes thanos
```

## Cost Analysis

### Storage Usage Estimate

For a small cluster (10 pods, 100 metrics/pod, 15s scrape interval):

**Prometheus (7 days local)**:
- ~5GB for 7 days
- Well within 20Gi limit

**Garage (long-term)**:
- Raw (30 days): ~20GB
- 5m downsampled (90 days): ~6GB
- 1h downsampled (365 days): ~2GB
- **Total**: ~28GB for 1 year

Your Garage storage has plenty of space available for many years of metrics!

## Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Thanos Documentation](https://thanos.io/tip/thanos/getting-started.md/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Thanos Architecture](https://thanos.io/tip/thanos/design.md/)
- [Garage Documentation](https://garagehq.deuxfleurs.fr/)

## Version Information

- **Prometheus**: v2.54.1
- **Thanos**: v0.36.1
- **Local Storage**: 20Gi SSD at /mnt/k8s-pvc/prometheus (7 days)
- **Object Storage**: Garage bucket 'thanos' (1 year+)
- **Access**: Internal service endpoints + port-forward for debugging

## Next Steps

1. ✅ Prometheus + Thanos installed with Garage storage
2. ⬜ **Install Grafana** for visualization (recommended next step)
3. ⬜ Configure Grafana to use Thanos Query as data source
4. ⬜ Import recommended Grafana dashboards
5. ⬜ Set up Alertmanager for alerts
6. ⬜ Add custom scrape configs for your applications
7. ⬜ Configure alert rules
8. ⬜ Add node-exporter for detailed node metrics

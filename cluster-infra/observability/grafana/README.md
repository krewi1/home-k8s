# Grafana - Observability Dashboard

Grafana is an open-source platform for monitoring and observability. This deployment is pre-configured with datasources for Prometheus (via Thanos Query) and Loki, plus several useful Kubernetes dashboards.

## Current Setup

**Deployment:** Helm chart (grafana/grafana)
**Namespace:** observability
**Datasources:**
- Prometheus (via Thanos Query) - Metrics
- Loki - Logs

**Pre-installed Dashboards:**
- Kubernetes Cluster Monitoring
- Kubernetes Pods
- Node Exporter Full
- Loki Logs Dashboard

**Storage:** 5Gi persistent volume for dashboards and settings
**Access:** http://grafana.home (via nginx ingress) or port-forward

## Installation

### Prerequisites

1. **Helm 3** installed
2. **Prometheus/Thanos** installed and running
3. **Loki** installed and running
4. **kubectl** configured

### Deploy Grafana

```bash
# Make the script executable
chmod +x install.sh

# Run installation
./install.sh
```

The installation will:
1. Check prerequisites (kubectl, helm, datasources)
2. Add Grafana Helm repository
3. Install Grafana with custom values
4. Display admin credentials
5. Show access instructions

## Access Grafana

### Via Ingress (Recommended)

Grafana is exposed at **http://grafana.home** via nginx ingress.

Add to your `/etc/hosts` (or configure DNS):
```
<your-node-ip> grafana.home
```

Then open browser:
```
http://grafana.home
```

### Via Port Forward (Alternative)

```bash
# Forward Grafana service to localhost
kubectl port-forward -n observability svc/grafana 3000:80

# Open browser
open http://localhost:3000
```

### Default Credentials

- **Username:** `admin`
- **Password:** Check installation output or run:
  ```bash
  kubectl get secret --namespace observability grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
  ```

## Using Grafana

### Explore Logs with Loki

1. Go to **Explore** (compass icon in sidebar)
2. Select **Loki** from datasource dropdown
3. Try these LogQL queries:

```logql
# All logs from default namespace
{namespace="default"}

# Logs from specific pod
{pod="your-pod-name"}

# Search for errors
{namespace="default"} |= "error"

# Count errors by pod
sum(rate({namespace="default"} |= "error" [5m])) by (pod)
```

### Query Metrics with Prometheus

1. Go to **Explore**
2. Select **Prometheus** from datasource dropdown
3. Try these PromQL queries:

```promql
# Check what's up
up

# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{pod!=""}[5m])) by (pod)

# Memory usage by pod
sum(container_memory_working_set_bytes{pod!=""}) by (pod)

# Pod count by namespace
count(kube_pod_info) by (namespace)
```

### Browse Pre-installed Dashboards

1. Go to **Dashboards** (four squares icon in sidebar)
2. Click **Browse**
3. Select a dashboard:
   - **Kubernetes Cluster Monitoring** - Overall cluster health
   - **Kubernetes Pods** - Detailed pod metrics
   - **Node Exporter Full** - Node-level metrics
   - **Loki Logs** - Log analytics dashboard

### Create Your Own Dashboard

1. Go to **Dashboards** → **New** → **New Dashboard**
2. Click **Add visualization**
3. Select datasource (Prometheus or Loki)
4. Write your query
5. Choose visualization type (Graph, Table, Stat, etc.)
6. Click **Apply** and **Save**

## Configuration

### Datasources

Datasources are pre-configured in `values.yaml`:

```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      # Prometheus via Thanos Query
      - name: Prometheus
        type: prometheus
        url: http://thanos-query.observability.svc.cluster.local:9090
        isDefault: true

      # Loki for logs
      - name: Loki
        type: loki
        url: http://loki-gateway.observability.svc.cluster.local:80
```

### Add More Datasources

Edit `values.yaml` and add to the `datasources` section:

```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      # ... existing datasources ...

      # Add a new datasource
      - name: MyDatabase
        type: postgres
        url: postgres.default.svc.cluster.local:5432
        database: mydb
        user: grafana
        secureJsonData:
          password: mypassword
```

Apply changes:
```bash
helm upgrade grafana grafana/grafana -n observability -f values.yaml
```

### Import Additional Dashboards

You can import dashboards from [grafana.com/dashboards](https://grafana.com/grafana/dashboards):

**Via UI:**
1. Go to **Dashboards** → **New** → **Import**
2. Enter dashboard ID (e.g., `315` for K8s Cluster)
3. Select datasource
4. Click **Import**

**Via values.yaml:**
```yaml
dashboards:
  default:
    my-dashboard:
      gnetId: 12345  # Dashboard ID from grafana.com
      revision: 1
      datasource: Prometheus
```

### Popular Kubernetes Dashboards

- **315** - Kubernetes Cluster Monitoring (Global)
- **747** - Kubernetes Pods
- **1860** - Node Exporter Full
- **6417** - Kubernetes Deployment Statefulset Daemonset Metrics
- **13639** - Loki Dashboard Quick Search
- **7249** - Kubernetes Cluster (Prometheus)
- **11074** - Node Exporter for Prometheus Dashboard

## Monitoring

### Check Status

```bash
# Helm release status
helm status grafana -n observability

# Pod status
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

# Service status
kubectl get svc -n observability -l app.kubernetes.io/name=grafana

# PVC usage
kubectl get pvc -n observability -l app.kubernetes.io/name=grafana
```

### View Logs

```bash
# Real-time logs
kubectl logs -n observability -f -l app.kubernetes.io/name=grafana

# Last 100 lines
kubectl logs -n observability -l app.kubernetes.io/name=grafana --tail=100
```

## Troubleshooting

### Cannot Access Grafana

```bash
# Check if pod is running
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

# Check pod logs for errors
kubectl logs -n observability -l app.kubernetes.io/name=grafana

# Verify port-forward is active
# Should show: Forwarding from 127.0.0.1:3000 -> 3000
```

### Datasource Connection Failed

**For Prometheus/Thanos:**
```bash
# Test connection from Grafana pod
kubectl exec -n observability -l app.kubernetes.io/name=grafana -- \
  curl -s http://thanos-query.observability.svc.cluster.local:9090/-/healthy

# Should return: Thanos is Healthy.
```

**For Loki:**
```bash
# Test connection from Grafana pod
kubectl exec -n observability -l app.kubernetes.io/name=grafana -- \
  curl -s http://loki-gateway.observability.svc.cluster.local:80/ready

# Should return: ready
```

### Forgot Admin Password

```bash
# Retrieve password from secret
kubectl get secret --namespace observability grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Or reset by reinstalling
./uninstall.sh
./install.sh
```

### Dashboard Not Loading

1. Check datasource is configured correctly
2. Go to **Configuration** → **Data Sources**
3. Click on datasource → **Save & Test**
4. Should show green "Data source is working"

### High Memory Usage

If Grafana is consuming too much memory:

1. Edit `values.yaml`:
   ```yaml
   resources:
     limits:
       memory: 512Mi  # Reduce from 1Gi
   ```

2. Upgrade:
   ```bash
   helm upgrade grafana grafana/grafana -n observability -f values.yaml
   ```

## Backup & Restore

### Backup Strategy

**1. Export Dashboards**

Via UI:
- Go to **Dashboard** → **Settings** → **JSON Model**
- Copy the JSON
- Save to file

Via API:
```bash
# Get dashboard UID
kubectl port-forward -n observability svc/grafana 3000:80 &
curl -u admin:password http://localhost:3000/api/search | jq

# Export dashboard
curl -u admin:password \
  http://localhost:3000/api/dashboards/uid/<dashboard-uid> \
  > dashboard-backup.json
```

**2. Backup Grafana Database (PVC)**

```bash
# Backup entire PVC data
kubectl exec -n observability -l app.kubernetes.io/name=grafana -- \
  tar czf - /var/lib/grafana \
  > grafana-backup.tar.gz
```

**3. Backup Helm Values**

```bash
# Backup values
cp values.yaml values.yaml.backup

# Export current Helm values
helm get values grafana -n observability > grafana-values-backup.yaml
```

### Restore

**Restore Dashboards:**
1. Go to **Dashboards** → **New** → **Import**
2. Paste JSON or upload file
3. Click **Load** → **Import**

**Restore from PVC backup:**
```bash
# Copy backup into pod
kubectl cp grafana-backup.tar.gz \
  observability/<grafana-pod-name>:/tmp/

# Extract
kubectl exec -n observability <grafana-pod-name> -- \
  tar xzf /tmp/grafana-backup.tar.gz -C /
```

## Upgrade Grafana

```bash
# Update Helm repo
helm repo update grafana

# Upgrade to latest version
helm upgrade grafana grafana/grafana \
  --namespace observability \
  --values values.yaml \
  --wait

# Or upgrade to specific version
helm upgrade grafana grafana/grafana \
  --namespace observability \
  --values values.yaml \
  --version 7.0.0 \
  --wait
```

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes Grafana but preserves the PVC with your dashboards and settings.

To fully clean up:
```bash
# Remove PVC (WARNING: deletes all dashboards)
kubectl delete pvc -n observability -l app.kubernetes.io/name=grafana
```

## Customization

### Change Admin Password

1. Edit `values.yaml`:
   ```yaml
   adminPassword: "my-secure-password"
   ```

2. Upgrade:
   ```bash
   helm upgrade grafana grafana/grafana -n observability -f values.yaml
   ```

### Enable Plugins

1. Edit `values.yaml`:
   ```yaml
   plugins:
     - grafana-piechart-panel
     - grafana-clock-panel
     - grafana-worldmap-panel
   ```

2. Upgrade:
   ```bash
   helm upgrade grafana grafana/grafana -n observability -f values.yaml
   ```

### Enable Anonymous Access

For public dashboards without login:

1. Edit `values.yaml`:
   ```yaml
   env:
     GF_AUTH_ANONYMOUS_ENABLED: "true"
     GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
   ```

2. Upgrade:
   ```bash
   helm upgrade grafana grafana/grafana -n observability -f values.yaml
   ```

## Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL Basics](https://grafana.com/docs/loki/latest/logql/)

## Version Information

- **Grafana Helm Chart**: Latest (from Grafana Helm repository)
- **Datasources**: Prometheus (Thanos Query) + Loki
- **Storage**: 5Gi persistent volume
- **Access**: Port-forward to localhost:3000

## Next Steps

1. ✅ Grafana installed and configured
2. ✅ Datasources configured (Prometheus + Loki)
3. ✅ Pre-installed dashboards available
4. ⬜ Customize dashboards for your workloads
5. ⬜ Set up alerting rules
6. ⬜ Create custom dashboards
7. ⬜ Configure alert notifications (Slack, email, etc.)

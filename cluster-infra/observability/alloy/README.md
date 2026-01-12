# Grafana Alloy - Log Collection

Grafana Alloy is an OpenTelemetry Collector distribution with built-in Prometheus pipelines. This deployment uses Alloy as a DaemonSet to collect logs from all Kubernetes pods and send them to Loki.

## Current Setup

**Deployment:** Helm chart (DaemonSet mode)
**Purpose:** Collect logs from all Kubernetes pods
**Destination:** Loki (loki-gateway.observability)
**Namespace:** observability
**Access:** DaemonSet (runs on every node)

## Architecture

```
Kubernetes Pods (all namespaces)
    ↓ (stdout/stderr → /var/log/pods/)
Alloy DaemonSet (one pod per node)
    ├─ Discovers pods via Kubernetes API
    ├─ Tails log files from /var/log/pods/
    ├─ Parses containerd/docker format
    ├─ Adds labels (namespace, pod, container, etc.)
    └─ Sends to Loki
         ↓
Loki Gateway
    ↓
Loki (storage)
    ↓
Grafana (visualization)
```

## Features

- **Automatic Pod Discovery**: Discovers all pods on the node via Kubernetes API
- **Label Extraction**: Automatically adds useful labels:
  - `namespace`: Kubernetes namespace
  - `pod`: Pod name
  - `container`: Container name
  - `app`: App label (from `app.kubernetes.io/name`)
  - `job`: Namespace/container combination
  - `cluster`: Static cluster name
  - `stream`: stdout/stderr
- **Runtime Detection**: Automatically detects and parses containerd and docker logs
- **Node-scoped**: Each Alloy instance only processes pods on its own node (reduces memory usage)

## Installation

### Prerequisites

1. **Helm 3** installed
2. **Loki** installed and running
3. **kubectl** configured

### Deploy Alloy

```bash
# Make the script executable
chmod +x install.sh

# Run installation
./install.sh
```

The installation will:
1. Check prerequisites (kubectl, helm, Loki)
2. Add Grafana Helm repository
3. Create Alloy configuration ConfigMap
4. Install Alloy as DaemonSet via Helm
5. Wait for all pods to be ready

## Manual Setup Steps

If you prefer manual installation:

### 1. Create ConfigMap

```bash
kubectl apply -f configmap.yaml
```

### 2. Install via Helm

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace observability

# Install Alloy
helm install alloy grafana/alloy \
  --namespace observability \
  --values values.yaml \
  --set alloy.configMap.name=alloy-config \
  --wait
```

## Configuration

### Alloy Configuration (configmap.yaml)

The Alloy configuration is written in Alloy's configuration language and stored in a Kubernetes ConfigMap. The configuration includes:

1. **Pod Discovery**: Uses `discovery.kubernetes` to find all pods on the node
2. **Relabeling**: Extracts Kubernetes metadata into log labels
3. **Log Tailing**: Uses `loki.source.kubernetes` to read pod logs
4. **Processing**: Parses containerd/docker formats and adds labels
5. **Writing**: Sends logs to Loki via `loki.write`

### Helm Values (values.yaml)

Key configuration options:

```yaml
alloy:
  controller:
    type: 'daemonset'  # Run on every node
  mounts:
    varlog: true  # Mount /var/log for reading pod logs
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### Customizing the Configuration

To modify the Alloy configuration:

1. Edit `configmap.yaml` (the Alloy config is in the `data.config.alloy` field)
2. Apply changes:
   ```bash
   kubectl apply -f configmap.yaml
   ```
3. Restart Alloy pods:
   ```bash
   kubectl rollout restart daemonset/alloy -n observability
   ```

Or upgrade via Helm:
```bash
kubectl apply -f configmap.yaml
helm upgrade alloy grafana/alloy -n observability -f values.yaml --set alloy.configMap.name=alloy-config
```

## Monitoring

### Check Status

```bash
# View all Alloy pods (one per node)
kubectl get pods -n observability -l app.kubernetes.io/name=alloy

# Check DaemonSet status
kubectl get daemonset -n observability -l app.kubernetes.io/name=alloy

# View Helm release
helm status alloy -n observability
```

### View Logs

```bash
# View logs from all Alloy pods
kubectl logs -n observability -l app.kubernetes.io/name=alloy -f

# View logs from specific pod
kubectl logs -n observability <alloy-pod-name> -f

# Check if logs are being sent to Loki
kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep "loki.write"
```

### Verify Log Collection

1. **Check Alloy is discovering pods:**
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep "discovery.kubernetes"
   ```

2. **Check Alloy is sending to Loki:**
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep "loki.write"
   ```

3. **Query logs in Grafana:**
   - Go to Grafana → Explore
   - Select Loki data source
   - Query: `{namespace="default"}`
   - You should see logs from pods in the default namespace

## Troubleshooting

### Pods Not Starting

```bash
# Check events
kubectl describe daemonset -n observability alloy

# Common issues:
# 1. /var/log not mounted - check values.yaml mounts configuration
# 2. Permission denied - check security context in values.yaml
# 3. ConfigMap not found - ensure configmap.yaml was applied
```

### No Logs Appearing in Loki

```bash
# Check Alloy logs for errors
kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep -i error

# Common issues:
# 1. Cannot connect to Loki - check Loki is running
kubectl get pods -n observability -l app.kubernetes.io/name=loki

# 2. Wrong Loki URL - check configmap.yaml loki.write endpoint
kubectl get configmap alloy-config -n observability -o yaml | grep "url ="

# 3. No pods discovered - check RBAC permissions
kubectl get clusterrole alloy -o yaml
```

### Alloy Consuming Too Much Memory

If Alloy pods are using too much memory:

1. **Reduce resource limits** in `values.yaml`:
   ```yaml
   resources:
     limits:
       memory: 256Mi  # Reduce from 512Mi
   ```

2. **Limit discovery scope** in `config.alloy`:
   - Already limited to pods on the same node
   - Can further filter by namespace if needed

3. **Upgrade and restart:**
   ```bash
   helm upgrade alloy grafana/alloy -n observability -f values.yaml
   ```

## Label Reference

Logs collected by Alloy include these labels:

| Label | Source | Example |
|-------|--------|---------|
| `cluster` | Static | `home-k8s` |
| `namespace` | Kubernetes | `default` |
| `pod` | Kubernetes | `nginx-deployment-abc123` |
| `container` | Kubernetes | `nginx` |
| `app` | Kubernetes label | `nginx` |
| `job` | Namespace/Container | `default/nginx` |
| `stream` | Log stream | `stdout` or `stderr` |

Use these labels in LogQL queries:

```logql
# All logs from namespace
{namespace="default"}

# Logs from specific app
{app="nginx"}

# Only stderr logs
{stream="stderr"}

# Logs from specific pod
{pod="nginx-deployment-abc123"}

# Combine labels
{namespace="default", app="nginx", stream="stderr"}
```

## Backup & Restore

### Backup Strategy

**Configuration Only** - No data to backup since Alloy doesn't store logs

```bash
# Backup Helm values
cp values.yaml values.yaml.backup

# Backup Alloy config
cp configmap.yaml configmap.yaml.backup

# Export Helm release values
helm get values alloy -n observability > alloy-values-backup.yaml
```

### Restore

```bash
# Restore from backup
./install.sh
```

## Upgrade Alloy

```bash
# Update Helm repo
helm repo update grafana

# Upgrade to latest version
helm upgrade alloy grafana/alloy \
  --namespace observability \
  --values values.yaml \
  --set alloy.configMap.name=alloy-config \
  --wait
```

## Uninstallation

```bash
./uninstall.sh
```

**Note:** This removes Alloy and stops log collection. No data is lost since logs are stored in Loki.

To resume log collection:
```bash
./install.sh
```

## Performance Characteristics

On a Raspberry Pi cluster:

- **CPU Usage**: ~50-100m per node (depending on pod count)
- **Memory Usage**: ~100-200Mi per node
- **Network**: Minimal (logs compressed before sending to Loki)
- **Disk I/O**: Read-only access to /var/log

## Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Alloy Configuration Syntax](https://grafana.com/docs/alloy/latest/concepts/configuration-syntax/)
- [Alloy Components Reference](https://grafana.com/docs/alloy/latest/reference/components/)
- [Loki Integration](https://grafana.com/docs/alloy/latest/reference/components/loki/)

## Version Information

- **Alloy Helm Chart**: Latest (from Grafana Helm repository)
- **Deployment Mode**: DaemonSet
- **Log Destination**: Loki (loki-gateway.observability)
- **Access**: Runs on all nodes

## Next Steps

1. ✅ Alloy installed and collecting logs
2. ⬜ Verify logs appearing in Grafana
3. ⬜ Create Grafana dashboards for log visualization
4. ⬜ Set up log-based alerts
5. ⬜ Configure log filtering/sampling if needed

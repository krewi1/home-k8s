# K8s Infrastructure Services

This directory contains Kubernetes manifests and configurations for deploying essential infrastructure and supporting services to the cluster.

## Overview

These services provide observability, storage, serverless capabilities, and other foundational features needed for running applications on the cluster.

## Services

### External Infrastructure

#### DNS Server (Raspberry Pi 4)
**Purpose:** Internal DNS resolution for .home domain

**Directory:** `dns-config/`

- Resolves all `*.home` domains to nginx server
- Provides DNS for all cluster services
- Uses dnsmasq for lightweight DNS serving
- Integrates with upstream DNS for external queries
- Automatic wildcard resolution (no manual DNS entries needed)

**Key Features:**
- Wildcard DNS: `*.home` → nginx IP
- Static entries for cluster nodes
- DNS caching for performance
- Upstream forwarding for external domains

**Example Resolutions:**
- `grafana.home` → nginx → Kourier → Grafana
- `prometheus.home` → nginx → Kourier → Prometheus
- `hello.home` → nginx → Kourier → Knative service

**Setup:** See [dns-config/README.md](./dns-config/README.md) for complete installation and configuration guide.

#### nginx (Raspberry Pi 4)
**Purpose:** External reverse proxy and ingress gateway

**Directory:** `nginx-config/`

- Single entry point for all external traffic
- SSL/TLS termination
- Routes traffic to Kourier NodePort in the cluster
- Load balances across all K8s nodes
- Works with DNS server for seamless service access

**Key Configuration:**
- Proxies to Kourier NodePort (30080/30443)
- Upstream pool includes all K8s nodes
- Proper headers for Knative routing
- WebSocket support
- Health checks and failover

**Setup:** See [nginx-config/README.md](./nginx-config/README.md) for complete installation and configuration guide.

### Observability Stack

#### Prometheus
**Purpose:** Metrics collection and monitoring

**Directory:** `observability/prometheus/`

- Collects metrics from all cluster nodes and workloads
- Provides alerting capabilities
- Stores time-series metrics data
- Web UI for querying metrics

**Key Components:**
- Prometheus Server
- Node Exporter (on each node)
- kube-state-metrics
- AlertManager

**Access:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

#### Grafana Alloy
**Purpose:** Telemetry data collection and forwarding

**Directory:** `observability/alloy/`

- OpenTelemetry-compatible collector
- Processes and forwards telemetry data
- Supports metrics, logs, and traces
- Lightweight and efficient for ARM devices

#### Loki
**Purpose:** Log aggregation and querying

**Directory:** `observability/loki/`

- Aggregates logs from all pods and nodes
- Integrates with Grafana for log visualization
- Efficient storage using object storage (MinIO)
- Label-based log indexing

**Components:**
- Loki Server
- Promtail (log collector on each node)

**Access:**
```bash
kubectl port-forward -n monitoring svc/loki 3100:3100
```

#### Grafana
**Purpose:** Visualization and dashboards

**Directory:** `observability/grafana/`

- Unified dashboard for metrics and logs
- Pre-configured dashboards for Kubernetes
- Custom dashboard support
- Integrates with Prometheus and Loki

**Access:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### Storage

#### MinIO
**Purpose:** S3-compatible object storage

**Directory:** `storage/minio/`

- Distributed object storage
- S3-compatible API
- Used by Loki for log storage
- General purpose object storage for applications

**Features:**
- Multi-tenant support
- Bucket policies and versioning
- Web-based management console
- Distributed mode across worker nodes

**Access:**
```bash
kubectl port-forward -n storage svc/minio-console 9001:9001
```

**Default Credentials:** (Change after deployment)
- Username: `admin`
- Password: `minio123`

### Serverless

#### Knative with Kourier
**Purpose:** Serverless workload platform with lightweight ingress

**Directory:** `serverless/knative/`

- Run serverless containers
- Auto-scaling (including scale-to-zero)
- Event-driven architecture support
- Request-based routing with Kourier ingress

**Components:**
- **Knative Serving**: Deploy and manage serverless workloads
- **Knative Eventing**: Event-driven application support
- **Kourier**: Lightweight ingress controller for Knative
  - Exposes services via NodePort
  - Designed specifically for Knative
  - Much lighter than traditional ingress controllers

**Kourier NodePort Configuration:**

Kourier is configured to expose via NodePort for external access through nginx:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kourier
  namespace: knative-serving
spec:
  type: NodePort
  ports:
  - name: http2
    port: 80
    targetPort: 8080
    nodePort: 30080  # Accessible on all nodes
  - name: https
    port: 443
    targetPort: 8443
    nodePort: 30443  # Accessible on all nodes
  selector:
    app: 3scale-kourier-gateway
```

**Usage Example:**
```bash
# Deploy a Knative service
kn service create hello \
  --image gcr.io/knative-samples/helloworld-go \
  --port 8080 \
  --env TARGET=World

# Get the service URL
kn service describe hello -o url

# The service will be accessible via:
# http://<nginx-pi4-ip> with Host header set to the Knative service URL
```

**Integration with External nginx:**

After deploying Knative, configure your nginx on Pi 4:

```bash
# Get the NodePort
kubectl get svc -n knative-serving kourier

# Configure nginx to proxy to NodePort 30080/30443
# See nginx-config/README.md for detailed nginx configuration guide
# Use nginx-config/kourier-proxy.conf as a ready-to-use configuration
```

## Directory Structure

```
k8s-infrastructure/
├── dns-config/            # DNS server configuration (for Pi 4)
│   ├── README.md          # Setup guide
│   ├── dnsmasq.conf       # Main dnsmasq config
│   ├── home-domain.conf   # .home domain config
│   ├── hosts.home         # Static host entries
│   └── setup-dns.sh       # Automated setup script
├── nginx-config/          # External nginx configuration (for Pi 4)
│   ├── README.md
│   └── kourier-proxy.conf
├── observability/
│   ├── prometheus/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── alloy/
│   │   ├── daemonset.yaml
│   │   └── configmap.yaml
│   ├── loki/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── grafana/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── storage/
│   └── minio/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── pvc.yaml
│       └── secret.yaml
└── serverless/
    └── knative/
        ├── serving.yaml
        └── eventing.yaml
```

## Deployment Order

Deploy services in the following order to satisfy dependencies:

### External Infrastructure (On Pi 4)

Deploy these first on the Raspberry Pi 4 **before** deploying Kubernetes services:

1. **DNS Server** - Provides name resolution for all services
   ```bash
   cd dns-config
   sudo ./setup-dns.sh
   # Or manually:
   # sudo cp dnsmasq.conf /etc/dnsmasq.conf
   # sudo cp home-domain.conf /etc/dnsmasq.d/
   # sudo cp hosts.home /etc/hosts.home
   # sudo systemctl restart dnsmasq
   ```

2. **nginx** - External reverse proxy
   ```bash
   # After Knative/Kourier is deployed to get NodePort
   cd nginx-config
   # Update kourier-proxy.conf with your IPs
   sudo cp kourier-proxy.conf /etc/nginx/sites-available/k8s-ingress
   sudo ln -s /etc/nginx/sites-available/k8s-ingress /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

### Kubernetes Services

Deploy these to the Kubernetes cluster:

1. **Storage (MinIO)** - Required by other services
   ```bash
   kubectl apply -f storage/minio/
   ```

2. **Observability - Prometheus**
   ```bash
   kubectl apply -f observability/prometheus/
   ```

3. **Observability - Loki**
   ```bash
   kubectl apply -f observability/loki/
   ```

4. **Observability - Alloy**
   ```bash
   kubectl apply -f observability/alloy/
   ```

5. **Observability - Grafana**
   ```bash
   kubectl apply -f observability/grafana/
   ```

6. **Knative Serving & Eventing**
   ```bash
   kubectl apply -f serverless/knative/
   ```

### Quick Deployment Script

```bash
#!/bin/bash
# deploy-all.sh - Deploy all infrastructure services

kubectl create namespace monitoring
kubectl create namespace storage
kubectl create namespace knative-serving
kubectl create namespace knative-eventing

# Deploy in order
kubectl apply -f storage/minio/
sleep 30  # Wait for MinIO to be ready

kubectl apply -f observability/prometheus/
kubectl apply -f observability/loki/
kubectl apply -f observability/alloy/
kubectl apply -f observability/grafana/

kubectl apply -f serverless/knative/

echo "Deployment complete! Check status with:"
echo "kubectl get pods -A"
```

## Configuration

### Resource Limits

Since we're running on Raspberry Pi, resource limits are configured for ARM devices:

- **Prometheus:** 1GB RAM limit
- **Loki:** 512MB RAM limit
- **Grafana:** 512MB RAM limit
- **MinIO:** 1GB RAM limit per instance

### Persistent Storage

Services requiring persistent storage:
- **Prometheus:** 50GB for metrics retention
- **Loki:** Uses MinIO for log storage
- **MinIO:** 100GB per node
- **Grafana:** 10GB for dashboards and plugins

### Node Affinity

Configure node affinity to distribute services:
- Storage services prefer nodes with more disk space
- Observability services distributed across worker nodes
- Critical services avoid infrastructure node

## Access and Ingress

### Setting up Ingress

```yaml
# Example ingress for Grafana
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
spec:
  rules:
  - host: grafana.homelab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
```

### DNS Configuration

Add entries to your DNS server (running on Pi 4):
- `grafana.homelab.local` → nginx node IP
- `prometheus.homelab.local` → nginx node IP
- `minio.homelab.local` → nginx node IP

## Monitoring & Maintenance

### Health Checks

```bash
# Check all infrastructure pods
kubectl get pods -n monitoring
kubectl get pods -n storage
kubectl get pods -n knative-serving

# Check service endpoints
kubectl get svc -A | grep -E "monitoring|storage|knative"

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

### Backup Strategy

**Prometheus:**
```bash
# Snapshot current data
kubectl exec -n monitoring prometheus-0 -- promtool tsdb snapshot /prometheus
```

**Grafana:**
```bash
# Backup dashboards and config
kubectl exec -n monitoring grafana-0 -- tar czf /tmp/grafana-backup.tar.gz /var/lib/grafana
```

**MinIO:**
- Configure bucket replication
- Use `mc mirror` for backups

### Upgrades

Update services one at a time:
```bash
kubectl set image deployment/prometheus -n monitoring \
  prometheus=prom/prometheus:latest

kubectl rollout status deployment/prometheus -n monitoring
```

## Troubleshooting

### Prometheus Not Scraping Metrics
```bash
# Check service discovery
kubectl logs -n monitoring deployment/prometheus

# Verify service monitors
kubectl get servicemonitors -A
```

### Loki Storage Issues
```bash
# Check MinIO connectivity
kubectl logs -n monitoring deployment/loki

# Verify MinIO bucket exists
kubectl run -it --rm mc --image=minio/mc --restart=Never -- \
  mc ls myminio/loki-logs
```

### Knative Services Not Scaling
```bash
# Check autoscaler
kubectl logs -n knative-serving deployment/autoscaler

# Verify metrics are available
kubectl top pods -n <namespace>
```

## Performance Tuning

### For Raspberry Pi

1. **Reduce retention periods:**
   - Prometheus: 7 days instead of 15 days
   - Loki: 7 days retention

2. **Enable compression:**
   - Enable gzip compression in all services
   - Use efficient storage formats

3. **Limit concurrent queries:**
   - Configure query limits in Prometheus
   - Set max concurrent queries in Grafana

4. **Use ARM-optimized images:**
   - Always use `arm64` or multi-arch images
   - Test for ARM compatibility

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [MinIO Documentation](https://min.io/docs/)
- [Knative Documentation](https://knative.dev/docs/)

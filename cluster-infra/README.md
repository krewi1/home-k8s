# Cluster Infrastructure

This directory contains infrastructure components and configurations for the home K3s cluster running on Raspberry Pi nodes.

## Components

### Knative Serving

Serverless platform with Kourier ingress controller for deploying and managing containerized applications.

- **Directory**: `knative/`
- **Purpose**: Serverless application deployment, auto-scaling, traffic management
- **Base Domain**: `kn.home`
- **Documentation**: See [knative/README.md](knative/README.md)
- **Quick Install**: `cd knative && ./install.sh`

## Installation Order

For a fresh cluster, install components in this order:

1. **Knative Serving** - Serverless platform with Kourier ingress
   ```bash
   cd knative
   ./install.sh
   ```

## Directory Structure

```
cluster-infra/
├── README.md                    # This file
└── knative/                     # Knative Serving with Kourier
    ├── README.md                # Detailed documentation
    ├── install.sh               # Installation script
    ├── uninstall.sh             # Uninstallation script
    ├── config/                  # Configuration files
    │   └── custom-domain.yaml   # Domain configuration (kn.home)
    └── examples/                # Example applications
        ├── hello-service.yaml   # Simple hello world service
        └── autoscaling-service.yaml  # Autoscaling demo
```

## Cluster Information

- **Platform**: K3s on Raspberry Pi
- **Master Node**: Raspberry Pi 5 (with SSD for etcd)
- **Worker Nodes**: Raspberry Pi 4/5
- **Serverless**: Knative Serving with Kourier ingress
- **Domain**: `*.kn.home` for Knative services
- **Load Balancing**: NodePort (via Kourier gateway)
- **Storage**: Local path provisioner (K3s default)

## Common Tasks

### Check Component Status

```bash
# Knative Serving
kubectl get pods -n knative-serving
kubectl get pods -n kourier-system

# All Knative services
kubectl get ksvc -A
```

### View Services

```bash
# All Knative services
kubectl get ksvc -A

# With details
kubectl get ksvc -A -o wide
```

### Access Applications

```bash
# Get Kourier NodePort
kubectl get svc -n kourier-system kourier

# Get node IP
kubectl get nodes -o wide

# Configure DNS (add to /etc/hosts)
echo "<node-ip> hello.default.kn.home" | sudo tee -a /etc/hosts

# Test with curl
curl http://hello.default.kn.home:<nodeport>

# Or with explicit Host header
curl -H "Host: hello.default.kn.home" http://<node-ip>:<nodeport>
```

## Maintenance

### Backup

Important configurations to backup:
- ConfigMaps in `knative-serving` namespace
- Custom domain configurations
- Application manifests

### Updates

Update components regularly:
```bash
# Check versions
kubectl get deployment -n knative-serving -o yaml | grep image:
kubectl get deployment -n kourier-system -o yaml | grep image:

# Update (see component README for specific instructions)
```

## Troubleshooting

### General Debug Commands

```bash
# Check all pods
kubectl get pods -A

# Check specific namespace
kubectl get pods -n <namespace>

# View logs
kubectl logs -n <namespace> <pod-name>

# Describe resource
kubectl describe pod -n <namespace> <pod-name>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Component-Specific

See individual component README files for detailed troubleshooting:
- Knative: [knative/README.md](knative/README.md#troubleshooting)

## Contributing

When adding new infrastructure components:

1. Create a new directory under `cluster-infra/`
2. Include a detailed README.md
3. Provide installation and uninstallation scripts
4. Add example configurations
5. Update this main README.md

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Knative Documentation](https://knative.dev/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

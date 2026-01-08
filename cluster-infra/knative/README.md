# Knative Serving with Kourier

Complete Knative Serving installation with Kourier as the ingress controller. Knative provides serverless capabilities on Kubernetes, enabling rapid deployment, automatic scaling (including scale-to-zero), and simplified application management.

## What's Included

- **Knative Serving**: Core serverless platform
- **Kourier**: Lightweight ingress controller built on Envoy proxy
- **Custom Domain**: Configured for `kn.home` base domain
- **NodePort Service**: Kourier exposed on all nodes for high availability

## Why Knative + Kourier?

- **Serverless on Kubernetes**: Deploy applications without managing infrastructure
- **Auto-scaling**: Scale to zero when idle, scale up based on traffic
- **Lightweight**: Minimal resource footprint compared to Istio
- **Simple**: No additional CRDs beyond Knative's own
- **Fast**: Built on Envoy proxy for high-performance traffic routing
- **Production-ready**: Used in production by many organizations

## Architecture

- **Knative Serving**: Manages application deployments, revisions, and routing
- **Kourier Gateway**: Envoy-based ingress handling external traffic
- **Services**: Your applications running as Knative Services (ksvc)
- **Domain**: All services accessible at `*.kn.home`

## Installation

### Prerequisites

- Kubernetes cluster (K3s in our case)
- kubectl configured to access your cluster

### Quick Install

```bash
# Run the installation script
./install.sh
```

### Manual Installation

```bash
# 1. Install Knative Serving CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.20.0/serving-crds.yaml

# 2. Install Knative Serving core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.20.0/serving-core.yaml

# 3. Install Kourier networking layer
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.20.0/kourier.yaml

# 4. Configure Knative to use Kourier
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# 5. Configure custom domain
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"kn.home":""}}'

# 6. Verify installation
kubectl get pods -n knative-serving
kubectl get pods -n kourier-system
kubectl get svc -n kourier-system kourier
```

## Configuration

### Expose Kourier Gateway

Kourier is automatically configured as a NodePort service, making it accessible on all cluster nodes:

```bash
# Check the kourier service (should show type: NodePort)
kubectl get svc -n kourier-system kourier

# Get the NodePort (typically 30000-32767 range)
kubectl get svc -n kourier-system kourier -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}'

# Access from any node in the cluster
curl -H "Host: hello.default.kn.home" http://<any-node-ip>:<nodeport>
```

The NodePort service ensures that:
- The same port is exposed on all nodes
- You can access services through any node's IP address
- Traffic is automatically routed to the Kourier gateway pods

### DNS Configuration

This installation uses `kn.home` as the base domain. Services will be accessible at:
- `<service-name>.<namespace>.kn.home`

For example:
- `hello.default.kn.home`
- `myapp.production.kn.home`

You'll need to configure DNS or use `/etc/hosts`:
```bash
# Add to /etc/hosts on your client machine
<node-ip> hello.default.kn.home
<node-ip> myapp.default.kn.home
```

Or set up wildcard DNS:
```
*.kn.home -> <node-ip>
```

## Usage

### Deploy a Sample Service

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  template:
    spec:
      containers:
        - image: gcr.io/knative-samples/helloworld-go
          ports:
            - containerPort: 8080
          env:
            - name: TARGET
              value: "Knative on K3s"
```

Apply and test:
```bash
kubectl apply -f hello-service.yaml

# Get the URL
kubectl get ksvc hello

# Test (replace with your node IP and port)
curl -H "Host: hello.default.kn.home" http://<node-ip>:<nodeport>

# Or with DNS configured:
curl http://hello.default.kn.home:<nodeport>
```

## Monitoring

```bash
# Check Kourier logs
kubectl logs -n kourier-system -l app=3scale-kourier-gateway -f

# Check Knative Serving controller logs
kubectl logs -n knative-serving -l app=controller -f

# Check all Knative resources
kubectl get ksvc -A
kubectl get revisions -A
kubectl get routes -A
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n knative-serving <pod-name>
kubectl logs -n knative-serving <pod-name>
```

### Service not accessible
```bash
# Check service status
kubectl get ksvc <service-name>

# Check route
kubectl get route <service-name>

# Check ingress
kubectl get ingress -n knative-serving

# Check Kourier gateway
kubectl get svc -n kourier-system kourier
```

### DNS resolution issues
```bash
# Check domain configuration (should show kn.home)
kubectl get configmap config-domain -n knative-serving -o yaml

# Test with explicit Host header
curl -H "Host: your-service.namespace.kn.home" http://<node-ip>:<nodeport>

# Verify DNS is resolving correctly
nslookup hello.default.kn.home
# Or check /etc/hosts
grep kn.home /etc/hosts
```

## Upgrading

```bash
# Upgrade Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v<NEW_VERSION>/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v<NEW_VERSION>/serving-core.yaml

# Upgrade Kourier
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v<NEW_VERSION>/kourier.yaml
```

## Uninstallation

```bash
./uninstall.sh

# Or manually:
kubectl delete -f https://github.com/knative/net-kourier/releases/download/knative-v1.20.0/kourier.yaml
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.20.0/serving-core.yaml
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.20.0/serving-crds.yaml
```

## Advanced Topics

- [NodePort Configuration](docs/nodeport-configuration.md) - Detailed guide on NodePort setup and load balancing

## References

- [Knative Documentation](https://knative.dev/docs/)
- [Kourier GitHub Repository](https://github.com/knative-extensions/net-kourier)
- [Knative Serving Installation](https://knative.dev/docs/install/yaml-install/serving/install-serving-with-yaml/)
- [Kourier Releases](https://github.com/knative-extensions/net-kourier/releases)

## Version Information

- **Knative Version**: v1.20.0
- **Kourier Version**: knative-v1.20.0 (October 2024)
- **Compatible Kubernetes**: 1.28+
- **Base Domain**: kn.home

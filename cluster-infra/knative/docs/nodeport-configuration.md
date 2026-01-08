# Kourier NodePort Configuration

Kourier is configured as a NodePort service to allow external access to Knative services from any node in the cluster.

## What is NodePort?

NodePort is a Kubernetes service type that exposes a service on a static port on each node's IP. This means:
- The service is accessible on `<any-node-ip>:<nodeport>`
- The same port is used across all nodes
- Kubernetes automatically routes traffic to the service pods

## Default Configuration

By default, the installation script configures Kourier as NodePort with:
- **Service Type**: NodePort
- **Port**: Auto-assigned by Kubernetes (typically 30000-32767 range)
- **Protocol**: HTTP on port 80 → NodePort
- **Availability**: All cluster nodes

## Check Current Configuration

```bash
# View Kourier service details
kubectl get svc -n kourier-system kourier -o yaml

# Get just the NodePort
kubectl get svc -n kourier-system kourier \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}'

# Example output: 31234
```

## Access Patterns

### Via Any Node

```bash
# Get node IPs
kubectl get nodes -o wide

# Access via master node
curl -H "Host: hello.default.kn.home" http://192.168.1.100:31234

# Access via worker node
curl -H "Host: hello.default.kn.home" http://192.168.1.101:31234

# Both work identically!
```

### With DNS

If you have DNS configured for `*.kn.home`:

```bash
# Direct access with port
curl http://hello.default.kn.home:31234

# Or configure DNS to point to any node
echo "192.168.1.100 *.kn.home" >> /etc/hosts
```

## Custom NodePort (Optional)

If you want a specific port instead of auto-assigned:

```bash
# Patch the service with a specific NodePort (e.g., 30080)
kubectl patch service kourier \
  --namespace kourier-system \
  --type merge \
  --patch '{
    "spec": {
      "ports": [{
        "name": "http2",
        "port": 80,
        "protocol": "TCP",
        "targetPort": 8080,
        "nodePort": 30080
      }]
    }
  }'
```

**Note**: Custom NodePorts must be in the range 30000-32767 (default Kubernetes range).

## Load Balancing Options

Since Kourier is exposed via NodePort, you can add external load balancing:

### Option 1: External Nginx/HAProxy

```nginx
upstream knative_backend {
    server 192.168.1.100:31234;  # master
    server 192.168.1.101:31234;  # worker-1
    server 192.168.1.102:31234;  # worker-2
}

server {
    listen 80;
    server_name *.kn.home;

    location / {
        proxy_pass http://knative_backend;
        proxy_set_header Host $host;
    }
}
```

### Option 2: DNS Round-Robin

Configure multiple A records for `*.kn.home`:
```
*.kn.home.  300  IN  A  192.168.1.100
*.kn.home.  300  IN  A  192.168.1.101
*.kn.home.  300  IN  A  192.168.1.102
```

### Option 3: MetalLB (for LoadBalancer type)

If you prefer LoadBalancer type instead of NodePort, you can install MetalLB:

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.0/config/manifests/metallb-native.yaml

# Configure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF

# Change Kourier to LoadBalancer
kubectl patch service kourier \
  --namespace kourier-system \
  --type merge \
  --patch '{"spec":{"type":"LoadBalancer"}}'
```

## Troubleshooting

### Service not accessible from other nodes

```bash
# Check if service exists
kubectl get svc -n kourier-system kourier

# Verify service type is NodePort
kubectl get svc -n kourier-system kourier -o jsonpath='{.spec.type}'
# Should output: NodePort

# Check endpoints
kubectl get endpoints -n kourier-system kourier

# Verify pods are running
kubectl get pods -n kourier-system
```

### Port conflicts

If the auto-assigned NodePort conflicts with another service:

```bash
# List all NodePorts in use
kubectl get svc --all-namespaces -o json | \
  jq '.items[] | select(.spec.type=="NodePort") | {name:.metadata.name, namespace:.metadata.namespace, ports:.spec.ports}'

# Change to a different port
kubectl patch service kourier \
  --namespace kourier-system \
  --type merge \
  --patch '{"spec":{"ports":[{"name":"http2","nodePort":30081}]}}'
```

### Firewall issues

Ensure NodePort range is allowed through firewall:

```bash
# For Ubuntu/Debian with ufw
sudo ufw allow 30000:32767/tcp

# For RHEL/CentOS with firewalld
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

## Security Considerations

1. **Firewall**: Only expose NodePort range to trusted networks
2. **TLS**: Consider adding TLS termination at external load balancer
3. **Network Policies**: Use Kubernetes NetworkPolicies to restrict pod-to-pod traffic
4. **DDoS Protection**: Use external load balancer with rate limiting

## References

- [Kubernetes Service Types](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
- [NodePort Documentation](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
- [K3s Networking](https://docs.k3s.io/networking)

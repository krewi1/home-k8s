# nginx-ingress Controller

nginx-ingress controller for standard Kubernetes Ingress resources. Works alongside Kourier to handle regular (non-Knative) HTTP services.

## Purpose

- **Kourier**: Handles Knative Services (serverless workloads)
- **nginx-ingress**: Handles standard Kubernetes Deployments with Ingress resources

## Port Configuration

- **HTTP**: NodePort 32080 (accessible on all nodes)
- **HTTPS**: NodePort 32443 (accessible on all nodes)
- **Kourier**: Separate port for Knative services (typically 30080)
- **External Traffic Policy**: Cluster (allows traffic to any node)

## Installation

```bash
./install.sh
```

This will:
1. Install nginx-ingress controller v1.10.0
2. Configure as NodePort service
3. Expose HTTP on port 32080
4. Expose HTTPS on port 32443
5. Set externalTrafficPolicy to Cluster for load balancer compatibility

## Performance Optimization

For better performance on Raspberry Pi:

```bash
./optimize.sh
```

This applies optimizations for:
- Worker processes tuned for ARM
- Increased connection limits
- Better buffering for large files (MinIO)
- Reduced logging overhead
- Multiple replicas for load distribution

**See [PERFORMANCE.md](PERFORMANCE.md) for detailed tuning guide.**

## Usage

### Deploy Application with Ingress

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello
        image: gcr.io/google-samples/hello-app:1.0
        ports:
        - containerPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: hello-service
  namespace: default
spec:
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 8080

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: hello.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-service
            port:
              number: 80
```

Apply:
```bash
kubectl apply -f my-app.yaml
```

### Test the Ingress

```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Test with curl
curl -H "Host: hello.local" http://$NODE_IP:32080/

# Or add to /etc/hosts
echo "$NODE_IP hello.local" | sudo tee -a /etc/hosts

# Then access directly
curl http://hello.local:32080/
```

## Features

### Path-based Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-path
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### TLS/HTTPS Support

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

### Custom Annotations

```yaml
metadata:
  annotations:
    # SSL redirect
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"

    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"

    # Custom headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Custom-Header "value";
```

## Monitoring

```bash
# Check controller pods
kubectl get pods -n ingress-nginx

# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f

# Check service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# List all Ingress resources
kubectl get ingress -A

# Describe specific Ingress
kubectl describe ingress <ingress-name>
```

## Troubleshooting

### Ingress not working

```bash
# Check ingress status
kubectl describe ingress <ingress-name>

# Check nginx-ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Verify service endpoints
kubectl get endpoints <service-name>

# Test from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -H "Host: myapp.local" http://ingress-nginx-controller.ingress-nginx/
```

### 404 errors

```bash
# Verify IngressClass is set
kubectl get ingress <ingress-name> -o yaml | grep ingressClassName

# Check backend service exists
kubectl get svc <service-name>

# Verify paths match
kubectl describe ingress <ingress-name>
```

### Port conflicts

If port 32080 conflicts with another service:

```bash
# Edit install.sh and change HTTP_NODEPORT
# Or patch the service manually
kubectl patch service ingress-nginx-controller \
  --namespace ingress-nginx \
  --type merge \
  --patch '{"spec":{"ports":[{"name":"http","nodePort":32081}]}}'
```

## Comparison: nginx-ingress vs Kourier

| Feature | nginx-ingress | Kourier |
|---------|---------------|---------|
| **Use Case** | Standard apps | Serverless/Knative |
| **Resource** | Ingress | Knative Service |
| **Port** | 32080/32443 | Auto-assigned |
| **Auto-scaling** | Manual | Automatic |
| **Scale to Zero** | No | Yes |
| **Traffic Splitting** | Via annotations | Native |
| **Deployment Type** | Deployment + Service | Knative Service |

## When to Use nginx-ingress

✅ **Use nginx-ingress when:**
- Deploying standard Kubernetes Deployments
- Need traditional Ingress features
- Want precise control over routing
- Don't need auto-scaling
- Running stateful applications

✅ **Use Kourier (Knative) when:**
- Want serverless capabilities
- Need auto-scaling to zero
- Deploying microservices
- Want simplified deployment

## Examples

See `examples/` directory for:
- Simple HTTP Ingress
- TLS/HTTPS setup
- Path-based routing
- Multi-service routing
- Custom headers and CORS

## Uninstallation

```bash
./uninstall.sh
```

## References

- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Ingress API Reference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#ingress-v1-networking-k8s-io)
- [nginx-ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)

## External Traffic Policy

The nginx-ingress service is configured with `externalTrafficPolicy: Cluster`:

### Why Cluster Policy?

- **Cluster** (default in this setup):
  - ✅ Any node can receive and forward traffic
  - ✅ Works with external load balancers distributing to all nodes
  - ✅ No dropped connections
  - ⚠️ Source IP is NAT'd (shows as cluster IP)

- **Local** (upstream default):
  - ✅ Preserves source IP address
  - ❌ Only nodes with nginx-ingress pods can handle traffic
  - ❌ External load balancers sending to all nodes cause failures/retries
  - ❌ Poor performance with multi-node load balancing

**For setups with external load balancers (like nginx on HAProxy upstream), Cluster policy is required.**

To change the policy back to Local (if you don't use external LB):

```bash
kubectl patch service ingress-nginx-controller \
  --namespace ingress-nginx \
  --type merge \
  --patch '{"spec":{"externalTrafficPolicy":"Local"}}'
```

## Version Information

- **nginx-ingress Version**: v1.10.0
- **HTTP NodePort**: 32080
- **HTTPS NodePort**: 32443
- **External Traffic Policy**: Cluster

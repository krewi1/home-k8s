# nginx Configuration for K8s Cluster Ingress

This directory contains nginx configuration examples for the Raspberry Pi 4 running nginx that acts as the external reverse proxy to the Kubernetes cluster.

## Overview

The nginx server on the Raspberry Pi 4:
- Acts as the single entry point for all external traffic
- Handles SSL/TLS termination
- Routes traffic to both ingress controllers in the cluster:
  - **Kourier** (port 30080): Knative services on `*.kn.home` domain
  - **nginx-ingress** (port 38080): Standard Kubernetes Ingress on `*.home` domain
- Provides DNS resolution via integrated DNS server

## Architecture Flow

```
Internet → nginx (Pi 4) → Routes based on domain:
                         ├─ *.kn.home → Kourier NodePort (30080) → Knative Services
                         └─ *.home → nginx-ingress NodePort (38080) → Standard Services
```

## Configuration Files

### `kourier-proxy.conf`
Main configuration for proxying traffic to both ingress controllers.

- Defines two upstreams:
  - `kourier_cluster`: Kourier on port 30080 for Knative services
  - `nginx_ingress_cluster`: nginx-ingress on port 38080 for standard Ingress
- Two separate server blocks for clean routing:
  - Server block with `server_name *.kn.home` → proxies to Kourier
  - Server block with `server_name *.home` → proxies to nginx-ingress
- Separate access/error logs for each backend
- Configures HTTP/HTTPS proxying
- Sets proper headers for routing
- Includes health checks for nginx-ingress

### `ssl-config.conf`
SSL/TLS configuration snippet for securing connections.

### `upstream-healthcheck.conf`
Health check configuration for K8s nodes.

## Installation Instructions

### 1. Prerequisites

Ensure nginx is installed on the Raspberry Pi 4:

```bash
sudo apt update
sudo apt install nginx
```

### 2. Get NodePort Services

On your local machine with kubectl access:

```bash
# Get Kourier service details
kubectl get svc -n kourier-system kourier

# You should see something like:
# NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
# kourier   NodePort   10.43.123.45    <none>        80:30080/TCP     5m

# Get nginx-ingress service details
kubectl get svc -n ingress-nginx ingress-nginx-controller

# You should see something like:
# NAME                       TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
# ingress-nginx-controller   NodePort   10.43.234.56    <none>        80:38080/TCP,443:38443/TCP   5m

# Note the NodePorts:
# - Kourier: 30080 (HTTP)
# - nginx-ingress: 38080 (HTTP), 38443 (HTTPS)
```

### 3. Update Configuration

Edit `kourier-proxy.conf` and update:
- Replace `192.168.0.222`, `192.168.0.223`, etc. with your actual node IPs
- Verify NodePorts match: Kourier on 30080, nginx-ingress on 38080
- Domain routing is preconfigured:
  - `*.kn.home` → Kourier (Knative services)
  - `*.home` → nginx-ingress (standard services)

### 4. Deploy Configuration

```bash
# Copy configuration to nginx
sudo cp kourier-proxy.conf /etc/nginx/sites-available/k8s-ingress

# Create symbolic link
sudo ln -s /etc/nginx/sites-available/k8s-ingress /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### 5. DNS Configuration

Configure your DNS server (also on Pi 4) to point your domains to the nginx server IP:

```bash
# Example DNS records
*.apps.homelab.local    A    <nginx-pi4-ip>
grafana.homelab.local   A    <nginx-pi4-ip>
```

## Routing Behavior

The nginx proxy uses multiple `server` blocks with `server_name` directives for clean routing:

### Knative Services (via Kourier)
- **Server name**: `*.kn.home`
- **Backend**: Kourier on port 30080
- **Example**: `hello.example.kn.home` → routes to Kourier
- **Logs**: `/var/log/nginx/kourier-access.log`

### Standard Services (via nginx-ingress)
- **Server name**: `*.home`
- **Backend**: nginx-ingress on port 38080
- **Example**: `myapp.home`, `api.home` → routes to nginx-ingress
- **Logs**: `/var/log/nginx/nginx-ingress-access.log`

**Note**: `*.kn.home` is more specific than `*.home`, so nginx will match `hello.example.kn.home` to the Kourier server block first.

This allows you to:
- Run serverless Knative services on `*.kn.home` domains
- Run traditional Kubernetes services on `*.home` domains
- Use a single nginx entry point for all traffic
- Keep clear separation between serverless and traditional workloads
- Easily debug with separate log files per backend

## Testing

### Test nginx Connectivity

```bash
# Get nginx Pi 4 IP (if you don't know it)
NGINX_IP="<nginx-pi4-ip>"

# Test routing to nginx-ingress (*.home domain)
curl -H "Host: hello.home" http://$NGINX_IP

# Test routing to Kourier (*.kn.home domain)
curl -H "Host: hello.example.kn.home" http://$NGINX_IP
```

### Test Knative Service (via Kourier)

```bash
# Deploy a test Knative service
kn service create hello \
  --image gcr.io/knative-samples/helloworld-go \
  --env TARGET=World \
  --namespace example

# The service will be accessible at hello.example.kn.home
# Test via nginx proxy
curl -H "Host: hello.example.kn.home" http://<nginx-pi4-ip>
```

### Test Standard Service (via nginx-ingress)

```bash
# Deploy a standard app with Ingress
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
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
spec:
  ingressClassName: nginx
  rules:
  - host: hello.home
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-service
            port:
              number: 80
EOF

# Test via nginx proxy
curl -H "Host: hello.home" http://<nginx-pi4-ip>
```

## Load Balancing

The configuration includes all K8s nodes in the upstream pool:
- nginx load balances requests across all nodes
- If a node goes down, traffic automatically routes to healthy nodes
- NodePort services are accessible on all nodes in the cluster

## SSL/TLS Configuration

### Using Let's Encrypt

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d apps.homelab.local -d *.apps.homelab.local

# Certificates auto-renew
sudo certbot renew --dry-run
```

### Using Self-Signed Certificates

For local development:

```bash
# Generate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/homelab.key \
  -out /etc/ssl/certs/homelab.crt

# Update nginx config to use these certificates
```

## Monitoring

### nginx Status

```bash
# Check nginx status
sudo systemctl status nginx

# View access logs
sudo tail -f /var/log/nginx/access.log

# View error logs
sudo tail -f /var/log/nginx/error.log
```

### Backend Health

```bash
# Check if Kourier is responding (port 30080)
curl http://<master-ip>:30080 -v

# Check if nginx-ingress is responding (port 38080)
curl http://<master-ip>:38080 -v

# Test Kourier on all nodes
echo "Testing Kourier (port 30080):"
for ip in <master-ip> <worker1-ip> <worker2-ip> <worker3-ip>; do
  echo "  Node $ip"
  curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://$ip:30080
done

# Test nginx-ingress on all nodes
echo "Testing nginx-ingress (port 38080):"
for ip in <master-ip> <worker1-ip> <worker2-ip> <worker3-ip>; do
  echo "  Node $ip"
  curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://$ip:38080
done
```

## Troubleshooting

### nginx Can't Connect to Backend

```bash
# Check if NodePort is accessible
curl http://<master-ip>:30080

# Check firewall on K8s nodes
sudo ufw status

# Allow NodePort if needed
sudo ufw allow 30080/tcp
sudo ufw allow 30443/tcp
```

### 502 Bad Gateway

- Check if K8s cluster is running: `kubectl get nodes`
- Verify Kourier is running: `kubectl get pods -n knative-serving`
- Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`

### 404 Not Found

- Verify Knative service exists: `kn service list`
- Check Host header is being passed correctly
- Verify Kourier routing: `kubectl get ksvc -A`

## Advanced Configuration

### Rate Limiting

Add to nginx config:

```nginx
limit_req_zone $binary_remote_addr zone=ratelimit:10m rate=10r/s;

server {
    location / {
        limit_req zone=ratelimit burst=20 nodelay;
        # ... rest of config
    }
}
```

### Caching

For static assets:

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=knative_cache:10m max_size=1g inactive=60m;

location / {
    proxy_cache knative_cache;
    proxy_cache_valid 200 60m;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    # ... rest of config
}
```

### WebSocket Support

Already included in the configuration via:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

## Security Recommendations

1. **Restrict Access:**
   ```nginx
   # Allow only specific IPs
   allow 192.168.1.0/24;
   deny all;
   ```

2. **Enable Security Headers:**
   ```nginx
   add_header X-Frame-Options "SAMEORIGIN" always;
   add_header X-Content-Type-Options "nosniff" always;
   add_header X-XSS-Protection "1; mode=block" always;
   ```

3. **Disable Server Tokens:**
   ```nginx
   server_tokens off;
   ```

4. **Use Fail2ban:**
   ```bash
   sudo apt install fail2ban
   # Configure to block repeated failed requests
   ```

## References

- [nginx Documentation](https://nginx.org/en/docs/)
- [Knative Serving Documentation](https://knative.dev/docs/serving/)
- [Kourier Documentation](https://github.com/knative-extensions/net-kourier)

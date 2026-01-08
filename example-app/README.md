# Example Applications

This directory contains example applications for testing and demonstrating the home K3s cluster capabilities.

## Applications

### hello-world-api

Simple Express.js API that returns "hello world". Perfect for testing Knative deployments and cluster functionality.

- **Language**: Node.js (Express)
- **Architecture**: ARM64 (aarch64) for Raspberry Pi
- **Endpoints**:
  - `GET /` - Returns "hello world"
  - `GET /health` - Health check
- **Documentation**: [hello-world-api/README.md](hello-world-api/README.md)

**Quick Start:**
```bash
cd hello-world-api

# Build for ARM64
./build.sh

# Run locally
docker run -p 8080:8080 localhost:5000/hello-world-api:latest

# Deploy to Knative
kubectl apply -f knative-service.yaml
```

## Development Workflow

### 0. Setup Docker Hub
```bash
# Set your Docker Hub username (do this once)
export DOCKER_HUB_USERNAME=yourusername

# Or add to your shell profile
echo 'export DOCKER_HUB_USERNAME=yourusername' >> ~/.zshrc
```

### 1. Local Development
```bash
cd hello-world-api
npm install
npm start
# Test: curl http://localhost:8080/
```

### 2. Build Docker Image for ARM64
```bash
cd hello-world-api
./build.sh v1.0.0
```

### 3. Push to Docker Hub
```bash
./build-and-push.sh v1.0.0
# Will prompt for Docker Hub login
```

### 4. Update Knative Service
Edit `knative-service.yaml` and replace `yourusername` with your Docker Hub username:
```yaml
- image: yourusername/hello-world-api:v1.0.0
```

### 5. Deploy to Cluster
```bash
# Deploy with Knative
kubectl apply -f hello-world-api/knative-service.yaml

# Check status
kubectl get ksvc hello-world-api

# Get URL
kubectl get ksvc hello-world-api -o jsonpath='{.status.url}'
```

## Prerequisites

### Local Development
- Node.js 18+ or 20+
- Docker with buildx support

### Cluster Deployment
- K3s cluster running
- Knative Serving installed
- kubectl configured

## Architecture Support

All applications are built for **ARM64 (aarch64)** architecture to run on:
- Raspberry Pi 4
- Raspberry Pi 5
- Other ARM64-based systems

To build for other architectures, modify the `PLATFORM` variable in `build.sh`:
- ARM64: `linux/arm64`
- AMD64: `linux/amd64`
- Multi-arch: `linux/arm64,linux/amd64`

## Adding New Applications

To add a new example application:

1. Create a new directory: `example-app/my-new-app/`
2. Add application code and dependencies
3. Create `Dockerfile` for containerization
4. Create `build.sh` script for ARM64 builds
5. Add `knative-service.yaml` for Knative deployment
6. Document in `README.md`
7. Update this main README

## Docker Hub Configuration

All images are pushed to Docker Hub. Set your username:

```bash
# Set for current session
export DOCKER_HUB_USERNAME=yourusername

# Or add to shell profile (~/.bashrc, ~/.zshrc, etc.)
echo 'export DOCKER_HUB_USERNAME=yourusername' >> ~/.zshrc

# Then build and push
cd hello-world-api
./build-and-push.sh v1.0.0
```

Your images will be available at:
- `docker.io/yourusername/hello-world-api:latest`
- Public URL: `https://hub.docker.com/r/yourusername/hello-world-api`

## Testing

### Local Testing
```bash
cd hello-world-api
npm install
npm start
curl http://localhost:8080/
```

### Docker Testing
```bash
docker run -p 8080:8080 localhost:5000/hello-world-api:latest
curl http://localhost:8080/
```

### Cluster Testing
```bash
# Deploy
kubectl apply -f hello-world-api/knative-service.yaml

# Wait for ready
kubectl wait --for=condition=Ready ksvc/hello-world-api

# Get URL
URL=$(kubectl get ksvc hello-world-api -o jsonpath='{.status.url}')

# Test (adjust port if needed)
curl -H "Host: hello-world-api.default.kn.home" http://<node-ip>:30080/
```

## Troubleshooting

### Build Issues

**Problem**: Docker buildx not available
```bash
docker buildx install
```

**Problem**: ARM64 emulation not working
```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

### Deployment Issues

**Problem**: Image pull error
```bash
# Check if image exists
docker images | grep hello-world-api

# Verify image is accessible to cluster
kubectl describe pod <pod-name>
```

**Problem**: Service not accessible
```bash
# Check service status
kubectl get ksvc hello-world-api

# Check pods
kubectl get pods -l serving.knative.dev/service=hello-world-api

# View logs
kubectl logs -l serving.knative.dev/service=hello-world-api
```

## Best Practices

1. **Version Tags**: Always tag images with versions (e.g., v1.0.0)
2. **Health Checks**: Include `/health` endpoint in all apps
3. **Resource Limits**: Set appropriate CPU/memory limits
4. **Security**: Run containers as non-root user
5. **Logging**: Use structured logging (JSON)
6. **Graceful Shutdown**: Handle SIGTERM for clean shutdowns

## Resources

- [Docker Documentation](https://docs.docker.com/)
- [Knative Documentation](https://knative.dev/docs/)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- [Docker Build for ARM](https://docs.docker.com/build/building/multi-platform/)

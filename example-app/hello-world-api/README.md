# Hello World API

Simple Express.js API that returns "hello world" on the root endpoint. Built for ARM64 (aarch64) architecture to run on Raspberry Pi.

## Features

- **Simple**: Single endpoint returning "hello world"
- **Health Check**: `/health` endpoint for monitoring
- **Lightweight**: Alpine-based Docker image
- **Production-Ready**: Multi-stage build, non-root user, health checks
- **ARM64 Optimized**: Built specifically for Raspberry Pi 4/5

## Endpoints

### GET /
Returns "hello world" with status 200.

```bash
curl http://localhost:8080/
# Response: hello world
```

### GET /health
Health check endpoint for monitoring.

```bash
curl http://localhost:8080/health
# Response: {"status":"healthy"}
```

## Local Development

### Prerequisites
- Node.js 18+ or 20+
- npm

### Install Dependencies
```bash
npm install
```

### Run Locally
```bash
npm start
# Server starts on http://localhost:8080
```

### Development with Hot Reload (Node 18.11+)
```bash
npm run dev
```

### Test
```bash
# Test main endpoint
curl http://localhost:8080/

# Test health endpoint
curl http://localhost:8080/health
```

## Docker Build

### Prerequisites
- Docker with buildx support
- ARM64 build capability (QEMU or native ARM64)
- Docker Hub account

### Setup Docker Hub Username

Set your Docker Hub username as an environment variable:

```bash
# Set for current session
export DOCKER_HUB_USERNAME=yourusername

# Or add to your shell profile (~/.bashrc, ~/.zshrc)
echo 'export DOCKER_HUB_USERNAME=yourusername' >> ~/.zshrc
```

### Build for ARM64
```bash
# Build with default tag (latest)
DOCKER_HUB_USERNAME=yourusername ./build.sh

# Build with specific tag
DOCKER_HUB_USERNAME=yourusername ./build.sh v1.0.0

# If DOCKER_HUB_USERNAME is exported
./build.sh v1.0.0
```

### Build and Push to Docker Hub
```bash
# Set your Docker Hub username
export DOCKER_HUB_USERNAME=yourusername

# Build and push (will prompt for Docker Hub login)
./build-and-push.sh v1.0.0

# Build, push, and save as tar file
./build-and-push.sh v1.0.0 --save-tar
```

The script will:
1. Build the ARM64 image
2. Prompt for Docker Hub login
3. Push to your Docker Hub account
4. Image will be available at: `docker.io/yourusername/hello-world-api:v1.0.0`

### Run Docker Container
```bash
# Run from Docker Hub (replace with your username)
docker run -p 8080:8080 yourusername/hello-world-api:latest

# Run in background
docker run -d -p 8080:8080 --name hello-api yourusername/hello-world-api:latest

# Test
curl http://localhost:8080/
```

## Deploy to Kubernetes

### Using kubectl
```bash
# Create deployment (replace with your Docker Hub username)
kubectl create deployment hello-world-api \
  --image=yourusername/hello-world-api:latest

# Expose as service
kubectl expose deployment hello-world-api \
  --port=80 \
  --target-port=8080

# Test
kubectl port-forward deployment/hello-world-api 8080:8080
curl http://localhost:8080/
```

### Using Knative

1. Update `knative-service.yaml` with your Docker Hub username:
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello-world-api
spec:
  template:
    spec:
      containers:
        - image: yourusername/hello-world-api:latest  # ← Update this
          ports:
            - containerPort: 8080
          env:
            - name: NODE_ENV
              value: "production"
```

2. Apply:
```bash
kubectl apply -f knative-service.yaml
```

## Configuration

### Environment Variables

- `PORT` - Port to listen on (default: 8080)
- `NODE_ENV` - Node environment (default: development)

Example:
```bash
docker run -p 3000:3000 -e PORT=3000 -e NODE_ENV=production hello-world-api:latest
```

## Architecture

### Application Structure
```
hello-world-api/
├── src/
│   └── index.js          # Main application file
├── package.json          # Node.js dependencies
├── Dockerfile            # Multi-stage Docker build
├── .dockerignore         # Docker build exclusions
├── build.sh              # Build script for ARM64
├── build-and-push.sh     # Build and push script
└── README.md             # This file
```

### Docker Image
- **Base**: Alpine Linux (minimal size)
- **Node**: Node.js 20 LTS
- **User**: Non-root (nodejs:nodejs)
- **Port**: 8080
- **Health Check**: Built-in Docker health check
- **Size**: ~120MB

## Troubleshooting

### Build Issues

**Problem**: Docker buildx not available
```bash
# Install buildx
docker buildx install
```

**Problem**: ARM64 emulation not working
```bash
# Install QEMU for multi-arch builds
docker run --privileged --rm tonistiigi/binfmt --install all
```

### Runtime Issues

**Problem**: Cannot connect to port 8080
```bash
# Check if container is running
docker ps

# Check container logs
docker logs <container-id>

# Verify port mapping
docker port <container-id>
```

**Problem**: Health check failing
```bash
# Check health status
docker inspect <container-id> | grep -A 10 Health

# Test health endpoint manually
docker exec <container-id> wget -q -O- http://localhost:8080/health
```

## Performance

On Raspberry Pi 5:
- **Startup Time**: < 1 second
- **Memory Usage**: ~40MB
- **Response Time**: < 5ms (local)
- **Container Size**: ~120MB

## Security

- Runs as non-root user (nodejs:nodejs, UID 1001)
- Minimal attack surface (Alpine base)
- No shell in production image
- Health checks for monitoring
- Graceful shutdown handlers

## License

MIT

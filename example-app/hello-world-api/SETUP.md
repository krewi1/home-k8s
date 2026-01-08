# Quick Setup Guide

## 1. Set Your Docker Hub Username

Choose one of these methods:

### Option A: Export for Current Session
```bash
export DOCKER_HUB_USERNAME=yourusername
```

### Option B: Add to Shell Profile (Permanent)
```bash
# For Zsh (macOS default)
echo 'export DOCKER_HUB_USERNAME=yourusername' >> ~/.zshrc
source ~/.zshrc

# For Bash
echo 'export DOCKER_HUB_USERNAME=yourusername' >> ~/.bashrc
source ~/.bashrc
```

### Option C: Use .env File (Project-specific)
```bash
# Create .env file
cp .env.example .env

# Edit .env and set your username
echo 'DOCKER_HUB_USERNAME=yourusername' > .env

# Load it before building
source .env
```

## 2. Verify Setup

```bash
echo $DOCKER_HUB_USERNAME
# Should output: yourusername
```

## 3. Build Your First Image

```bash
# Build with latest tag
./build.sh

# Build with specific version
./build.sh v1.0.0
```

## 4. Push to Docker Hub

```bash
# This will build and push
./build-and-push.sh v1.0.0

# You'll be prompted to login to Docker Hub
# Enter your Docker Hub username and password (or access token)
```

## 5. Verify on Docker Hub

Your image will be available at:
- `docker.io/yourusername/hello-world-api:v1.0.0`
- Web: `https://hub.docker.com/r/yourusername/hello-world-api`

## 6. Update Knative Service

Edit `knative-service.yaml`:
```yaml
- image: yourusername/hello-world-api:v1.0.0
```

## 7. Deploy to Cluster

```bash
kubectl apply -f knative-service.yaml
```

## Docker Hub Access Token (Recommended)

Instead of using your password, create an access token:

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Give it a name (e.g., "raspberry-pi-cluster")
4. Copy the token
5. Use the token as password when running `docker login`

```bash
docker login -u yourusername
# Password: [paste your access token]
```

## Troubleshooting

### Error: DOCKER_HUB_USERNAME not set
```bash
# Make sure it's exported
export DOCKER_HUB_USERNAME=yourusername
echo $DOCKER_HUB_USERNAME
```

### Error: unauthorized: authentication required
```bash
# Login to Docker Hub
docker login

# Verify you're logged in
docker info | grep Username
```

### Error: buildx not available
```bash
# Install buildx
docker buildx install

# Verify
docker buildx version
```

### Error: ARM64 emulation not working
```bash
# Install QEMU for multi-platform builds
docker run --privileged --rm tonistiigi/binfmt --install all

# Verify
docker buildx ls
```

## Next Steps

Once your image is on Docker Hub:
1. Anyone can pull it: `docker pull yourusername/hello-world-api:v1.0.0`
2. Your Raspberry Pi cluster can pull it directly
3. No need for local registry setup
4. Images are backed up on Docker Hub

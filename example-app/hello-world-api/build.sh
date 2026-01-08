#!/bin/bash

#####################################################################
# Docker Build Script for ARM64/aarch64
#
# This script builds a Docker image for ARM64 (aarch64) architecture
# suitable for Raspberry Pi 4/5.
#
# Usage:
#   ./build.sh [tag]
#
# Examples:
#   ./build.sh              # Builds with default tag
#   ./build.sh v1.0.0       # Builds with specific version tag
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
IMAGE_NAME="${IMAGE_NAME:-hello-world-api}"
DOCKER_HUB_USERNAME="${DOCKER_HUB_USERNAME:-}"
TAG="${1:-latest}"
PLATFORM="linux/arm64"

# Determine full image name
if [ -z "$DOCKER_HUB_USERNAME" ]; then
    print_error "DOCKER_HUB_USERNAME environment variable is not set"
    echo ""
    echo "Please set your Docker Hub username:"
    echo "  export DOCKER_HUB_USERNAME=yourusername"
    echo ""
    echo "Or pass it inline:"
    echo "  DOCKER_HUB_USERNAME=yourusername ./build.sh"
    echo ""
    exit 1
fi

FULL_IMAGE_NAME="${DOCKER_HUB_USERNAME}/${IMAGE_NAME}:${TAG}"

print_info "Building Docker image for ARM64 architecture"
echo "  Image: ${FULL_IMAGE_NAME}"
echo "  Platform: ${PLATFORM}"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if buildx is available
if ! docker buildx version &> /dev/null; then
    print_error "Docker buildx is not available"
    print_info "Install buildx: https://docs.docker.com/buildx/working-with-buildx/"
    exit 1
fi

# Create buildx builder if it doesn't exist
if ! docker buildx inspect arm64-builder &> /dev/null; then
    print_info "Creating buildx builder for ARM64..."
    docker buildx create --name arm64-builder --platform ${PLATFORM} --use
else
    print_info "Using existing arm64-builder"
    docker buildx use arm64-builder
fi

# Build the image
print_info "Building image..."
docker buildx build \
    --platform ${PLATFORM} \
    --tag ${FULL_IMAGE_NAME} \
    --load \
    .

print_success "Image built successfully: ${FULL_IMAGE_NAME}"

# Display image info
print_info "Image details:"
docker images ${DOCKER_HUB_USERNAME}/${IMAGE_NAME}

echo ""
print_info "To run the container:"
echo "  docker run -p 8080:8080 ${FULL_IMAGE_NAME}"
echo ""
print_info "To push to Docker Hub:"
echo "  ./build-and-push.sh ${TAG}"
echo ""
print_info "Or manually:"
echo "  docker login"
echo "  docker push ${FULL_IMAGE_NAME}"
echo ""
print_info "Image is public on Docker Hub at:"
echo "  https://hub.docker.com/r/${DOCKER_HUB_USERNAME}/${IMAGE_NAME}"
echo ""

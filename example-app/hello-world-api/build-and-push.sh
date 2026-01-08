#!/bin/bash

#####################################################################
# Build and Push Script
#
# Builds the Docker image and pushes it to the registry.
# Optionally saves as tar file for manual transfer.
#
# Usage:
#   ./build-and-push.sh [tag] [--save-tar]
#
# Examples:
#   ./build-and-push.sh v1.0.0
#   ./build-and-push.sh latest --save-tar
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

# Configuration
TAG="${1:-latest}"
SAVE_TAR=false

if [[ "$2" == "--save-tar" ]]; then
    SAVE_TAR=true
fi

# Check Docker Hub username
DOCKER_HUB_USERNAME="${DOCKER_HUB_USERNAME:-}"
if [ -z "$DOCKER_HUB_USERNAME" ]; then
    print_error "DOCKER_HUB_USERNAME environment variable is not set"
    echo ""
    echo "Please set your Docker Hub username:"
    echo "  export DOCKER_HUB_USERNAME=yourusername"
    echo ""
    exit 1
fi

# Build the image
print_info "Building image with tag: ${TAG}"
./build.sh ${TAG}

# Push to Docker Hub
IMAGE_NAME="${IMAGE_NAME:-hello-world-api}"
FULL_IMAGE_NAME="${DOCKER_HUB_USERNAME}/${IMAGE_NAME}:${TAG}"

print_info "Logging in to Docker Hub..."
echo "Please enter your Docker Hub credentials:"
docker login

print_info "Pushing image to Docker Hub..."
docker push ${FULL_IMAGE_NAME}
print_success "Image pushed to Docker Hub: ${FULL_IMAGE_NAME}"

# Save as tar if requested
if [ "$SAVE_TAR" = true ]; then
    TAR_FILE="hello-world-api-${TAG}.tar"
    print_info "Saving image as tar file: ${TAR_FILE}"
    docker save ${FULL_IMAGE_NAME} -o ${TAR_FILE}
    print_success "Image saved to: ${TAR_FILE}"
    echo ""
    print_info "To load on another machine:"
    echo "  docker load -i ${TAR_FILE}"
fi

print_success "Build and push complete!"

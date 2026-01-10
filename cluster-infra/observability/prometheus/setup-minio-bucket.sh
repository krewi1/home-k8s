#!/bin/bash

#####################################################################
# MinIO Bucket Setup for Thanos
#
# Creates the 'thanos' bucket in MinIO for long-term metrics storage
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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "  Thanos MinIO Bucket Setup"
echo "=========================================="
echo ""

# Check if MinIO is running
if ! kubectl get pod -n minio -l app=minio | grep -q Running; then
    print_error "MinIO is not running. Please install MinIO first."
    exit 1
fi

print_info "Creating Thanos bucket in MinIO..."

# Create a temporary pod with mc (MinIO client) to create the bucket
kubectl run -n minio mc-thanos-setup \
    --image=minio/mc:latest \
    --restart=Never \
    --rm \
    -i \
    --command -- sh -c "
    mc alias set myminio http://minio.minio.svc.cluster.local:9000 admin changeMe123!
    mc mb myminio/thanos --ignore-existing
    mc ls myminio/
    echo 'Bucket created successfully!'
"

print_success "Thanos bucket created in MinIO"
echo ""
print_info "Next steps:"
echo "  1. Update thanos/minio-secret.yaml with your MinIO credentials"
echo "  2. Run the install script to deploy Prometheus + Thanos"

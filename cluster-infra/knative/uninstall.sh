#!/bin/bash

#####################################################################
# Knative Serving Uninstallation Script
#####################################################################

set -e

# Colors for output
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

# Configuration
KNATIVE_VERSION="${KNATIVE_VERSION:-v1.20.0}"

echo "=========================================="
echo "  Knative Serving Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove Knative Serving and Kourier from your cluster"
read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling Kourier..."
kubectl delete -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml --ignore-not-found=true

print_info "Uninstalling Knative Serving core..."
kubectl delete -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml --ignore-not-found=true

print_info "Uninstalling Knative Serving CRDs..."
kubectl delete -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml --ignore-not-found=true

print_info "Cleaning up namespaces..."
kubectl delete namespace knative-serving --ignore-not-found=true
kubectl delete namespace kourier-system --ignore-not-found=true

print_success "Knative Serving and Kourier have been uninstalled"

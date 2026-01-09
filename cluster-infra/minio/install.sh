#!/bin/bash

#####################################################################
# MinIO Installation Script (Standalone Mode)
#
# Installs MinIO in standalone mode using the SSD on master node
# Can be migrated to distributed mode later when more nodes are added
#
# Prerequisites:
#   - K3s cluster running
#   - SSD formatted and mounted at /mnt/minio-data on master node
#   - kubectl configured
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MINIO_VERSION="standalone"
NAMESPACE="minio"

#####################################################################
# Helper Functions
#####################################################################

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

print_step() {
    echo -e "\n${CYAN}==>${NC} $1"
}

check_kubectl() {
    print_step "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    print_success "kubectl configured and cluster accessible"
}

check_ssd_mount() {
    print_step "Checking SSD mount..."

    local master_node=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')

    print_info "Checking /mnt/minio-data on $master_node..."

    if ! kubectl get node "$master_node" &> /dev/null; then
        print_error "Master node not found"
        exit 1
    fi

    print_success "Master node found: $master_node"
    print_warning "Ensure /mnt/minio-data is mounted on $master_node before continuing"

    read -p "Is /mnt/minio-data mounted and ready? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Installation cancelled. Please mount the SSD first."
        exit 0
    fi
}

check_existing_installation() {
    print_step "Checking for existing installation..."

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "Namespace $NAMESPACE already exists"
        read -p "Do you want to continue? This may upgrade or reinstall components. (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

update_credentials() {
    print_step "Security Warning: Default Credentials"

    print_warning "The default credentials are:"
    echo "  Username: admin"
    echo "  Password: changeme123"
    echo ""
    print_warning "You should change these after installation!"
    echo ""

    read -p "Do you want to set custom credentials now? (y/N): " set_custom

    if [[ "$set_custom" == "y" || "$set_custom" == "Y" ]]; then
        read -p "Enter MinIO root username: " minio_user
        read -sp "Enter MinIO root password: " minio_pass
        echo ""

        # Update secret file
        sed -i.bak "s/rootUser: \"admin\"/rootUser: \"$minio_user\"/" standalone/secret.yaml
        sed -i.bak "s/rootPassword: \"changeme123\"/rootPassword: \"$minio_pass\"/" standalone/secret.yaml

        print_success "Credentials updated in manifest"
    fi
}

install_minio() {
    print_step "Installing MinIO (Standalone Mode)..."

    print_info "Applying manifests..."
    kubectl apply -f standalone/namespace.yaml
    kubectl apply -f standalone/secret.yaml
    kubectl apply -f standalone/pv-pvc.yaml
    kubectl apply -f standalone/deployment.yaml
    kubectl apply -f standalone/service.yaml
    kubectl apply -f standalone/ingress.yaml

    print_success "MinIO manifests applied"
}

wait_for_minio() {
    print_step "Waiting for MinIO to be ready..."

    print_info "Waiting for deployment..."
    kubectl wait --namespace "$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app=minio \
        --timeout=300s

    print_success "MinIO is ready"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "MinIO Deployment:"
    kubectl get deployment -n "$NAMESPACE"
    echo ""
    echo "MinIO Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "MinIO Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "MinIO Ingress:"
    kubectl get ingress -n "$NAMESPACE"
    echo ""
    echo "MinIO PVC:"
    kubectl get pvc -n "$NAMESPACE"

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    echo ""
    echo "=========================================="
    print_success "MinIO Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Access Information:"
    echo ""
    echo "  Web Console: http://minio.home"
    echo "  API Endpoint: http://minio-api.home"
    echo ""
    echo "  Or via IP:"
    echo "  Web Console: http://$node_ip:38080 (with Host: minio.home)"
    echo "  API: http://$node_ip:38080 (with Host: minio-api.home)"
    echo ""
    echo "Credentials:"
    echo "  Check standalone/secret.yaml for username/password"
    echo ""
    echo "Storage:"
    echo "  Location: /mnt/minio-data (on master node)"
    echo "  Size: ~800GB"
    echo ""
    echo "Next Steps:"
    echo "  1. Access web console at http://minio.home"
    echo "  2. Login with credentials"
    echo "  3. Create buckets for your applications"
    echo "  4. Configure applications to use MinIO"
    echo ""
    echo "Future Expansion:"
    echo "  See docs/expansion-guide.md for migrating to distributed mode"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  MinIO Installation (Standalone)"
    echo "=========================================="
    echo ""
    echo "Mode: Standalone (Single Node)"
    echo "Storage: /mnt/minio-data on master node"
    echo ""

    # Check prerequisites
    check_kubectl

    # Check SSD mount
    check_ssd_mount

    # Check for existing installation
    check_existing_installation

    # Update credentials
    update_credentials

    # Install MinIO
    install_minio

    # Wait for MinIO to be ready
    wait_for_minio

    # Verify installation
    verify_installation

    # Display installation information
    display_installation_info

    print_success "Installation script completed!"
}

# Run main function
main "$@"

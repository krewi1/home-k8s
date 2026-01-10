#!/bin/bash

#####################################################################
# Garage Installation Script (Standalone Mode)
#
# Installs Garage in standalone mode using the SSD on master node
# Can be migrated to distributed mode later when more nodes are added
#
# Prerequisites:
#   - K3s cluster running
#   - SSD formatted and mounted at /mnt/garage-data on master node
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
GARAGE_VERSION="standalone"
NAMESPACE="garage"

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

    print_info "Checking /mnt/garage-data on $master_node..."

    if ! kubectl get node "$master_node" &> /dev/null; then
        print_error "Master node not found"
        exit 1
    fi

    print_success "Master node found: $master_node"
    print_warning "Ensure /mnt/garage-data is mounted on $master_node before continuing"

    read -p "Is /mnt/garage-data mounted and ready? (y/N): " confirm
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
    print_step "Security Warning: Default RPC Secret"

    print_warning "The default RPC secret is set in standalone/secret.yaml"
    echo ""
    print_warning "You should change this after installation!"
    echo ""

    read -p "Do you want to set a custom RPC secret now? (y/N): " set_custom

    if [[ "$set_custom" == "y" || "$set_custom" == "Y" ]]; then
        # Generate random secret
        local rpc_secret=$(openssl rand -base64 32)

        # Update secret file
        sed -i.bak "s/rpc_secret = \"changeMe123!\"/rpc_secret = \"$rpc_secret\"/" standalone/secret.yaml

        print_success "RPC secret updated in manifest"
    fi
}

install_garage() {
    print_step "Installing Garage (Standalone Mode)..."

    print_info "Applying manifests..."
    kubectl apply -f standalone/namespace.yaml
    kubectl apply -f standalone/secret.yaml
    kubectl apply -f standalone/pv-pvc.yaml
    kubectl apply -f standalone/deployment.yaml
    kubectl apply -f standalone/service.yaml
    kubectl apply -f standalone/ingress.yaml

    print_success "Garage manifests applied"
}

wait_for_garage() {
    print_step "Waiting for Garage to be ready..."

    print_info "Waiting for deployment..."
    kubectl wait --namespace "$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app=garage \
        --timeout=300s

    print_success "Garage is ready"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Garage Deployment:"
    kubectl get deployment -n "$NAMESPACE"
    echo ""
    echo "Garage Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Garage Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "Garage Ingress:"
    kubectl get ingress -n "$NAMESPACE"
    echo ""
    echo "Garage PVC:"
    kubectl get pvc -n "$NAMESPACE"

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    echo ""
    echo "=========================================="
    print_success "Garage Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Access Information:"
    echo ""
    echo "  S3 API: http://garage-api.home"
    echo "  Web UI: http://garage.home"
    echo ""
    echo "  Or via IP:"
    echo "  S3 API: http://$node_ip:38080 (with Host: garage-api.home)"
    echo "  Web UI: http://$node_ip:38080 (with Host: garage.home)"
    echo ""
    echo "  Internal cluster service:"
    echo "  S3 API: garage.garage.svc.cluster.local:3900"
    echo ""
    echo "Configuration:"
    echo "  Config file: /etc/garage.toml (in secret garage-config)"
    echo "  RPC Secret: Change 'rpc_secret' in standalone/secret.yaml"
    echo ""
    echo "Storage:"
    echo "  Location: /mnt/garage-data (on master node)"
    echo "  Size: ~800GB"
    echo ""
    echo "Next Steps:"
    echo "  1. Get the node ID:"
    echo "     kubectl exec -n garage deployment/garage -- garage status"
    echo ""
    echo "  2. Create a garage layout:"
    echo "     kubectl exec -n garage deployment/garage -- garage layout assign -z dc1 -c 1 <node-id>"
    echo "     kubectl exec -n garage deployment/garage -- garage layout apply --version 1"
    echo ""
    echo "  3. Create keys and buckets:"
    echo "     kubectl exec -n garage deployment/garage -- garage key create my-key"
    echo "     kubectl exec -n garage deployment/garage -- garage bucket create my-bucket"
    echo "     kubectl exec -n garage deployment/garage -- garage bucket allow --read --write my-bucket --key my-key"
    echo ""
    echo "  4. Configure applications to use Garage S3 API"
    echo "     Endpoint: http://garage.garage.svc.cluster.local:3900"
    echo "     Region: garage"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  Garage Installation (Standalone)"
    echo "=========================================="
    echo ""
    echo "Mode: Standalone (Single Node)"
    echo "Storage: /mnt/garage-data on master node"
    echo ""

    # Check prerequisites
    check_kubectl

    # Check SSD mount
    check_ssd_mount

    # Check for existing installation
    check_existing_installation

    # Update credentials
    update_credentials

    # Install Garage
    install_garage

    # Wait for Garage to be ready
    wait_for_garage

    # Verify installation
    verify_installation

    # Display installation information
    display_installation_info

    print_success "Installation script completed!"
}

# Run main function
main "$@"

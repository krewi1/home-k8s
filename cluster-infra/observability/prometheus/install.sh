#!/bin/bash

#####################################################################
# Prometheus + Thanos Installation Script
#
# Installs complete observability stack:
#   - Prometheus (with Thanos sidecar)
#   - Thanos Query, Store Gateway, Compactor
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - Garage installed and running
#   - Master node with /mnt/k8s-pvc mounted
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
NAMESPACE="observability"

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

check_garage() {
    print_step "Checking Garage availability..."

    if ! kubectl get namespace garage &> /dev/null; then
        print_error "Garage namespace not found. Please install Garage first."
        exit 1
    fi

    if ! kubectl get pod -n garage -l app=garage | grep -q Running; then
        print_error "Garage is not running. Please ensure Garage is installed and running."
        exit 1
    fi

    print_success "Garage is available"
}

check_existing_installation() {
    print_step "Checking for existing installation..."

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        if kubectl get deployment prometheus -n "$NAMESPACE" &> /dev/null; then
            print_warning "Observability stack is already installed"
            read -p "Do you want to continue? This may upgrade or reinstall. (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                print_info "Installation cancelled"
                exit 0
            fi
        fi
    fi
}

setup_storage() {
    print_step "Setting up storage directory on master node..."

    local master_node=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$master_node" ]; then
        print_error "Could not find master node"
        exit 1
    fi

    print_info "Master node: $master_node"
    print_warning "Please ensure /mnt/k8s-pvc is mounted on $master_node"
    echo ""
    print_info "Run the following command on the master node to create the directory:"
    echo ""
    echo "  sudo mkdir -p /mnt/k8s-pvc/prometheus"
    echo "  sudo chown -R 65534:65534 /mnt/k8s-pvc/prometheus"
    echo "  sudo chmod 755 /mnt/k8s-pvc/prometheus"
    echo ""

    read -p "Have you created the directory and set permissions? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Installation cancelled. Please set up the directory first."
        exit 0
    fi
}

setup_garage_bucket() {
    print_step "Setting up Garage bucket for Thanos..."

    print_warning "Please create the bucket and key in Garage manually:"
    echo ""
    echo "  # Create a key for Thanos"
    echo "  garage key new --name thanos-key"
    echo ""
    echo "  # Create the bucket"
    echo "  garage bucket create thanos"
    echo ""
    echo "  # Allow the key to access the bucket"
    echo "  garage bucket allow --read --write thanos --key thanos-key"
    echo ""
    echo "  # Get the credentials"
    echo "  garage key info thanos-key"
    echo ""
    print_warning "Update garage-secret.yaml with the access_key and secret_key from above"
    echo ""

    read -p "Have you created the bucket and updated the secret? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Installation cancelled. Please set up Garage first."
        exit 0
    fi
}

install_stack() {
    print_step "Installing Prometheus + Thanos..."

    print_info "Creating namespace..."
    kubectl apply -f namespace.yaml

    print_info "Setting up RBAC..."
    kubectl apply -f rbac.yaml

    print_info "Creating ConfigMap..."
    kubectl apply -f configmap.yaml

    print_info "Creating storage..."
    kubectl apply -f pv-pvc.yaml

    print_info "Creating Thanos object storage secret..."
    kubectl apply -f garage-secret.yaml

    print_info "Deploying Prometheus with Thanos sidecar..."
    kubectl apply -f deployment.yaml

    print_info "Creating Prometheus service..."
    kubectl apply -f service.yaml

    print_info "Deploying Thanos Store Gateway..."
    kubectl apply -f store-gateway.yaml

    print_info "Deploying Thanos Query..."
    kubectl apply -f query.yaml

    print_info "Deploying Thanos Compactor..."
    kubectl apply -f compactor.yaml

    print_success "All components deployed"
}

wait_for_stack() {
    print_step "Waiting for components to be ready..."

    print_info "Waiting for Prometheus..."
    kubectl wait --namespace "$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app=prometheus \
        --timeout=300s

    print_info "Waiting for Thanos Query..."
    kubectl wait --namespace "$NAMESPACE" \
        --for=condition=ready pod \
        --selector=app=thanos-query \
        --timeout=300s

    print_success "All components are ready"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Deployments:"
    kubectl get deployment -n "$NAMESPACE"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "PVC:"
    kubectl get pvc -n "$NAMESPACE"

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    echo ""
    echo "=========================================="
    print_success "Observability Stack Installed!"
    echo "=========================================="
    echo ""
    echo "Components:"
    echo "  ✅ Prometheus (with Thanos sidecar)"
    echo "  ✅ Thanos Query"
    echo "  ✅ Thanos Store Gateway"
    echo "  ✅ Thanos Compactor"
    echo ""
    echo "Storage:"
    echo "  - Recent Data (7 days):  /mnt/k8s-pvc/prometheus (20Gi SSD)"
    echo "  - Long-term Data (1yr+): Garage bucket 'thanos'"
    echo ""
    echo "Data Retention:"
    echo "  - Raw metrics:        30 days"
    echo "  - 5min downsampled:   90 days"
    echo "  - 1hr downsampled:    365 days"
    echo ""
    echo "Access (via port-forward):"
    echo "  Thanos Query:"
    echo "    kubectl port-forward -n observability svc/thanos-query 9090:9090"
    echo "  Prometheus:"
    echo "    kubectl port-forward -n observability svc/prometheus 9091:9090"
    echo ""
    echo "Next Steps:"
    echo "  1. Install Grafana"
    echo "  2. Configure Grafana data source:"
    echo "     Type: Prometheus"
    echo "     URL: http://thanos-query.observability.svc.cluster.local:9090"
    echo "  3. Import recommended dashboards (see ../README.md)"
    echo "  4. Wait 2+ hours for first data blocks to upload to Garage"
    echo ""
    echo "Annotations for auto-discovery:"
    echo "  Add these annotations to your pods/services:"
    echo "    prometheus.io/scrape: \"true\""
    echo "    prometheus.io/port: \"<metrics-port>\""
    echo "    prometheus.io/path: \"/metrics\"  # optional"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  Prometheus + Thanos Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - Prometheus (with Thanos sidecar)"
    echo "  - Thanos Query, Store Gateway, Compactor"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo ""

    # Check prerequisites
    check_kubectl
    check_garage
    check_existing_installation
    setup_storage
    setup_garage_bucket

    # Install everything
    install_stack
    wait_for_stack
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"

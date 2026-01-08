#!/bin/bash

#####################################################################
# Knative Serving with Kourier Installation Script
#
# This script installs Knative Serving with Kourier as the ingress
# controller on your K3s cluster. Services will be accessible at
# *.kn.home domain.
#
# Prerequisites:
#   - K3s cluster running with kubectl configured
#   - Internet connection for downloading manifests
#####################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
KNATIVE_VERSION="${KNATIVE_VERSION:-v1.20.0}"
KNATIVE_SERVING_CRDS_URL="https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml"
KNATIVE_SERVING_CORE_URL="https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml"
KOURIER_URL="https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml"

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

check_existing_installation() {
    print_step "Checking for existing installation..."

    if kubectl get namespace knative-serving &> /dev/null; then
        print_warning "Knative Serving namespace already exists"
        read -p "Do you want to continue? This may upgrade or reinstall components. (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

install_knative_crds() {
    print_step "Installing Knative Serving CRDs..."
    print_info "Downloading from: $KNATIVE_SERVING_CRDS_URL"

    kubectl apply -f "$KNATIVE_SERVING_CRDS_URL"

    print_success "Knative Serving CRDs installed"
}

install_knative_core() {
    print_step "Installing Knative Serving core components..."
    print_info "Downloading from: $KNATIVE_SERVING_CORE_URL"

    kubectl apply -f "$KNATIVE_SERVING_CORE_URL"

    print_success "Knative Serving core installed"
}

wait_for_knative_serving() {
    print_step "Waiting for Knative Serving to be ready..."

    print_info "Waiting for deployments in knative-serving namespace..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment --all -n knative-serving

    print_success "Knative Serving is ready"
}

install_kourier() {
    print_step "Installing Kourier networking layer..."
    print_info "Downloading from: $KOURIER_URL"

    kubectl apply -f "$KOURIER_URL"

    print_success "Kourier installed"
}

wait_for_kourier() {
    print_step "Waiting for Kourier to be ready..."

    print_info "Waiting for deployments in kourier-system namespace..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment --all -n kourier-system

    print_success "Kourier is ready"
}

configure_kourier_nodeport() {
    print_step "Configuring Kourier as NodePort service..."

    # Patch the Kourier service to be NodePort type
    kubectl patch service kourier \
        --namespace kourier-system \
        --type merge \
        --patch '{"spec":{"type":"NodePort"}}'

#     Set specific NodePort for HTTP (optional - K8s will auto-assign if not specified)
#     Uncomment the following if you want a specific port:
     kubectl patch service kourier \
         --namespace kourier-system \
         --type merge \
         --patch '{"spec":{"ports":[{"name":"http2","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080}]}}'

    print_success "Kourier configured as NodePort"

    local kourier_nodeport=$(kubectl get svc -n kourier-system kourier \
        -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

    print_info "Kourier is accessible on port $kourier_nodeport on all nodes"
}

configure_knative_network() {
    print_step "Configuring Knative to use Kourier..."

    kubectl patch configmap/config-network \
        --namespace knative-serving \
        --type merge \
        --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

    print_success "Knative configured to use Kourier"
}

configure_custom_domain() {
    print_step "Configuring custom domain (kn.home)..."

    kubectl patch configmap/config-domain \
        --namespace knative-serving \
        --type merge \
        --patch '{"data":{"kn.home":""}}'

    print_success "Domain configured to kn.home"
    print_info "Services will be accessible at: <service-name>.<namespace>.kn.home"
    echo ""
    print_warning "DNS Configuration Required:"
    echo "  Add to your /etc/hosts or DNS server:"
    echo "    <node-ip> *.kn.home"
    echo ""
    echo "  Or for individual services:"
    echo "    <node-ip> <service-name>.<namespace>.kn.home"
}

display_installation_info() {
    print_step "Installation complete!"

    local kourier_nodeport=$(kubectl get svc -n kourier-system kourier \
        -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "N/A")

    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    echo ""
    echo "=========================================="
    print_success "Knative Serving Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Knative Serving Status:"
    kubectl get pods -n knative-serving
    echo ""
    echo "Kourier Gateway Status:"
    kubectl get pods -n kourier-system
    echo ""
    echo "Kourier Service:"
    kubectl get svc -n kourier-system kourier
    echo ""
    echo "Access Information:"
    echo "  Node IP: $node_ip"
    echo "  HTTP Port: $kourier_nodeport"
    echo "  Base Domain: kn.home"
    echo ""
    echo "DNS Configuration:"
    echo "  Add to /etc/hosts on your client machine:"
    echo "    $node_ip hello.default.kn.home"
    echo ""
    echo "To deploy a test service:"
    echo "  kubectl apply -f examples/hello-service.yaml"
    echo ""
    echo "To test the service:"
    echo "  curl http://hello.default.kn.home:$kourier_nodeport"
    echo "  # Or with explicit Host header:"
    echo "  curl -H \"Host: hello.default.kn.home\" http://$node_ip:$kourier_nodeport"
    echo ""
    echo "View Knative services:"
    echo "  kubectl get ksvc -A"
    echo ""
    echo "=========================================="
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Checking Knative Serving components..."
    kubectl get pods -n knative-serving

    echo ""
    echo "Checking Kourier components..."
    kubectl get pods -n kourier-system

    echo ""
    echo "Checking network configuration..."
    kubectl get configmap config-network -n knative-serving -o yaml | grep ingress-class

    echo ""
    echo "Checking domain configuration..."
    kubectl get configmap config-domain -n knative-serving -o yaml | grep kn.home

    print_success "Installation verification complete"
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  Knative Serving Installation"
    echo "=========================================="
    echo ""
    echo "Knative Version: $KNATIVE_VERSION"
    echo "Base Domain: kn.home"
    echo ""

    # Check prerequisites
    check_kubectl

    # Check for existing installation
    check_existing_installation

    # Install Knative Serving CRDs
    install_knative_crds

    # Install Knative Serving core
    install_knative_core

    # Wait for Knative Serving to be ready
    wait_for_knative_serving

    # Install Kourier
    install_kourier

    # Wait for Kourier to be ready
    wait_for_kourier

    # Configure Kourier as NodePort service
    configure_kourier_nodeport

    # Configure Knative to use Kourier
    configure_knative_network

    # Configure custom domain (kn.home)
    configure_custom_domain

    # Verify installation
    verify_installation

    # Display installation information
    display_installation_info

    print_success "Installation script completed!"
}

# Run main function
main "$@"

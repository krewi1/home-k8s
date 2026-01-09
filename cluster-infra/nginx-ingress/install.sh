#!/bin/bash

#####################################################################
# nginx-ingress Controller Installation Script
#
# Installs nginx-ingress for standard Kubernetes Ingress resources.
# Works alongside Kourier for regular (non-Knative) services.
#
# Exposed on NodePort 38080 (HTTP) and 38443 (HTTPS)
#
# Prerequisites:
#   - K3s cluster running with kubectl configured
#   - Internet connection for downloading manifests
#####################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NGINX_VERSION="${NGINX_VERSION:-v1.10.0}"
NGINX_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"
HTTP_NODEPORT=32080
HTTPS_NODEPORT=32443

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

    if kubectl get namespace ingress-nginx &> /dev/null; then
        print_warning "ingress-nginx namespace already exists"
        read -p "Do you want to continue? This may upgrade or reinstall components. (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

install_nginx_ingress() {
    print_step "Installing nginx-ingress controller..."
    print_info "Downloading from: $NGINX_MANIFEST_URL"

    kubectl apply -f "$NGINX_MANIFEST_URL"

    print_success "nginx-ingress controller installed"
}

wait_for_nginx_ingress() {
    print_step "Waiting for nginx-ingress to be ready..."

    print_info "Waiting for controller deployment..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s

    print_success "nginx-ingress controller is ready"
}

configure_nodeport() {
    print_step "Configuring NodePort service..."

    print_info "Setting HTTP port to ${HTTP_NODEPORT} and HTTPS port to ${HTTPS_NODEPORT}"

    # Patch the service to use specific NodePorts and set externalTrafficPolicy
    kubectl patch service ingress-nginx-controller \
        --namespace ingress-nginx \
        --type merge \
        --patch "{
            \"spec\": {
                \"type\": \"NodePort\",
                \"externalTrafficPolicy\": \"Cluster\",
                \"ports\": [
                    {
                        \"name\": \"http\",
                        \"port\": 80,
                        \"protocol\": \"TCP\",
                        \"targetPort\": 80,
                        \"nodePort\": ${HTTP_NODEPORT}
                    },
                    {
                        \"name\": \"https\",
                        \"port\": 443,
                        \"protocol\": \"TCP\",
                        \"targetPort\": 443,
                        \"nodePort\": ${HTTPS_NODEPORT}
                    }
                ]
            }
        }"

    print_success "nginx-ingress configured as NodePort"
    print_info "HTTP accessible on port ${HTTP_NODEPORT} on all nodes"
    print_info "HTTPS accessible on port ${HTTPS_NODEPORT} on all nodes"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Checking nginx-ingress pods..."
    kubectl get pods -n ingress-nginx

    echo ""
    echo "Checking nginx-ingress service..."
    kubectl get svc -n ingress-nginx ingress-nginx-controller

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    echo ""
    echo "=========================================="
    print_success "nginx-ingress Installation Complete!"
    echo "=========================================="
    echo ""
    echo "nginx-ingress Controller Status:"
    kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller
    echo ""
    echo "Service Configuration:"
    kubectl get svc -n ingress-nginx ingress-nginx-controller
    echo ""
    echo "Access Information:"
    echo "  Node IP: $node_ip"
    echo "  HTTP Port: ${HTTP_NODEPORT}"
    echo "  HTTPS Port: ${HTTPS_NODEPORT}"
    echo ""
    echo "Service Separation:"
    echo "  - nginx-ingress: HTTP ${HTTP_NODEPORT}, HTTPS ${HTTPS_NODEPORT}"
    echo "  - Kourier (Knative): Separate port (typically 30080-32767)"
    echo ""
    echo "To deploy a test application with Ingress:"
    echo "  kubectl apply -f examples/simple-ingress.yaml"
    echo ""
    echo "Test with curl:"
    echo "  curl -H \"Host: myapp.local\" http://$node_ip:${HTTP_NODEPORT}/"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  nginx-ingress Installation"
    echo "=========================================="
    echo ""
    echo "Version: $NGINX_VERSION"
    echo "HTTP NodePort: $HTTP_NODEPORT"
    echo "HTTPS NodePort: $HTTPS_NODEPORT"
    echo ""

    # Check prerequisites
    check_kubectl

    # Check for existing installation
    check_existing_installation

    # Install nginx-ingress
    install_nginx_ingress

    # Wait for nginx-ingress to be ready
    wait_for_nginx_ingress

    # Configure NodePort
    configure_nodeport

    # Verify installation
    verify_installation

    # Display installation information
    display_installation_info

    print_success "Installation script completed!"
}

# Run main function
main "$@"

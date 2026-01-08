#!/bin/bash

#####################################################################
# K3s Worker Node Installation Script
#
# This script installs K3s agent on a worker node (Raspberry Pi)
# and joins it to an existing K3s master node.
#
# Prerequisites:
#   - Master node IP address and node token
#   - Static IP address configured on worker
#   - Internet connection available
#
# Usage:
#   ./install-worker.sh <master-ip> <node-token>
#   ./install-worker.sh 192.168.1.100 K10abcd1234::server:xyz789
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
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
DATA_DIR="/var/lib/rancher/k3s"

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

print_usage() {
    echo "Usage: $0 <master-ip> <node-token> [rpi-version]"
    echo ""
    echo "Arguments:"
    echo "  master-ip    : IP address of the K3s master node"
    echo "  node-token   : Token from master node (/var/lib/rancher/k3s/server/node-token)"
    echo "  rpi-version  : (Optional) Raspberry Pi version (3, 4, 5, etc.)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 K10abcd1234::server:xyz789"
    echo "  $0 192.168.1.100 K10abcd1234::server:xyz789 5"
    echo ""
    echo "To get the token from master node:"
    echo "  sudo cat /var/lib/rancher/k3s/server/node-token"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0 $*"
        exit 1
    fi
}

detect_rpi_version() {
    # Try to detect Raspberry Pi version from hardware info
    if [[ -f /proc/cpuinfo ]]; then
        local model=$(grep "Model" /proc/cpuinfo | head -1)
        if [[ $model =~ "Raspberry Pi 5" ]]; then
            echo "5"
        elif [[ $model =~ "Raspberry Pi 4" ]]; then
            echo "4"
        elif [[ $model =~ "Raspberry Pi 3" ]]; then
            echo "3"
        elif [[ $model =~ "Raspberry Pi 2" ]]; then
            echo "2"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

check_arguments() {
    if [[ $# -lt 2 || $# -gt 3 ]]; then
        print_error "Invalid number of arguments"
        echo ""
        print_usage
        exit 1
    fi

    MASTER_IP="$1"
    NODE_TOKEN="$2"
    RPI_VERSION="${3:-}"

    # Validate IP address format
    if ! [[ $MASTER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP address format: $MASTER_IP"
        print_usage
        exit 1
    fi

    # Validate token is not empty
    if [[ -z "$NODE_TOKEN" ]]; then
        print_error "Node token cannot be empty"
        print_usage
        exit 1
    fi

    # Auto-detect or validate RPi version
    if [[ -z "$RPI_VERSION" ]]; then
        RPI_VERSION=$(detect_rpi_version)
        if [[ "$RPI_VERSION" != "unknown" ]]; then
            print_info "Auto-detected Raspberry Pi version: $RPI_VERSION"
        else
            print_warning "Could not auto-detect Raspberry Pi version"
            read -p "Enter Raspberry Pi version (3, 4, 5, or leave empty): " RPI_VERSION
            RPI_VERSION="${RPI_VERSION:-unknown}"
        fi
    fi
}

check_prerequisites() {
    print_step "Checking prerequisites..."

    # Check worker node IP
    local worker_ip=$(hostname -I | awk '{print $1}')
    print_info "Worker node IP: $worker_ip"

    # Check master node connectivity
    print_info "Testing connectivity to master node at $MASTER_IP..."
    if ! ping -c 1 "$MASTER_IP" >/dev/null 2>&1; then
        print_error "Cannot reach master node at $MASTER_IP"
        echo "Please check:"
        echo "  - Master node is running"
        echo "  - Network connectivity between nodes"
        echo "  - IP address is correct"
        exit 1
    fi
    print_success "Master node is reachable"

    # Check if master K3s API is accessible
    print_info "Checking K3s API on master node..."
    if ! curl -sk "https://$MASTER_IP:6443" >/dev/null 2>&1; then
        print_warning "Cannot connect to K3s API at https://$MASTER_IP:6443"
        print_info "This might be normal if the master is still starting up"
    else
        print_success "K3s API is accessible"
    fi

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_error "No internet connectivity. Please check your network connection."
        exit 1
    fi
    print_success "Internet connectivity verified"

    # Check if K3s is already installed
    if command -v k3s >/dev/null 2>&1; then
        print_warning "K3s is already installed"
        k3s --version
        echo ""
        read -p "Do you want to reinstall K3s? (y/N): " reinstall
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
        print_info "Uninstalling existing K3s..."
        /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
        sleep 2
    fi
}

disable_swap() {
    print_step "Disabling swap (if enabled)..."

    if [ -f /proc/swaps ] && [ $(cat /proc/swaps | wc -l) -gt 1 ]; then
        swapoff -a
        sed -i '/ swap / s/^/#/' /etc/fstab
        print_success "Swap disabled"
    else
        print_info "Swap not enabled"
    fi
}

enable_cgroups() {
    print_step "Ensuring cgroups are enabled..."

    # Check if we need to modify boot config
    if grep -q "cgroup_memory=1 cgroup_enable=memory" /boot/firmware/cmdline.txt 2>/dev/null; then
        print_info "cgroups already enabled"
        return
    fi

    # For Raspberry Pi OS
    if [[ -f /boot/firmware/cmdline.txt ]]; then
        cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup
        sed -i '$ s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt

        # Also update /boot/firmware/current/cmdline.txt if it exists
        if [[ -f /boot/firmware/current/cmdline.txt ]]; then
            cp /boot/firmware/current/cmdline.txt /boot/firmware/current/cmdline.txt.backup
            sed -i '$ s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/current/cmdline.txt
            print_info "Updated both /boot/firmware/cmdline.txt and /boot/firmware/current/cmdline.txt"
        fi

        print_warning "cgroups enabled - REBOOT REQUIRED after installation"
        CGROUPS_MODIFIED=1
    elif [[ -f /boot/cmdline.txt ]]; then
        cp /boot/cmdline.txt /boot/cmdline.txt.backup
        sed -i '$ s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt
        print_warning "cgroups enabled - REBOOT REQUIRED after installation"
        CGROUPS_MODIFIED=1
    else
        print_info "Boot config not found, assuming cgroups are enabled"
    fi
}

install_k3s_agent() {
    print_step "Installing K3s agent on worker node..."

    local worker_ip=$(hostname -I | awk '{print $1}')
    local hostname=$(hostname)

    # K3s installation options
    export INSTALL_K3S_CHANNEL="$K3S_CHANNEL"
    export K3S_URL="https://$MASTER_IP:6443"
    export K3S_TOKEN="$NODE_TOKEN"
    export INSTALL_K3S_EXEC="agent"

    # Build node labels
    local node_labels=()

    # Add Raspberry Pi version label
    if [[ -n "$RPI_VERSION" && "$RPI_VERSION" != "unknown" ]]; then
        node_labels+=("--node-label=node.home-k8s.io/rpi-version=rpi$RPI_VERSION")
        node_labels+=("--node-label=hardware.home-k8s.io/type=raspberry-pi-$RPI_VERSION")
    fi

    # Add custom role label for worker (cannot use kubernetes.io namespace during registration)
    node_labels+=("--node-label=node.home-k8s.io/role=worker")

    # Add hostname label
    node_labels+=("--node-label=node.home-k8s.io/hostname=$hostname")

    # K3s agent configuration
    local k3s_opts=(
        "--node-ip=$worker_ip"        # Explicit node IP
        "--data-dir=$DATA_DIR"         # Base data directory
        "${node_labels[@]}"            # Node labels
    )

    print_info "K3s configuration:"
    echo "  - Channel: $K3S_CHANNEL"
    echo "  - Master IP: $MASTER_IP"
    echo "  - Node IP: $worker_ip"
    echo "  - Data dir: $DATA_DIR"
    if [[ -n "$RPI_VERSION" && "$RPI_VERSION" != "unknown" ]]; then
        echo "  - RPi Version: $RPI_VERSION"
    fi
    echo "  - Node Labels:"
    for label in "${node_labels[@]}"; do
        echo "      ${label#--node-label=}"
    done
    echo ""

    # Download and run K3s installer
    print_info "Downloading K3s installer..."
    curl -sfL https://get.k3s.io | sh -s - ${k3s_opts[@]}

    print_success "K3s agent installed successfully"
}

wait_for_k3s() {
    print_step "Waiting for K3s agent to start..."

    local retries=0
    local max_retries=30

    while [[ $retries -lt $max_retries ]]; do
        if systemctl is-active --quiet k3s-agent; then
            print_success "K3s agent service is active"
            break
        fi

        echo -n "."
        sleep 2
        retries=$((retries + 1))
    done

    echo ""

    if [[ $retries -eq $max_retries ]]; then
        print_error "K3s agent failed to start within timeout"
        print_info "Check logs with: sudo journalctl -u k3s-agent -f"
        exit 1
    fi

    # Give it a few more seconds to fully connect
    print_info "Waiting for agent to connect to master..."
    sleep 5
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "K3s Agent Service Status:"
    systemctl status k3s-agent --no-pager | head -10

    echo ""
    print_info "To verify the worker node has joined the cluster, run on the MASTER node:"
    echo "  kubectl get nodes"
    echo ""
    print_info "You should see this worker node listed with status 'Ready'"
}

display_node_info() {
    print_step "Worker node information..."

    local worker_ip=$(hostname -I | awk '{print $1}')
    local hostname=$(hostname)

    echo ""
    echo "=========================================="
    print_success "K3s Worker Node Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Worker Node Information:"
    echo "  Hostname: $hostname"
    echo "  IP Address: $worker_ip"
    echo "  Master IP: $MASTER_IP"
    if [[ -n "$RPI_VERSION" && "$RPI_VERSION" != "unknown" ]]; then
        echo "  RPi Version: $RPI_VERSION"
    fi
    echo ""
    echo "Data Directory:"
    echo "  Location: $DATA_DIR"
    if [[ -d "$DATA_DIR" ]]; then
        du -sh "$DATA_DIR" 2>/dev/null | awk '{print "  Size: " $1}'
    fi
    echo ""
    echo "Verify cluster status (run on master node):"
    echo "  kubectl get nodes"
    echo "  kubectl get nodes -o wide"
    echo "  kubectl get nodes --show-labels"
    echo ""
    echo "Optional: Add Kubernetes role label (run on master node):"
    echo "  kubectl label node $hostname node-role.kubernetes.io/worker=true"
    echo ""
    echo "Check worker logs:"
    echo "  sudo journalctl -u k3s-agent -f"
    echo ""
    echo "=========================================="
}

check_reboot_required() {
    if [[ "${CGROUPS_MODIFIED:-0}" == "1" ]]; then
        echo ""
        print_warning "A REBOOT IS REQUIRED to complete the installation"
        print_info "cgroups configuration was modified in boot config"
        print_info "After rebooting, verify K3s agent is running with: sudo systemctl status k3s-agent"
        echo ""
        read -p "Reboot now? (y/N): " reboot_now
        if [[ "$reboot_now" == "y" || "$reboot_now" == "Y" ]]; then
            print_info "Rebooting in 5 seconds..."
            sleep 5
            reboot
        fi
    fi
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  K3s Worker Node Installation"
    echo "=========================================="
    echo ""

    # Check we're running as root
    check_root

    # Check and parse arguments
    check_arguments "$@"

    # Check prerequisites
    check_prerequisites

    # Prepare system
    disable_swap
    enable_cgroups

    # Install K3s agent
    install_k3s_agent

    # Wait for K3s agent to be ready
    wait_for_k3s

    # Show installation verification
    verify_installation

    # Display node information
    display_node_info

    # Check if reboot is required
    check_reboot_required

    print_success "Installation script completed!"
}

# Run main function
main "$@"
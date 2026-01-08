#!/bin/bash

#####################################################################
# K3s Master Node Installation Script
#
# This script installs K3s on the master node (Raspberry Pi 5)
# and configures it to use the SSD partition for etcd storage.
#
# Prerequisites:
#   - Run setup-ssd.sh first to partition and mount the SSD
#   - Static IP address configured
#   - Internet connection available
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
ETCD_MOUNT="/var/lib/rancher/k3s/server/db"
DATA_DIR="/var/lib/rancher/k3s"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
TOKEN_PATH="/var/lib/rancher/k3s/server/node-token"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0 $*"
        exit 1
    fi
}

check_prerequisites() {
    print_step "Checking prerequisites..."

    # Check if etcd partition is mounted
    if ! mountpoint -q "$ETCD_MOUNT" 2>/dev/null; then
        print_error "etcd partition is not mounted at $ETCD_MOUNT"
        echo ""
        echo "Please run setup-ssd.sh first to partition and mount the SSD:"
        echo "  sudo ./setup-ssd.sh"
        echo ""
        exit 1
    fi

    # Verify etcd mount has enough space (at least 30GB free)
    local available=$(df -BG "$ETCD_MOUNT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available -lt 30 ]]; then
        print_warning "etcd partition has less than 30GB available ($available GB)"
        read -p "Continue anyway? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            exit 0
        fi
    fi

    print_success "etcd partition mounted at $ETCD_MOUNT (${available}GB available)"

    # Check for static IP
    local ip_addr=$(hostname -I | awk '{print $1}')
    print_info "Master node IP: $ip_addr"

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
        /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
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

install_k3s() {
    print_step "Installing K3s on master node..."

    local master_ip=$(hostname -I | awk '{print $1}')

    # K3s installation options
    export INSTALL_K3S_CHANNEL="$K3S_CHANNEL"
    export K3S_KUBECONFIG_MODE="644"
    export INSTALL_K3S_EXEC="server"

    # K3s server configuration
    local k3s_opts=(
        "--disable traefik"                    # We use Kourier (Knative ingress) instead
        "--disable servicelb"                  # We use NodePort + external nginx
        "--write-kubeconfig-mode=644"          # Make kubeconfig readable
        "--node-ip=$master_ip"                 # Explicit node IP
        "--advertise-address=$master_ip"       # Advertise this IP
        "--data-dir=$DATA_DIR"                 # Base data directory
        "--tls-san=$master_ip"                 # Add IP to TLS SAN
    )

    print_info "K3s configuration:"
    echo "  - Channel: $K3S_CHANNEL"
    echo "  - Node IP: $master_ip"
    echo "  - Data dir: $DATA_DIR"
    echo "  - etcd dir: $ETCD_MOUNT"
    echo "  - Traefik: disabled (using Kourier for Knative)"
    echo "  - ServiceLB: disabled (using NodePort + nginx)"
    echo ""

    # Download and run K3s installer
    print_info "Downloading K3s installer..."
    curl -sfL https://get.k3s.io | sh -s - ${k3s_opts[@]}

    print_success "K3s installed successfully"
}

wait_for_k3s() {
    print_step "Waiting for K3s to start..."

    local retries=0
    local max_retries=30

    while [[ $retries -lt $max_retries ]]; do
        if systemctl is-active --quiet k3s; then
            print_success "K3s service is active"
            break
        fi

        echo -n "."
        sleep 2
        retries=$((retries + 1))
    done

    echo ""

    if [[ $retries -eq $max_retries ]]; then
        print_error "K3s failed to start within timeout"
        print_info "Check logs with: sudo journalctl -u k3s -f"
        exit 1
    fi

    # Wait for node to be ready
    print_info "Waiting for node to be ready..."
    retries=0
    while [[ $retries -lt $max_retries ]]; do
        if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
            print_success "Node is ready"
            break
        fi

        echo -n "."
        sleep 2
        retries=$((retries + 1))
    done

    echo ""

    if [[ $retries -eq $max_retries ]]; then
        print_error "Node failed to become ready within timeout"
        exit 1
    fi
}

setup_kubeconfig() {
    print_step "Setting up kubeconfig..."

    # For root user
    mkdir -p /root/.kube
    cp "$KUBECONFIG_PATH" /root/.kube/config
    chmod 600 /root/.kube/config

    # For the user who invoked sudo (if applicable)
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        local user_home=$(eval echo ~$SUDO_USER)
        mkdir -p "$user_home/.kube"
        cp "$KUBECONFIG_PATH" "$user_home/.kube/config"
        chown -R "$SUDO_USER:$SUDO_USER" "$user_home/.kube"
        chmod 600 "$user_home/.kube/config"
        print_success "Kubeconfig copied to $user_home/.kube/config"
    fi

    print_success "Kubeconfig configured"
}

verify_etcd_storage() {
    print_step "Verifying etcd storage location..."

    # Wait a moment for etcd to initialize
    sleep 5

    # Check if etcd data directory exists on the SSD
    if [[ -d "$ETCD_MOUNT/member" ]]; then
        local etcd_size=$(du -sh "$ETCD_MOUNT/member" 2>/dev/null | awk '{print $1}')
        print_success "etcd data found on SSD: $etcd_size"
    else
        print_warning "etcd data directory not yet created (this is normal on first start)"
    fi

    # Show disk usage
    print_info "SSD partition usage:"
    df -h "$ETCD_MOUNT" | tail -1
}

display_node_info() {
    print_step "Master node information..."

    local master_ip=$(hostname -I | awk '{print $1}')
    local node_token=$(cat "$TOKEN_PATH" 2>/dev/null || echo "Token not yet available")

    echo ""
    echo "=========================================="
    print_success "K3s Master Node Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Master Node Information:"
    echo "  IP Address: $master_ip"
    echo "  Node Token: $node_token"
    echo ""
    echo "Kubeconfig location:"
    echo "  $KUBECONFIG_PATH"
    echo ""
    echo "etcd Storage:"
    echo "  Location: $ETCD_MOUNT"
    df -h "$ETCD_MOUNT" | tail -1 | awk '{print "  Used: " $3 " / " $2 " (" $5 ")"}'
    echo ""
    echo "To join worker nodes, run on each worker:"
    echo "  curl -sfL https://get.k3s.io | K3S_URL=https://$master_ip:6443 \\"
    echo "    K3S_TOKEN=$node_token sh -"
    echo ""
    echo "Or use the install-worker.sh script:"
    echo "  ./install-worker.sh $master_ip $node_token"
    echo ""
    echo "Copy kubeconfig to your local machine:"
    echo "  scp pi@$master_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
    echo "  sed -i 's/127.0.0.1/$master_ip/g' ~/.kube/config"
    echo ""
    echo "Verify installation:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo ""
    echo "=========================================="
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Cluster Status:"
    kubectl get nodes -o wide

    echo ""
    echo "System Pods:"
    kubectl get pods -n kube-system

    echo ""
    echo "K3s Service Status:"
    systemctl status k3s --no-pager | head -10
}

check_reboot_required() {
    if [[ "${CGROUPS_MODIFIED:-0}" == "1" ]]; then
        echo ""
        print_warning "A REBOOT IS REQUIRED to complete the installation"
        print_info "cgroups configuration was modified in boot config"
        print_info "After rebooting, verify K3s is running with: sudo systemctl status k3s"
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
    echo "  K3s Master Node Installation"
    echo "=========================================="
    echo ""

    # Check we're running as root
    check_root

    # Check prerequisites
    check_prerequisites

    # Prepare system
    disable_swap
    enable_cgroups

    # Install K3s
    install_k3s

    # Wait for K3s to be ready
    wait_for_k3s

    # Setup kubeconfig
    setup_kubeconfig

    # Verify etcd is using SSD
    verify_etcd_storage

    # Show installation verification
    verify_installation

    # Display node information and join command
    display_node_info

    # Check if reboot is required
    check_reboot_required

    print_success "Installation script completed!"
}

# Run main function
main "$@"

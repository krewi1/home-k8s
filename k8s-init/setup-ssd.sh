, and photo books.#!/bin/bash

#####################################################################
# SSD Partitioning Script for K3s Master Node
#
# This script partitions a 1TB SSD into:
#   - 40GB for etcd (K3s database)
#   - 100GB for PersistentVolumeClaims (K8s storage)
#   - ~860GB for MinIO (object storage)
#
# WARNING: This will DESTROY ALL DATA on the target disk!
#          Make absolutely sure you specify the correct device.
#####################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ETCD_SIZE="40G"
PVC_SIZE="100G"
ETCD_MOUNT="/var/lib/rancher/k3s/server/db"
PVC_MOUNT="/mnt/k8s-pvc"
MINIO_MOUNT="/mnt/minio-data"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0 $*"
        exit 1
    fi
}

detect_ssd() {
    print_info "Detecting available storage devices..."
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
    echo ""
}

confirm_device() {
    local device=$1

    if [[ ! -b "$device" ]]; then
        print_error "Device $device does not exist or is not a block device"
        exit 1
    fi

    # Get device information
    local size=$(lsblk -b -d -n -o SIZE "$device" | awk '{print $1}')
    local size_gb=$((size / 1024 / 1024 / 1024))
    local model=$(lsblk -d -n -o MODEL "$device" 2>/dev/null || echo "Unknown")

    print_warning "You are about to partition the following device:"
    echo "  Device: $device"
    echo "  Size: ${size_gb}GB"
    echo "  Model: $model"
    echo ""
    echo "This will create:"
    echo "  - Partition 1: ${ETCD_SIZE} for etcd at ${ETCD_MOUNT}"
    echo "  - Partition 2: ${PVC_SIZE} for PVCs at ${PVC_MOUNT}"
    echo "  - Partition 3: ~$((size_gb - 140))GB for MinIO at ${MINIO_MOUNT}"
    echo ""
    print_error "ALL DATA ON THIS DEVICE WILL BE DESTROYED!"
    echo ""

    read -p "Type 'YES' to continue (anything else will abort): " confirmation
    if [[ "$confirmation" != "YES" ]]; then
        print_info "Operation cancelled by user"
        exit 0
    fi
}

check_mounted() {
    local device=$1
    if mount | grep -q "^${device}"; then
        print_warning "Device or its partitions are currently mounted"
        print_info "Attempting to unmount..."

        # Unmount all partitions
        for partition in ${device}*[0-9]; do
            if mount | grep -q "^${partition}"; then
                umount "$partition" 2>/dev/null || {
                    print_error "Failed to unmount $partition"
                    print_info "Please unmount manually and try again"
                    exit 1
                }
                print_success "Unmounted $partition"
            fi
        done
    fi
}

partition_disk() {
    local device=$1
    local pvc_end="140G"  # 40GB + 100GB

    print_info "Wiping existing partition table..."
    wipefs -a "$device" >/dev/null 2>&1 || true

    print_info "Creating new GPT partition table..."
    parted -s "$device" mklabel gpt

    print_info "Creating partition 1 (${ETCD_SIZE} for etcd)..."
    parted -s "$device" mkpart primary ext4 0% "$ETCD_SIZE"

    print_info "Creating partition 2 (${PVC_SIZE} for PVCs)..."
    parted -s "$device" mkpart primary ext4 "$ETCD_SIZE" "$pvc_end"

    print_info "Creating partition 3 (remaining space for MinIO)..."
    parted -s "$device" mkpart primary ext4 "$pvc_end" 100%

    # Wait for kernel to recognize new partitions
    partprobe "$device"
    sleep 2

    print_success "Partitions created successfully"
}

format_partitions() {
    local device=$1
    local part1="${device}1"
    local part2="${device}2"
    local part3="${device}3"

    # Handle different device naming conventions
    if [[ $device == /dev/nvme* ]]; then
        part1="${device}p1"
        part2="${device}p2"
        part3="${device}p3"
    fi

    print_info "Formatting partition 1 (etcd) as ext4..." >&2
    mkfs.ext4 -F -L "k3s-etcd" "$part1" >&2

    print_info "Formatting partition 2 (PVC) as ext4..." >&2
    mkfs.ext4 -F -L "k8s-pvc" "$part2" >&2

    print_info "Formatting partition 3 (MinIO) as ext4..." >&2
    mkfs.ext4 -F -L "minio-data" "$part3" >&2

    print_success "Partitions formatted successfully" >&2

    # Return partition names for use in mounting
    echo "$part1 $part2 $part3"
}

create_mount_points() {
    print_info "Creating mount points..."

    # Create etcd mount point
    if [[ ! -d "$ETCD_MOUNT" ]]; then
        mkdir -p "$ETCD_MOUNT"
        print_success "Created $ETCD_MOUNT"
    fi

    # Create PVC mount point
    if [[ ! -d "$PVC_MOUNT" ]]; then
        mkdir -p "$PVC_MOUNT"
        print_success "Created $PVC_MOUNT"
    fi

    # Create MinIO mount point
    if [[ ! -d "$MINIO_MOUNT" ]]; then
        mkdir -p "$MINIO_MOUNT"
        print_success "Created $MINIO_MOUNT"
    fi
}

mount_partitions() {
    local part1=$1
    local part2=$2
    local part3=$3

    print_info "Mounting partitions..."

    # Mount etcd partition
    mount "$part1" "$ETCD_MOUNT"
    print_success "Mounted $part1 to $ETCD_MOUNT"

    # Mount PVC partition
    mount "$part2" "$PVC_MOUNT"
    print_success "Mounted $part2 to $PVC_MOUNT"

    # Mount MinIO partition
    mount "$part3" "$MINIO_MOUNT"
    print_success "Mounted $part3 to $MINIO_MOUNT"

    # Set permissions
    chmod 755 "$PVC_MOUNT"
    chown -R 1000:1000 "$MINIO_MOUNT"
    chmod 755 "$MINIO_MOUNT"
}

update_fstab() {
    local part1=$1
    local part2=$2
    local part3=$3

    print_info "Updating /etc/fstab for persistent mounts..."

    # Get UUIDs
    local uuid1=$(blkid -s UUID -o value "$part1")
    local uuid2=$(blkid -s UUID -o value "$part2")
    local uuid3=$(blkid -s UUID -o value "$part3")

    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

    # Remove any existing entries for these mount points
    sed -i "\|$ETCD_MOUNT|d" /etc/fstab
    sed -i "\|$PVC_MOUNT|d" /etc/fstab
    sed -i "\|$MINIO_MOUNT|d" /etc/fstab

    # Add new entries
    cat >> /etc/fstab <<EOF

# K3s etcd storage
UUID=$uuid1  $ETCD_MOUNT  ext4  defaults,noatime  0  2

# K8s PersistentVolumeClaims storage
UUID=$uuid2  $PVC_MOUNT  ext4  defaults,noatime  0  2

# MinIO object storage
UUID=$uuid3  $MINIO_MOUNT  ext4  defaults,noatime  0  2
EOF

    print_success "Updated /etc/fstab"
    print_info "Backup saved to /etc/fstab.backup.*"
}

verify_setup() {
    print_info "Verifying setup..."
    echo ""

    df -h "$ETCD_MOUNT" "$PVC_MOUNT" "$MINIO_MOUNT"
    echo ""

    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL
    echo ""

    print_success "Verification complete"
}

show_summary() {
    echo ""
    echo "=========================================="
    print_success "SSD Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Partition Summary:"
    echo "  etcd:  $ETCD_MOUNT (${ETCD_SIZE})"
    echo "  PVC:   $PVC_MOUNT (${PVC_SIZE})"
    echo "  MinIO: $MINIO_MOUNT (remaining space)"
    echo ""
    echo "Next Steps:"
    echo "  1. Run install-master.sh to install K3s"
    echo "     (K3s will automatically use $ETCD_MOUNT)"
    echo ""
    echo "  2. Configure K8s to use $PVC_MOUNT for PVCs"
    echo "     (Set up local-path-provisioner or similar)"
    echo ""
    echo "  3. Deploy MinIO to k8s-infrastructure"
    echo "     (Configure to use $MINIO_MOUNT)"
    echo ""
    echo "  4. Verify mounts persist after reboot:"
    echo "     sudo reboot"
    echo "     df -h | grep -E 'etcd|pvc|minio'"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  K3s Master Node SSD Setup"
    echo "=========================================="
    echo ""

    # Check we're running as root
    check_root

    # Show available devices
    detect_ssd

    # Get device from user
    read -p "Enter the device path (e.g., /dev/sda or /dev/nvme0n1): " DEVICE

    # Validate and confirm
    confirm_device "$DEVICE"

    # Check if device is mounted
    check_mounted "$DEVICE"

    # Partition the disk
    partition_disk "$DEVICE"

    # Format partitions and get partition names
    partitions=$(format_partitions "$DEVICE")
    part1=$(echo $partitions | awk '{print $1}')
    part2=$(echo $partitions | awk '{print $2}')
    part3=$(echo $partitions | awk '{print $3}')

    # Create mount points
    create_mount_points

    # Mount partitions
    mount_partitions "$part1" "$part2" "$part3"

    # Update fstab
    update_fstab "$part1" "$part2" "$part3"

    # Verify
    verify_setup

    # Show summary
    show_summary
}

# Run main function
main "$@"

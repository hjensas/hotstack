#!/bin/bash
# Copyright Red Hat, Inc.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Setup and configure host prerequisites for hotstack-os

set -e

# Source common utilities
# shellcheck source=scripts/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

echo "=== HotStack-OS Host Setup ==="

# Check for root privileges
require_root

# Load .env configuration
load_env_file

# Install required packages
echo "Installing required packages..."

# Setup required repositories (CentOS only)
if is_centos; then
    echo "Setting up required repositories..."
    setup_epel_repository
    setup_nfv_repository
fi

check_and_queue_package "libvirt"
check_and_queue_package "qemu-kvm"
check_and_queue_package "podman"
check_and_queue_package "podman-compose"
check_and_queue_package "make"
check_and_queue_package "nmap-ncat"
check_and_queue_package "nfs-utils"
if is_centos; then
    check_and_queue_package "openvswitch3.5"
else
    check_and_queue_package "openvswitch"
fi

install_queued_packages

# Check for network subnet conflicts
echo -n "Checking network availability... "
SUBNET_IN_USE=0
check_podman_network_conflicts && SUBNET_IN_USE=1
check_host_ip_conflicts && SUBNET_IN_USE=1

if [ $SUBNET_IN_USE -eq 1 ]; then
    echo -e "${RED}ERROR${NC}"
    echo "  Note: hotstack-os uses 172.31.0.0/24 (split: /25 containers, /25 provider)"
    echo "  If needed, change subnets in podman-compose.yml and setup-host.sh"
else
    echo -e "${GREEN}✓${NC}"
fi

# Enable and start required services
echo "Configuring required services..."

# Setup libvirt services
setup_libvirt_services || exit 1
verify_libvirt || exit 1

# Setup OpenvSwitch service
setup_openvswitch_service || exit 1

# Setup NFS server for Cinder
setup_nfs_server || exit 1

# Setup network infrastructure
add_ovs_bridges || exit 1

# Setup firewall zones and /etc/hosts entries
add_firewall_zones || exit 1
add_hosts_entries || exit 1

# Create system directories for Nova and Cinder
echo "Setting up system directories..."
setup_directory "$HOTSTACK_DATA_DIR" "Data directory" || exit 1
# Nova instances directory needs qemu:qemu ownership for libvirt access
setup_directory "$NOVA_INSTANCES_PATH" "Nova instances directory" "qemu:qemu" || exit 1
# Set setgid bit and group-writable so nova-compute can create subdirs that qemu can access
chmod 2775 "$NOVA_INSTANCES_PATH"
# Set SELinux context for libvirt access
if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t virt_var_lib_t "$NOVA_INSTANCES_PATH(/.*)?" 2>/dev/null || true
    restorecon -R "$NOVA_INSTANCES_PATH" 2>/dev/null || true
fi
# Nova mount directory for NFS volume attachments (needs root:root for mounting)
setup_directory "$NOVA_NFS_MOUNT_POINT_BASE" "Nova NFS mount directory" "root:root" || exit 1
chmod 755 "$NOVA_NFS_MOUNT_POINT_BASE"
# Set SELinux context for libvirt access to mounted volumes
if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t virt_var_lib_t "$NOVA_NFS_MOUNT_POINT_BASE(/.*)?" 2>/dev/null || true
    restorecon -R "$NOVA_NFS_MOUNT_POINT_BASE" 2>/dev/null || true
fi
echo -e "${GREEN}✓ Host setup complete!${NC} Next: make build && make start"

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

# Setup host configuration for podman-compose deployment
# Note: This script assumes dependencies are already installed via install-deps.sh

set -e

# Source common utilities
# shellcheck source=scripts/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

echo "=== HotStack-OS Host Setup (podman-compose) ==="

# Check for root privileges
require_root

# Load .env configuration
load_env_file

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

# Setup network infrastructure
add_ovs_bridges || exit 1

# Setup firewall zones and host records
add_firewall_zones || exit 1
add_hosts_entries || exit 1

# Setup NFS exports for Cinder
setup_nfs_exports || exit 1

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
echo ""
echo "========================================"
echo "Host setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Start services: sudo make start"
echo ""

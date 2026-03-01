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

# HotStack-OS Infrastructure Setup Script
# Sets up network (OVS bridges, /etc/hosts) and storage (NFS exports) for systemd deployment
# This script is idempotent and safe to run multiple times

set -e

# Environment variables are passed by systemd service unit
# Default values if not set (for standalone testing)
BREX_IP=${BREX_IP:-172.31.0.129}
PROVIDER_NETWORK=${PROVIDER_NETWORK:-172.31.0.128/25}
CONTAINER_NETWORK=${CONTAINER_NETWORK:-172.31.0.0/25}

# /etc/hosts markers
HOSTS_FILE="/etc/hosts"
HOSTS_BEGIN_MARKER="# BEGIN hotstack-os managed entries"
HOSTS_END_MARKER="# END hotstack-os managed entries"

# NFS exports markers
NFS_EXPORTS_FILE="/etc/exports"
NFS_EXPORTS_BEGIN_MARKER="# BEGIN hotstack-os managed exports"
NFS_EXPORTS_END_MARKER="# END hotstack-os managed exports"
CINDER_NFS_EXPORT_DIR="${CINDER_NFS_EXPORT_DIR:-/var/lib/hotstack-os/cinder-nfs}"

# Service data directories to create
# NOTE: For systemd deployment, all directories must exist before podman run
# (unlike podman-compose which creates them automatically)
SERVICE_DATA_DIRS=(
    "mysql"
    "rabbitmq"
    "keystone/fernet-keys"
    "keystone/credential-keys"
    "glance/images"
    "nova"
    "nova-instances"
    "nova-mnt"
    "ovn"
    "ovn-run"
    "cinder"
)

echo "=== HotStack-OS Infrastructure Setup ==="

# Create Podman network for containers
echo "Setting up Podman network..."
if podman network exists hotstack-os 2>/dev/null; then
    echo "✓ Podman network 'hotstack-os' already exists"
else
    echo "  Creating Podman network 'hotstack-os' with subnet $CONTAINER_NETWORK..."
    podman network create --subnet="$CONTAINER_NETWORK" hotstack-os
    echo "✓ Podman network 'hotstack-os' created"
fi

# Check OVS is functional
if ! ovs-vsctl show &>/dev/null; then
    echo "ERROR: OVS is not functional"
    exit 1
fi
echo "✓ OVS is functional"

# Create hot-int bridge if it doesn't exist
if ovs-vsctl br-exists hot-int; then
    echo "✓ hot-int bridge exists"
else
    echo "Creating hot-int bridge..."
    ovs-vsctl --may-exist add-br hot-int
    echo "✓ hot-int bridge created"
fi

# Create hot-ex bridge if it doesn't exist
if ovs-vsctl br-exists hot-ex; then
    echo "✓ hot-ex bridge exists"
else
    echo "Creating hot-ex bridge..."
    ovs-vsctl --may-exist add-br hot-ex
    echo "✓ hot-ex bridge created"
fi

# Assign IP to hot-ex bridge internal interface
if ip addr show hot-ex | grep -q "$BREX_IP"; then
    echo "✓ hot-ex already has IP $BREX_IP configured"
else
    echo "Assigning IP $BREX_IP to hot-ex bridge..."
    ip addr add "${BREX_IP}/25" dev hot-ex
    ip link set hot-ex up
    echo "✓ Assigned IP $BREX_IP to hot-ex bridge"
fi

# Ensure hot-ex is up
ip link set hot-ex up

echo "✓ hot-ex configured for provider networks ($PROVIDER_NETWORK)"

# Configure /etc/hosts entries
echo "Configuring /etc/hosts for OpenStack service access..."

# Remove old hotstack-os entries if they exist
if grep -q "$HOSTS_BEGIN_MARKER" "$HOSTS_FILE"; then
    echo "  Removing old hotstack-os entries..."
    sed -i "/$HOSTS_BEGIN_MARKER/,/$HOSTS_END_MARKER/d" "$HOSTS_FILE"
fi

# Add new entries
echo "  Adding hotstack-os service entries for $BREX_IP..."
cat >> "$HOSTS_FILE" <<EOF
$HOSTS_BEGIN_MARKER
$BREX_IP keystone.hotstack-os.local
$BREX_IP glance.hotstack-os.local
$BREX_IP placement.hotstack-os.local
$BREX_IP nova.hotstack-os.local
$BREX_IP neutron.hotstack-os.local
$BREX_IP cinder.hotstack-os.local
$BREX_IP heat.hotstack-os.local
$HOSTS_END_MARKER
EOF

echo "✓ /etc/hosts updated with OpenStack service FQDNs"

# Configure NFS exports for Cinder
echo "Configuring NFS exports for Cinder..."

# Create export directory if it doesn't exist
if [ ! -d "$CINDER_NFS_EXPORT_DIR" ]; then
    echo "  Creating NFS export directory..."
    mkdir -p "$CINDER_NFS_EXPORT_DIR"
    chown root:root "$CINDER_NFS_EXPORT_DIR"
    chmod 0755 "$CINDER_NFS_EXPORT_DIR"
fi

# Remove old exports if they exist
if grep -q "$NFS_EXPORTS_BEGIN_MARKER" "$NFS_EXPORTS_FILE" 2>/dev/null; then
    echo "  Removing old NFS exports..."
    sed -i "/$NFS_EXPORTS_BEGIN_MARKER/,/$NFS_EXPORTS_END_MARKER/d" "$NFS_EXPORTS_FILE"
fi

# Add new export entry
echo "  Adding NFS export for $CINDER_NFS_EXPORT_DIR..."
cat >> "$NFS_EXPORTS_FILE" <<EOF

$NFS_EXPORTS_BEGIN_MARKER
$CINDER_NFS_EXPORT_DIR 127.0.0.1(rw,sync,no_root_squash,no_subtree_check)
$NFS_EXPORTS_END_MARKER
EOF

# Export the shares
echo "  Exporting NFS shares..."
exportfs -ra

echo "✓ NFS exports configured"

# Create required data directories for services
echo "Creating service data directories..."
HOTSTACK_DATA_DIR="${HOTSTACK_DATA_DIR:-/var/lib/hotstack-os}"
NOVA_INSTANCES_PATH="${NOVA_INSTANCES_PATH:-${HOTSTACK_DATA_DIR}/nova-instances}"
NOVA_NFS_MOUNT_POINT_BASE="${NOVA_NFS_MOUNT_POINT_BASE:-${HOTSTACK_DATA_DIR}/nova-mnt}"

# Create directories needed by services (only if they don't exist)
for dir in "${SERVICE_DATA_DIRS[@]}"; do
    if [ ! -d "$HOTSTACK_DATA_DIR/$dir" ]; then
        mkdir -p "$HOTSTACK_DATA_DIR/$dir"
    fi
done

# Set ownership only on the base directory (not recursive to preserve service-specific permissions)
chown root:root "$HOTSTACK_DATA_DIR"
chmod 755 "$HOTSTACK_DATA_DIR"

# Nova instances directory needs special handling for libvirt access
echo "Configuring Nova instances directory for libvirt..."
chown qemu:qemu "$NOVA_INSTANCES_PATH"
# Set setgid bit and group-writable so nova-compute can create subdirs that qemu can access
chmod 2775 "$NOVA_INSTANCES_PATH"

# Set SELinux context for libvirt access
if command -v semanage >/dev/null 2>&1; then
    echo "  Setting SELinux context for Nova instances..."
    semanage fcontext -a -t virt_var_lib_t "$NOVA_INSTANCES_PATH(/.*)?" 2>/dev/null || true
    restorecon -R "$NOVA_INSTANCES_PATH" 2>/dev/null || true
fi

# Nova mount directory for NFS volume attachments (needs root:root for mounting)
chown root:root "$NOVA_NFS_MOUNT_POINT_BASE"
chmod 755 "$NOVA_NFS_MOUNT_POINT_BASE"

# Set SELinux context for libvirt access to mounted volumes
if command -v semanage >/dev/null 2>&1; then
    echo "  Setting SELinux context for Nova mounts..."
    semanage fcontext -a -t virt_var_lib_t "$NOVA_NFS_MOUNT_POINT_BASE(/.*)?" 2>/dev/null || true
    restorecon -R "$NOVA_NFS_MOUNT_POINT_BASE" 2>/dev/null || true
fi

echo "✓ Service data directories created with proper permissions and SELinux context"

echo "=== Infrastructure Setup Complete ==="
exit 0

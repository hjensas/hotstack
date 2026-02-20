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
# Complete cleanup: containers, data, NFS, and host infrastructure

set -e

# Source common utilities
# shellcheck source=scripts/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# Check for root privileges
require_root

# Load .env to get paths (optional, won't error if missing)
if [ -f .env ]; then
    # shellcheck source=.env
    # shellcheck disable=SC1091
    source .env
fi

# Constants are now defined in common.sh

echo -e "${RED}=== Complete system cleanup ===${NC}"
echo ""

echo "Stopping containers..."
podman-compose down -v || true
echo -e "All containers stopped ${GREEN}✓${NC}"

echo -n "Cleaning libvirt VMs... "
remove_libvirt_vms 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Cleaning network namespaces... "
remove_network_namespaces 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Cleaning storage state... "
cleanup_storage_state 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Cleaning NFS exports... "
cleanup_nfs_exports 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Cleaning data directories... "
if [ -d "$HOTSTACK_DATA_DIR" ]; then
    find "$HOTSTACK_DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
fi
rm -f clouds.yaml 2>/dev/null || true
rm -rf /run/ovn/* 2>/dev/null || true
# Clean Nova instances directory (only if using default path under HOTSTACK_DATA_DIR)
if [[ "$NOVA_INSTANCES_PATH" == "${HOTSTACK_DATA_DIR}"* ]] && [ -d "$NOVA_INSTANCES_PATH" ]; then
    find "${NOVA_INSTANCES_PATH:?}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
fi
# Clean Nova NFS mount directory (only if using default path under HOTSTACK_DATA_DIR)
if [[ "$NOVA_NFS_MOUNT_POINT_BASE" == "${HOTSTACK_DATA_DIR}"* ]] && [ -d "$NOVA_NFS_MOUNT_POINT_BASE" ]; then
    find "$NOVA_NFS_MOUNT_POINT_BASE" -mindepth 1 -maxdepth 1 -exec umount -f {} \; 2>/dev/null || true
    find "$NOVA_NFS_MOUNT_POINT_BASE" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
fi
echo -e "${GREEN}✓${NC}"

echo -n "Removing OVS bridges... "
remove_ovs_bridges 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Removing /etc/hosts entries... "
remove_hosts_entries 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "Removing firewall zones... "
remove_firewall_zones 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo ""
echo -e "${GREEN}Complete!${NC} To rebuild: make setup && make build && make start"

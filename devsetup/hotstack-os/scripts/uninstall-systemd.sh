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

set -euo pipefail

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

echo "Uninstalling HotStack-OS systemd services..."
echo ""

# Stop and disable target
echo "Stopping services..."
systemctl stop hotstack-os.target 2>/dev/null || true
systemctl disable hotstack-os.target 2>/dev/null || true
echo "  ✓ Services stopped"
echo ""

# Remove systemd units
echo "Removing systemd units..."
rm -f /etc/systemd/system/hotstack-os*.service
rm -f /etc/systemd/system/hotstack-os.target
echo "  ✓ Removed systemd units"
echo ""

# Remove helper scripts
echo "Removing helper scripts..."
rm -f /usr/local/bin/hotstack-os-infra-setup.sh
rm -f /usr/local/bin/hotstack-os-infra-cleanup.sh
rm -f /usr/local/bin/hotstack-healthcheck.sh
echo "  ✓ Removed helper scripts"
echo ""

# Reload systemd
echo "Reloading systemd..."
systemctl daemon-reload
echo "  ✓ Systemd reloaded"
echo ""

echo "========================================"
echo "Uninstall complete!"
echo "========================================"
echo ""
echo "Note: Podman resources (network, volumes) and data in"
echo "/var/lib/hotstack-os were not removed. To clean up:"
echo "  podman network rm hotstack-os"
echo "  podman volume rm hotstack-os-ovn-run"
echo "  sudo rm -rf /var/lib/hotstack-os"
echo ""

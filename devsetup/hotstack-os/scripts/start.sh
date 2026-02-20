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

# Convenient startup script for hotstack-os

set -e
set -o pipefail

# Source common utilities
# shellcheck source=scripts/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

echo "=== Starting HotStack-OS ==="

# Load environment configuration
load_env_file

# Auto-detect chassis hostname if not set (needed for OVN controller registration)
if [ -z "$CHASSIS_HOSTNAME" ]; then
    CHASSIS_HOSTNAME=$(hostname)
    export CHASSIS_HOSTNAME
    echo "Auto-detected chassis hostname: $CHASSIS_HOSTNAME"
fi

# Create all data directories (constants from common.sh)
# NOTE: mysql directory is NOT created here - MariaDB must create it for init scripts to run
setup_directory "$HOTSTACK_DATA_DIR/rabbitmq" "RabbitMQ data" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/ovn" "OVN data" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/glance/images" "Glance images" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/keystone/fernet-keys" "Keystone fernet keys" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/keystone/credential-keys" "Keystone credential keys" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/cinder" "Cinder data" || exit 1
setup_directory "$HOTSTACK_DATA_DIR/nova" "Nova data" || exit 1

# Clean up any stopped containers to avoid name conflicts
echo -n "Cleaning stopped containers... "
podman-compose down 2>/dev/null || true
echo -e "${GREEN}✓${NC}"

# Start all services - let podman-compose handle orchestration via depends_on
echo "Starting services (this may take a few minutes)..."
podman-compose up -d

echo ""
echo -e "${GREEN}Services started!${NC} Check status: make status"

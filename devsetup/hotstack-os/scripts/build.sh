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

# Build all HotStack-OS container images

set -e

# Source common utilities
# shellcheck source=scripts/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

echo "=== Building HotStack-OS Container Images ==="

# Load environment configuration
load_env_file

# Build base images
build_base_builder_image || exit 1
build_base_runtime_image || exit 1

# Build service images
build_service_images || exit 1

echo -e "\n${GREEN}Build complete!${NC}"
echo -e "Next steps:"
echo -e "  Podman-Compose: sudo make setup && sudo make start"
echo -e "  Systemd:        sudo make install"

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

# Common utilities for hotstack-os scripts
#
# Usage: source scripts/common.sh

# ============================================================================
# Color Constants
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GREY='\033[0;90m'
NC='\033[0m' # No Color

# ============================================================================
# Path and Infrastructure Constants
# ============================================================================
# Default data directories (can be overridden via .env)
HOTSTACK_DATA_DIR=${HOTSTACK_DATA_DIR:-/var/lib/hotstack-os}
NOVA_INSTANCES_PATH=${NOVA_INSTANCES_PATH:-${HOTSTACK_DATA_DIR}/nova-instances}
NOVA_NFS_MOUNT_POINT_BASE=${NOVA_NFS_MOUNT_POINT_BASE:-${HOTSTACK_DATA_DIR}/nova-mnt}
CINDER_NFS_EXPORT_DIR=${CINDER_NFS_EXPORT_DIR:-${HOTSTACK_DATA_DIR}/cinder-nfs}
# Configuration directories
CONFIGS_DIR="configs"
CONFIGS_RUNTIME_DIR="${HOTSTACK_DATA_DIR}/runtime/config"
SCRIPTS_RUNTIME_DIR="${HOTSTACK_DATA_DIR}/runtime/scripts"

# Hosts file constants
HOSTS_FILE="/etc/hosts"
HOSTS_BACKUP="/etc/hosts.hotstack-backup"
HOSTS_BEGIN_MARKER="# BEGIN hotstack-os managed entries"
HOSTS_END_MARKER="# END hotstack-os managed entries"

# NFS constants
NFS_EXPORTS_FILE="/etc/exports"

# ============================================================================
# Environment Configuration
# ============================================================================

# Initialize variables with defaults from .env.example
# These will be overridden when .env file is sourced
# Note: podman-compose reads these directly from .env file
DB_PASSWORD="openstack"
KEYSTONE_ADMIN_PASSWORD="admin"
SERVICE_PASSWORD="openstack"
RABBITMQ_DEFAULT_USER="openstack"
RABBITMQ_DEFAULT_PASS="openstack"
REGION_NAME="regionOne"

# Load .env file with error handling
# Usage: load_env_file
load_env_file() {
    if [ ! -f .env ]; then
        echo ""
        echo "=========================================================="
        echo "INFO: .env file not found - creating from .env.example"
        echo "=========================================================="
        echo ""
        echo "Using defaults from .env.example"
        echo "Edit .env to customize network, passwords, or storage paths."
        echo ""
        cp .env.example .env
        echo -e "${GREEN}✓${NC} Created .env from .env.example"
        sleep 2
    fi

    # shellcheck source=.env
    # shellcheck disable=SC1091
    source .env
    return 0
}

# ============================================================================
# Directory Management
# ============================================================================

# Setup a directory with proper permissions
# Usage: setup_directory <path> <description> [owner:group]
# Returns: 0 on success, 1 on failure
setup_directory() {
    local dir_path=$1
    local description=$2
    local ownership=$3

    echo -n "$description ($dir_path)... "

    if ! mkdir -p "$dir_path"; then
        echo -e "${RED}✗${NC}"
        return 1
    fi

    # Set ownership if specified
    if [ -n "$ownership" ]; then
        if ! chown -R "$ownership" "$dir_path" 2>/dev/null; then
            echo -e "${YELLOW}⚠${NC} (created, but ownership failed: $ownership)"
            return 1
        fi
    fi

    echo -e "${GREEN}✓${NC}"
    return 0
}

# ============================================================================
# Package Management
# ============================================================================

# Check if package is installed, add to PACKAGES_TO_INSTALL array if not
# Usage: check_and_queue_package <package_name>
# Note: Requires PACKAGES_TO_INSTALL array to be declared before calling
check_and_queue_package() {
    local pkg=$1
    if rpm -q "$pkg" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $pkg is already installed"
    else
        echo -e "${YELLOW}⚠${NC} $pkg needs to be installed"
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
    return 0
}

# Install queued packages
# Usage: install_queued_packages
# Requires: PACKAGES_TO_INSTALL array
install_queued_packages() {
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        echo
        echo "Installing ${#PACKAGES_TO_INSTALL[@]} package(s): ${PACKAGES_TO_INSTALL[*]}"
        dnf install -y "${PACKAGES_TO_INSTALL[@]}"
        echo -e "${GREEN}✓${NC} All packages installed"
    else
        echo -e "${GREEN}✓${NC} All required packages are already installed"
    fi
    return 0
}

# ============================================================================
# Service Management
# ============================================================================

# Check systemd service status
# Usage: check_systemd_service <service_name>
# Returns: 0 if active, 1 otherwise
check_systemd_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}✓${NC} $service_name is already running"
        return 0
    else
        return 1
    fi
}

# Enable and start a systemd service
# Usage: enable_start_service <service_name>
# Returns: 0 on success, 1 on failure
enable_start_service() {
    local service_name=$1

    echo -e "${YELLOW}⚠${NC} Starting $service_name service..."
    systemctl enable "$service_name"
    if systemctl start "$service_name"; then
        if systemctl is-active --quiet "$service_name"; then
            echo -e "${GREEN}✓${NC} $service_name started and enabled"
            return 0
        fi
    fi

    echo -e "${RED}✗${NC} Failed to start $service_name service"
    return 1
}

# Check container service status
# Usage: check_service <service_name> <container_name>
# Returns: 0 if healthy, 1 otherwise
check_service() {
    local service_name=$1
    local container_name=$2

    # Get container status from podman ps -a
    local status
    status=$(podman ps -a --filter "name=^${container_name}$" --format "{{.Status}}")

    if [ -z "$status" ]; then
        echo -e "${RED}✗${NC} $service_name - container does not exist"
        return 1
    fi

    # Parse status - anything not "Up ... (healthy)" or "Up ... (no healthcheck)" is a problem
    if echo "$status" | grep -qE "^Exited|^Created|^Initialized"; then
        echo -e "${RED}✗${NC} $service_name - $status"
        return 1
    elif echo "$status" | grep -q "(unhealthy)"; then
        echo -e "${RED}✗${NC} $service_name - unhealthy"
        return 1
    elif echo "$status" | grep -q "(starting)"; then
        echo -e "${YELLOW}⚠${NC} $service_name - still starting"
        return 1
    else
        echo -e "${GREEN}✓${NC} $service_name"
        return 0
    fi
}

# ============================================================================
# Wait Functions
# ============================================================================

# Wait for a URL to become available
# Usage: wait_for_url <service_name> <url> [max_attempts]
# Returns: 0 on success, 1 on timeout
wait_for_url() {
    local service_name=$1
    local url=$2
    local max_attempts=${3:-30}

    echo "Waiting for $service_name to be ready..."
    for i in $(seq 1 "$max_attempts"); do
        # Get HTTP status code, accept 2xx and 3xx as success
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        if [[ "$http_code" =~ ^[23] ]]; then
            echo -e "${GREEN}✓ $service_name is ready (HTTP $http_code)${NC}"
            return 0
        fi
        echo -e "${GREY}Waiting for $service_name... ($i/$max_attempts)${NC}"
        sleep 2
    done
    echo -e "${RED}✗ $service_name failed to start after $max_attempts attempts${NC}"
    return 1
}

# Wait for a command to succeed
# Usage: wait_for_command <service_name> <check_command> [max_attempts]
# Returns: 0 on success, 1 on timeout
wait_for_command() {
    local service_name=$1
    local check_command=$2
    local max_attempts=${3:-30}

    echo "Waiting for $service_name to be ready..."
    for i in $(seq 1 "$max_attempts"); do
        if eval "$check_command" &>/dev/null; then
            echo -e "${GREEN}✓ $service_name is ready${NC}"
            return 0
        fi
        echo -e "${GREY}Waiting for $service_name... ($i/$max_attempts)${NC}"
        sleep 2
    done
    echo -e "${RED}✗ $service_name failed to start after $max_attempts attempts${NC}"
    return 1
}

# Verify OpenStack CLI functionality
# Usage: verify_openstack_cli
# Returns: 0 if CLI works, 1 otherwise
verify_openstack_cli() {
    if [ ! -f clouds.yaml ]; then
        echo -e "${YELLOW}⚠${NC} clouds.yaml not found - skipping CLI test"
        return 1
    fi

    # Check if openstack command is available
    if ! command -v openstack &>/dev/null; then
        echo -e "${YELLOW}⚠${NC} openstack command not found - install python3-openstackclient"
        echo "  Install: sudo make install-client"
        echo "  Or manually: sudo dnf install -y python3-openstackclient python3-heatclient"
        return 1
    fi

    if openstack --os-cloud hotstack-os-admin endpoint list &>/dev/null; then
        echo -e "${GREEN}✓${NC} OpenStack CLI working"

        # Show service status
        echo
        echo "Registered services:"
        openstack --os-cloud hotstack-os-admin service list -c Name -c Type
        return 0
    else
        echo -e "${RED}✗${NC} OpenStack CLI not working"
        return 1
    fi
}

# Wait for container to be running and stable
# Usage: wait_for_container <service_name> <container_name> [max_attempts]
# Returns: 0 on success, 1 on timeout
wait_for_container() {
    local service_name=$1
    local container_name=$2
    local max_attempts=${3:-15}

    echo "Waiting for $service_name container to be running..."
    for i in $(seq 1 "$max_attempts"); do
        if podman inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null | grep -q "running"; then
            echo -e "${GREEN}✓${NC} $service_name is running"
            return 0
        fi
        echo -e "${GREY}Waiting for $service_name... ($i/$max_attempts)${NC}"
        sleep 2
    done
    echo -e "${RED}✗${NC} $service_name container failed to start"
    return 1
}

# ============================================================================
# Kernel Module Functions
# ============================================================================

# Load KVM kernel module (Intel or AMD)
# Usage: load_kvm_module
# Returns: 0 on success, 1 on failure
load_kvm_module() {
    if lsmod | grep -q "^kvm_intel"; then
        echo -e "${GREEN}✓${NC} Kernel module kvm_intel is already loaded"
        return 0
    elif lsmod | grep -q "^kvm_amd"; then
        echo -e "${GREEN}✓${NC} Kernel module kvm_amd is already loaded"
        return 0
    else
        # Try to detect CPU vendor and load appropriate module
        if grep -q "vendor_id.*GenuineIntel" /proc/cpuinfo; then
            echo -e "${YELLOW}⚠${NC} Loading kvm_intel module..."
            if modprobe kvm_intel; then
                lsmod | grep -q "^kvm_intel" && echo -e "${GREEN}✓${NC} kvm_intel module loaded"
                return 0
            else
                echo -e "${RED}✗${NC} Failed to load kvm_intel module"
                return 1
            fi
        elif grep -q "vendor_id.*AuthenticAMD" /proc/cpuinfo; then
            echo -e "${YELLOW}⚠${NC} Loading kvm_amd module..."
            if modprobe kvm_amd; then
                lsmod | grep -q "^kvm_amd" && echo -e "${GREEN}✓${NC} kvm_amd module loaded"
                return 0
            else
                echo -e "${RED}✗${NC} Failed to load kvm_amd module"
                return 1
            fi
        else
            echo -e "${RED}✗${NC} Cannot detect CPU vendor for KVM module"
            return 1
        fi
    fi
}

# Load OpenvSwitch kernel module
# Usage: load_ovs_module
# Returns: 0 on success, 1 on failure
load_ovs_module() {
    if lsmod | grep -q "^openvswitch"; then
        echo -e "${GREEN}✓${NC} Kernel module openvswitch is already loaded"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Loading openvswitch module..."
        if modprobe openvswitch; then
            lsmod | grep -q "^openvswitch" && echo -e "${GREEN}✓${NC} openvswitch module loaded"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to load openvswitch module"
            return 1
        fi
    fi
}

# ============================================================================
# System Services Functions
# ============================================================================

# Verify libvirt functionality
# Usage: verify_libvirt
# Returns: 0 if functional, 1 otherwise
verify_libvirt() {
    echo "Checking libvirt configuration..."
    if virsh list --all &>/dev/null; then
        echo -e "${GREEN}✓${NC} libvirt is functional"
        return 0
    else
        echo -e "${RED}✗${NC} libvirt is not functional"
        return 1
    fi
}

# Verify KVM support
# Usage: verify_kvm
# Returns: 0 if available, 1 otherwise
verify_kvm() {
    echo "Checking KVM support..."
    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}✓${NC} /dev/kvm exists"
        return 0
    else
        echo -e "${RED}✗${NC} /dev/kvm does not exist - KVM not available"
        echo "  Enable virtualization in BIOS/UEFI"
        return 1
    fi
}

# Setup OpenvSwitch service
# Usage: setup_openvswitch_service
setup_openvswitch_service() {
    if ! check_systemd_service openvswitch; then
        enable_start_service openvswitch || return 1
    fi
    return 0
}

# Setup NFS server for Cinder volumes
# Usage: setup_nfs_server
setup_nfs_server() {
    local service_name="nfs-server"

    echo "Setting up NFS server for Cinder..."

    # Create export directory
    if ! setup_directory "$CINDER_NFS_EXPORT_DIR" "NFS export directory"; then
        return 1
    fi

    # Set permissions: root:root with 0755 (standard for NFS exports)
    chown root:root "$CINDER_NFS_EXPORT_DIR"
    chmod 0755 "$CINDER_NFS_EXPORT_DIR"

    # Configure /etc/exports
    echo -n "Configuring NFS exports... "
    local export_line="$CINDER_NFS_EXPORT_DIR 127.0.0.1(rw,sync,no_root_squash,no_subtree_check)"

    if grep -q "^${CINDER_NFS_EXPORT_DIR} " "$NFS_EXPORTS_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} (already configured)"
    else
        echo "$export_line" >> "$NFS_EXPORTS_FILE"
        echo -e "${GREEN}✓${NC}"
    fi

    # Enable and start NFS server
    if ! check_systemd_service "$service_name"; then
        enable_start_service "$service_name" || return 1
    fi

    # Export the shares
    echo -n "Exporting NFS shares... "
    if exportfs -ra; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi

    # Verify NFS export is accessible
    echo -n "Verifying NFS export... "
    if showmount -e 127.0.0.1 2>/dev/null | grep -q "$CINDER_NFS_EXPORT_DIR"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo "NFS export verification failed - showmount output:"
        showmount -e 127.0.0.1 2>&1 | sed 's/^/  /'
        return 1
    fi

    echo -e "${GREEN}✓${NC} NFS server configured for Cinder"
    echo "  Export: $CINDER_NFS_EXPORT_DIR → 127.0.0.1"
    return 0
}

# Cleanup NFS exports for Cinder
# Usage: cleanup_nfs_exports
cleanup_nfs_exports() {
    # Remove NFS export entry from /etc/exports
    if [ -f "$NFS_EXPORTS_FILE" ] && grep -q "^${CINDER_NFS_EXPORT_DIR} " "$NFS_EXPORTS_FILE" 2>/dev/null; then
        sed -i "\|^${CINDER_NFS_EXPORT_DIR} |d" "$NFS_EXPORTS_FILE"
        exportfs -ra 2>/dev/null || true
    fi

    return 0
}

# Setup libvirt services (modular or legacy)
# Usage: setup_libvirt_services
setup_libvirt_services() {
    # Check for modular libvirt (newer systems)
    if systemctl list-unit-files | grep -q virtqemud.socket; then
        echo "Detected modular libvirt, enabling/starting required daemons..."

        # List of modular libvirt sockets needed for nova-compute
        local libvirt_sockets="virtqemud virtnodedevd virtstoraged virtnetworkd"
        local errors=0

        for daemon in $libvirt_sockets; do
            if ! (systemctl is-active --quiet "${daemon}.socket" || systemctl is-active --quiet "${daemon}"); then
                echo -e "${YELLOW}⚠${NC} Starting ${daemon}..."
                systemctl enable "${daemon}.socket"
                if systemctl start "${daemon}.socket"; then
                    if systemctl is-active --quiet "${daemon}.socket" || systemctl is-active --quiet "${daemon}"; then
                        echo -e "${GREEN}✓${NC} ${daemon} started and enabled"
                    fi
                else
                    echo -e "${RED}✗${NC} Failed to start ${daemon}.socket"
                    errors=$((errors + 1))
                fi
            else
                echo -e "${GREEN}✓${NC} ${daemon} is already running"
            fi
        done

        [ $errors -gt 0 ] && return 1
    else
        # Legacy libvirtd
        if ! check_systemd_service libvirtd; then
            echo -e "${YELLOW}⚠${NC} Starting libvirtd (legacy monolithic)..."
            enable_start_service libvirtd || return 1
        fi
    fi
    return 0
}

# ============================================================================
# Repository Management Functions
# ============================================================================

# Setup EPEL repository (CentOS only)
# Usage: setup_epel_repository
setup_epel_repository() {
    if ! dnf repolist enabled | grep -q epel; then
        echo -e "${YELLOW}⚠${NC} EPEL repository not enabled, installing..."
        dnf install -y epel-release
        echo -e "${GREEN}✓${NC} EPEL repository enabled"
    else
        echo -e "${GREEN}✓${NC} EPEL repository already enabled"
    fi
    return 0
}

# Setup NFV SIG repository for OpenvSwitch (CentOS only)
# Usage: setup_nfv_repository
setup_nfv_repository() {
    if ! dnf repolist enabled | grep -q nfv; then
        echo -e "${YELLOW}⚠${NC} NFV SIG repository not enabled, installing..."
        dnf install -y centos-release-nfv-openvswitch
        echo -e "${GREEN}✓${NC} NFV SIG repository enabled"
    else
        echo -e "${GREEN}✓${NC} NFV SIG repository already enabled"
    fi
    return 0
}

# ============================================================================
# System Detection Functions
# ============================================================================

# Detect operating system (called automatically on source, can be called again if needed)
# Usage: detect_os [quiet]
# Sets: OS_ID, OS_NAME, OS_VERSION global variables
# Exits on error if OS cannot be detected
detect_os() {
    local quiet=${1:-false}

    [ "$quiet" = "false" ] && echo "Detecting operating system..."

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_ID="${ID}"
        OS_NAME="${NAME}"
        OS_VERSION="${VERSION_ID}"
        [ "$quiet" = "false" ] && echo -e "${GREEN}✓${NC} Detected: ${OS_NAME} ${OS_VERSION}"
    else
        echo -e "${RED}✗${NC} Cannot detect OS - /etc/os-release not found"
        exit 1
    fi
    return 0
}

# Check if running CentOS
# Usage: is_centos && ...
# Returns: 0 if CentOS, 1 otherwise
is_centos() {
    [[ "${OS_ID}" == "centos" ]]
}

# Check if running Fedora
# Usage: is_fedora && ...
# Returns: 0 if Fedora, 1 otherwise
is_fedora() {
    [[ "${OS_ID}" == "fedora" ]]
}

# ============================================================================
# Validation Functions
# ============================================================================

# Check if running with root privileges
# Usage: require_root
# Exits with error message if not root
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run with sudo or as root${NC}"
        echo ""
        echo "Run: sudo make setup"
        echo "  or: sudo ./scripts/$(basename "$0")"
        echo ""
        echo "This script requires root privileges to:"
        echo "  - Install system packages (dnf install)"
        echo "  - Start/enable system services (systemctl)"
        echo "  - Load kernel modules (modprobe)"
        echo "  - Configure firewall (firewall-cmd)"
        echo "  - Create system directories (/var/lib/nova/instances)"
        echo "  - Setup NFS server for Cinder (exportfs, nfs-server)"
        echo "  - Add user to libvirt group (usermod)"
        exit 1
    fi
}

# Check if a command exists
# Usage: command_exists <command_name>
# Returns: 0 if exists, 1 otherwise
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if podman networks use 172.31.0.0/24
# Usage: check_podman_network_conflicts
# Returns: 0 if conflict found, 1 if clear
check_podman_network_conflicts() {
    if command -v podman &>/dev/null; then
        if podman network ls --format "{{.Name}} {{.Subnets}}" 2>/dev/null | grep -q "172.31.0"; then
            echo  # Newline to break from "Checking network availability... "
            echo -e "${YELLOW}⚠${NC} 172.31.0.0/24 address space may already be in use by podman"
            echo "  Existing networks using this range:"
            podman network ls --format "table {{.Name}}\t{{.Subnets}}" 2>/dev/null | grep "172.31.0" | sed 's/^/  /'
            return 0
        fi
    fi
    return 1
}

# Check if host has IPs assigned in 172.31.0.0/24
# Usage: check_host_ip_conflicts
# Returns: 0 if conflict found, 1 if clear
check_host_ip_conflicts() {
    # Exclude hotstack-os interfaces (hot-ex, hot-int)
    if ip addr show 2>/dev/null | grep "172.31.0" | grep -v -E "(hot-ex|hot-int)" >/dev/null; then
        echo  # Newline if this is the first message
        echo -e "${YELLOW}⚠${NC} IPs in 172.31.0.0/24 range already assigned on this host"
        echo "  Another network may be using the 172.31.0.0/24 range"
        return 0
    fi
    return 1
}

# ============================================================================
# Error Tracking
# ============================================================================

# Initialize error counter (call at start of script)
# Usage: init_error_counter
init_error_counter() {
    export ERRORS=0
}

# Increment error counter
# Usage: increment_errors [count]
increment_errors() {
    local count=${1:-1}
    export ERRORS=$((ERRORS + count))
}

# Check if any errors occurred and exit with appropriate code
# Usage: exit_with_error_summary
exit_with_error_summary() {
    if [ "${ERRORS:-0}" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Container Build Functions
# ============================================================================

# Build base OpenStack builder container image
# Usage: build_base_builder_image
build_base_builder_image() {
    echo -n "Building base builder image... "
    if ! podman build --target=builder \
        -t localhost/hotstack-os-base-builder:latest \
        -f containerfiles/base-openstack.containerfile \
        containerfiles/ &>/dev/null; then
        echo -e "${RED}✗${NC}"
        return 1
    fi
    echo -e "${GREEN}✓${NC}"
}

# Build base OpenStack runtime container image
# Usage: build_base_runtime_image
build_base_runtime_image() {
    echo -n "Building base runtime image... "
    if ! podman build --target=runtime \
        -t localhost/hotstack-os-base:latest \
        -f containerfiles/base-openstack.containerfile \
        containerfiles/ &>/dev/null; then
        echo -e "${RED}✗${NC}"
        return 1
    fi
    echo -e "${GREEN}✓${NC}"
}

# Build all OpenStack service container images using podman-compose
# Usage: build_service_images
build_service_images() {
    echo "Building service container images (this will take ~8 minutes)..."

    if ! podman-compose build; then
        echo -e "${RED}Build failed!${NC}"
        echo "If you see permission errors, try: podman system reset -f"
        return 1
    fi

    echo -e "${GREEN}✓${NC} All service images built successfully"
}

# ============================================================================
# Configuration Generation Functions
# ============================================================================

# Get upstream DNS servers from /etc/resolv.conf
# Usage: get_upstream_dns_servers
# Returns: Space-separated list of "server=IP" entries for dnsmasq config
get_upstream_dns_servers() {
    grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print "server="$2}' | tr '\n' '\n' || echo "server=8.8.8.8"
}

# Prepare runtime configuration directory
# Usage: prepare_runtime_configs [extra_directories...]
# Example: prepare_runtime_configs "keystone/fernet-keys" "keystone/credential-keys"
prepare_runtime_configs() {
    echo -n "Preparing runtime configs... "
    rm -rf "$CONFIGS_RUNTIME_DIR"
    mkdir -p "$CONFIGS_RUNTIME_DIR"
    cp -r "$CONFIGS_DIR"/* "$CONFIGS_RUNTIME_DIR"/

    # Create any extra directories requested
    for dir in "$@"; do
        mkdir -p "$CONFIGS_RUNTIME_DIR/$dir"
    done

    echo -e "${GREEN}✓${NC}"
}

# Process multiple config files in-place with variable substitution
# Usage: process_config_files <directory> <description> [VAR VALUE] ...
# Example: process_config_files "configs-runtime" "service configs" "DB_PASSWORD" "$DB_PASSWORD" "REGION" "$REGION"
process_config_files() {
    local dir=$1
    local description=$2
    shift 2

    echo -n "Processing ${description}... "

    # Build sed command from remaining arguments (pairs of search/replace)
    local sed_args=""
    while [ $# -gt 1 ]; do
        local search=$1
        local replace=$2
        sed_args+=" -e 's|${search}|${replace}|g'"
        shift 2
    done

    # Execute sed on all config files
    eval "find '$dir' -type f \\( -name '*.conf' -o -name '*.ini' -o -name '*.cfg' -o -name '*.yaml' -o -name '*.example' \\) -exec sed -i $sed_args {} \\;"

    echo -e "${GREEN}✓${NC}"
}

# Prepare all configuration files (high-level convenience function)
# Usage: prepare_all_configs
# Note: Requires environment variables to be loaded first
prepare_all_configs() {
    # RabbitMQ transport URL for oslo.messaging
    local transport_url="rabbit://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672/"

    # Prepare runtime configs
    prepare_runtime_configs "keystone/fernet-keys" "keystone/credential-keys"

    # Copy scripts to runtime directory
    echo -n "Copying container scripts... "
    rm -rf "$SCRIPTS_RUNTIME_DIR"
    mkdir -p "$SCRIPTS_RUNTIME_DIR"
    cp -r containerfiles/scripts/* "$SCRIPTS_RUNTIME_DIR"/
    echo -e "${GREEN}✓${NC}"

    # Get upstream DNS for dnsmasq
    local upstream_dns
    upstream_dns=$(get_upstream_dns_servers)

    # Get the actual hostname for Nova compute service
    # This must match the OVN chassis hostname for port binding to work
    local compute_hostname
    compute_hostname=$(hostname -f 2>/dev/null || hostname)

    # Process ALL config files in one pass
    process_config_files \
        "$CONFIGS_RUNTIME_DIR" \
        "configuration files" \
        "KEYSTONE_DB_PASSWORD" "$DB_PASSWORD" \
        "GLANCE_DB_PASSWORD" "$DB_PASSWORD" \
        "PLACEMENT_DB_PASSWORD" "$DB_PASSWORD" \
        "NOVA_DB_PASSWORD" "$DB_PASSWORD" \
        "NEUTRON_DB_PASSWORD" "$DB_PASSWORD" \
        "CINDER_DB_PASSWORD" "$DB_PASSWORD" \
        "HEAT_DB_PASSWORD" "$DB_PASSWORD" \
        "SERVICE_PASSWORD" "$SERVICE_PASSWORD" \
        "RABBITMQ_USER" "$RABBITMQ_DEFAULT_USER" \
        "RABBITMQ_PASS" "$RABBITMQ_DEFAULT_PASS" \
        "TRANSPORT_URL" "$transport_url" \
        "REGION_NAME" "$REGION_NAME" \
        "BREX_IP" "$BREX_IP" \
        "OVN_NORTHD_IP" "$OVN_NORTHD_IP" \
        "COMPUTE_HOSTNAME" "$compute_hostname" \
        "METADATA_SECRET" "$SERVICE_PASSWORD" \
        "DEBUG_LOGGING" "${DEBUG_LOGGING:-false}" \
        "CINDER_STORAGE_BACKEND" "nfs" \
        "NOVA_INSTANCES_PATH" "$NOVA_INSTANCES_PATH" \
        "NOVA_NFS_MOUNT_POINT_BASE" "$NOVA_NFS_MOUNT_POINT_BASE" \
        "# UPSTREAM_DNS_SERVERS" "$upstream_dns" \
        "MARIADB_IP" "$MARIADB_IP" \
        "RABBITMQ_IP" "$RABBITMQ_IP" \
        "MEMCACHED_IP" "$MEMCACHED_IP" \
        "KEYSTONE_IP" "$KEYSTONE_IP" \
        "GLANCE_IP" "$GLANCE_IP" \
        "PLACEMENT_IP" "$PLACEMENT_IP" \
        "NOVA_API_IP" "$NOVA_API_IP" \
        "NEUTRON_SERVER_IP" "$NEUTRON_SERVER_IP" \
        "CINDER_API_IP" "$CINDER_API_IP" \
        "HEAT_API_IP" "$HEAT_API_IP" \
        "NOVA_NOVNCPROXY_IP" "$NOVA_NOVNCPROXY_IP" \
        "password: admin" "password: ${KEYSTONE_ADMIN_PASSWORD}"

    # Copy clouds.yaml to data directory and repo directory for OpenStack client
    echo -n "Copying clouds.yaml... "
    cp "$CONFIGS_RUNTIME_DIR/clouds.yaml.example" "${HOTSTACK_DATA_DIR}/clouds.yaml"
    cp "${HOTSTACK_DATA_DIR}/clouds.yaml" clouds.yaml
    echo -e "${GREEN}✓${NC}"
}

# ============================================================================
# Host Configuration Functions
# ============================================================================

# Add OpenStack service entries to /etc/hosts
# Usage: add_hosts_entries
# Requires: BREX_IP environment variable
add_hosts_entries() {
    echo "Configuring /etc/hosts for OpenStack service access..."

    # Create backup if it doesn't exist
    if [ ! -f "$HOSTS_BACKUP" ]; then
        cp "$HOSTS_FILE" "$HOSTS_BACKUP"
        echo "  Created backup: $HOSTS_BACKUP"
    fi

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

    echo -e "  ${GREEN}✓${NC} /etc/hosts updated with OpenStack service FQDNs"
    return 0
}

# Remove hotstack-os entries from /etc/hosts
# Usage: remove_hosts_entries
remove_hosts_entries() {
    if grep -q "$HOSTS_BEGIN_MARKER" "$HOSTS_FILE" 2>/dev/null; then
        sed -i "/$HOSTS_BEGIN_MARKER/,/$HOSTS_END_MARKER/d" "$HOSTS_FILE" || true
    fi
    return 0
}

# ============================================================================
# Network Infrastructure Functions
# ============================================================================

# Create and configure OVS bridges
# Usage: add_ovs_bridges
# Requires: PROVIDER_NETWORK environment variable
add_ovs_bridges() {
    echo "Checking OpenvSwitch configuration..."
    if ! ovs-vsctl show &>/dev/null; then
        echo -e "${RED}✗${NC} OVS is not functional"
        return 1
    fi
    echo -e "${GREEN}✓${NC} OVS is functional"

    # Create hot-int bridge if it doesn't exist
    if ovs-vsctl br-exists hot-int; then
        echo -e "${GREEN}✓${NC} hot-int bridge exists"
    else
        echo -e "${YELLOW}⚠${NC} hot-int bridge does not exist, creating..."
        ovs-vsctl add-br hot-int
        echo -e "${GREEN}✓${NC} hot-int bridge created"
    fi

    # Create hot-ex bridge if it doesn't exist
    echo ""
    echo "Setting up hot-ex (external bridge) for provider networks..."
    if ovs-vsctl br-exists hot-ex; then
        echo -e "${GREEN}✓${NC} hot-ex bridge exists"
    else
        echo -e "${YELLOW}⚠${NC} hot-ex bridge does not exist, creating..."
        ovs-vsctl add-br hot-ex
        echo -e "${GREEN}✓${NC} hot-ex bridge created"
    fi

    # Assign IP to hot-ex bridge internal interface for host connectivity
    # The bridge's internal interface acts as the gateway for the provider network
    # and allows the host to communicate with VMs and services on hot-ex
    if ip addr show hot-ex | grep -q "$BREX_IP"; then
        echo -e "${GREEN}✓${NC} hot-ex already has IP $BREX_IP configured"
    else
        ip addr add "${BREX_IP}"/25 dev hot-ex
        ip link set hot-ex up
        echo -e "${GREEN}✓${NC} Assigned IP $BREX_IP to hot-ex bridge"
    fi

    echo -e "${GREEN}✓${NC} hot-ex configured for provider networks ($PROVIDER_NETWORK)"
    return 0
}


# Remove Open vSwitch bridges
# Usage: remove_ovs_bridges
remove_ovs_bridges() {
    if systemctl is-active --quiet openvswitch; then
        if ovs-vsctl br-exists hot-ex 2>/dev/null; then
            ovs-vsctl del-br hot-ex 2>/dev/null || true
        fi
        if ovs-vsctl br-exists hot-int 2>/dev/null; then
            ovs-vsctl del-br hot-int 2>/dev/null || true
        fi
    fi
    return 0
}

# ============================================================================
# Firewall Functions
# ============================================================================

# Configure firewall zones for HotStack-OS networks
# Usage: add_firewall_zones
# Requires: CONTAINER_NETWORK, PROVIDER_NETWORK environment variables
add_firewall_zones() {
    if ! systemctl is-active --quiet firewalld; then
        echo -e "${YELLOW}⚠${NC} Firewalld not running"
        return 1
    fi

    echo "Configuring firewall for HotStack-OS networks..."

    # Step 1: Create firewall zones
    local ZONES_CREATED=0

    if ! firewall-cmd --get-zones | grep -qw hotstack-os; then
        firewall-cmd --permanent --new-zone=hotstack-os >/dev/null
        echo "  Created zone: hotstack-os (container network)"
        ZONES_CREATED=1
    else
        echo "  Zone already exists: hotstack-os (container network)"
    fi

    if ! firewall-cmd --get-zones | grep -qw hotstack-external; then
        firewall-cmd --permanent --new-zone=hotstack-external >/dev/null
        echo "  Created zone: hotstack-external (provider network)"
        ZONES_CREATED=1
    else
        echo "  Zone already exists: hotstack-external (provider network)"
    fi

    # Reload firewalld if new zones were created (needed before configuring them)
    if [ $ZONES_CREATED -eq 1 ]; then
        firewall-cmd --reload >/dev/null
        echo "  Reloaded firewalld to activate new zones"
    fi

    # Step 2: Add network sources to zones
    firewall-cmd --permanent --zone=hotstack-os --add-source="$CONTAINER_NETWORK" &>/dev/null || true
    firewall-cmd --permanent --zone=hotstack-external --add-source="$PROVIDER_NETWORK" &>/dev/null || true

    # Step 3: Set zone targets to ACCEPT
    firewall-cmd --permanent --zone=hotstack-os --set-target=ACCEPT &>/dev/null || true
    firewall-cmd --permanent --zone=hotstack-external --set-target=ACCEPT &>/dev/null || true

    firewall-cmd --reload >/dev/null
    echo -e "  ${GREEN}✓${NC} Firewall zone: hotstack-os configured (sources: $CONTAINER_NETWORK, target: ACCEPT)"
    echo -e "  ${GREEN}✓${NC} Firewall zone: hotstack-external configured (sources: $PROVIDER_NETWORK, target: ACCEPT)"
    return 0
}

# Remove hotstack firewall zones
# Usage: remove_firewall_zones
remove_firewall_zones() {
    if systemctl is-active --quiet firewalld; then
        local ZONES_REMOVED=0
        firewall-cmd --get-zones 2>/dev/null | grep -qw hotstack-os && {
            firewall-cmd --permanent --delete-zone=hotstack-os &>/dev/null || true
            ZONES_REMOVED=1
        }
        if firewall-cmd --get-zones 2>/dev/null | grep -qw hotstack-external; then
            firewall-cmd --permanent --delete-zone=hotstack-external &>/dev/null || true
            ZONES_REMOVED=1
        fi
        if [ $ZONES_REMOVED -eq 1 ]; then
            firewall-cmd --reload &>/dev/null || true
        fi
    fi
    return 0
}

# ============================================================================
# Storage Cleanup
# ============================================================================

# Clean up storage backend state (NFS mounts, etc.)
# Usage: cleanup_storage_state
# Returns: 0 on success
cleanup_storage_state() {
    # Unmount NFS shares if mounted (force unmount to handle stale mounts)
    if mountpoint -q "$CINDER_NFS_EXPORT_DIR" 2>/dev/null; then
        echo "  Unmounting NFS export at $CINDER_NFS_EXPORT_DIR..." >&2
        umount -f "$CINDER_NFS_EXPORT_DIR" 2>/dev/null || true
    fi

    return 0
}

# ============================================================================
# Libvirt VM Cleanup
# ============================================================================

# Remove libvirt VMs matching HotStack naming pattern
# Usage: remove_libvirt_vms
# Returns: 0 on success, 1 if virsh not available
remove_libvirt_vms() {
    if ! command -v virsh &> /dev/null; then
        return 1
    fi

    # WARNING: This will destroy ALL libvirt VMs matching the pattern "notapet-<uuid>"
    # This is HotStack's custom Nova naming (cattle not pets!), but could affect:
    # - VMs from other deployments using the same naming pattern
    # - Any manually created VMs following this naming pattern
    # Pattern matches full UUID format: 8-4-4-4-12 hex digits (e.g., notapet-9995eda6-9999-4d2e-afaf-bf7be0d981de)
    for vm in $(virsh list --all --name 2>/dev/null | grep -E "^notapet-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" || true); do
        virsh destroy "$vm" &>/dev/null || true
        virsh undefine "$vm" --nvram &>/dev/null || true
    done
    return 0
}

# ============================================================================
# Network Namespace Cleanup
# ============================================================================

# Remove network namespaces created by Neutron/OVN
# Usage: remove_network_namespaces
# Returns: 0 on success, 1 if ip command not available
remove_network_namespaces() {
    if ! command -v ip &> /dev/null; then
        return 1
    fi

    # Remove OVN metadata agent network namespaces (netns-*)
    # These are created by Neutron/OVN for each network's metadata proxy
    for ns in $(ip netns list 2>/dev/null | grep -oE "^netns-[0-9a-f-]+" || true); do
        ip netns delete "$ns" 2>/dev/null || true
    done
    return 0
}

# ============================================================================
# OpenStack Client Configuration
# ============================================================================

# Set up OpenStack admin credentials for CLI operations
# This function exports the necessary environment variables for OpenStack
# client commands to authenticate as the admin user.
#
# Prerequisites:
#   - KEYSTONE_ADMIN_PASSWORD must be set in the environment
#
# Usage:
#   setup_os_admin_credentials
setup_os_admin_credentials() {
    export OS_USERNAME=admin
    export OS_PASSWORD=${KEYSTONE_ADMIN_PASSWORD}
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://keystone:5000/v3
    export OS_IDENTITY_API_VERSION=3
}

# ============================================================================
# Auto-initialization
# ============================================================================

# Detect OS automatically when common.sh is sourced
# This sets OS_ID, OS_NAME, OS_VERSION for use by is_centos/is_fedora functions
detect_os quiet

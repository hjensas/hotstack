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

# Common functions for OpenStack service entrypoint scripts

# Validates that required environment variables are set and non-empty.
#
# Parameters:
#   $@ - List of environment variable names to validate
#
# Returns:
#   0 if all variables are set and non-empty
#   1 if any variable is missing or empty (also exits the script)
#
# Example:
#   validate_required_env "DB_HOST" "DB_USER" "DB_PASSWORD"
validate_required_env() {
    local missing=0
    local vars=("$@")

    for var in "${vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "ERROR: Required environment variable $var is not set or empty"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        echo "ERROR: $missing required environment variable(s) missing"
        echo "       Check your .env file and podman-compose.yml"
        exit 1
    fi
}

# Waits for a MariaDB/MySQL database to become available and responsive.
# Uses the 'mariadb' client command provided by default-mysql-client package.
#
# Parameters:
#   $1 - Database host (e.g., "mariadb" or "127.0.0.1")
#   $2 - Database user
#   $3 - Database password
#   $4 - Database name
#   $5 - Maximum retry attempts (optional, default: 60)
#
# Returns:
#   0 if database becomes available
#   1 if database is not available after max_retries (also exits the script)
#
# Example:
#   wait_for_database "mariadb" "keystone" "secretpass" "keystone" 60
wait_for_database() {
    local db_host="$1"
    local db_user="$2"
    local db_password="$3"
    local db_name="$4"
    local max_retries="${5:-60}"

    echo "Waiting for database ${db_name}..."
    local retry_count=0

    until mariadb -h "$db_host" -u"$db_user" -p"$db_password" -e "SELECT 1" "$db_name" &>/dev/null; do
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge "$max_retries" ]; then
            echo ""
            echo "========================================================================"
            echo "ERROR: Database ${db_name} not available after ${max_retries} attempts"
            echo "========================================================================"
            echo ""
            echo "Diagnostic information:"
            echo "  Database host: $db_host"
            echo "  Database name: $db_name"
            echo "  Database user: $db_user"
            echo "  Password set: $([ -n "$db_password" ] && echo "yes" || echo "NO - EMPTY!")"
            echo ""
            echo "Testing network connectivity to database:"
            if ping -c 1 -W 2 "$db_host" &>/dev/null; then
                echo "  ✓ Can ping $db_host"
            else
                echo "  ✗ Cannot ping $db_host (network issue?)"
            fi
            echo ""
            echo "Attempting connection with verbose output:"
            mariadb -h "$db_host" -u"$db_user" -p"$db_password" -e "SELECT 1" "$db_name" 2>&1 | head -20
            echo ""
            echo "Check MariaDB logs: podman logs hotstack-os-mariadb"
            echo "Check MariaDB status: podman exec hotstack-os-mariadb mariadb -uroot -prootpass -e 'SHOW DATABASES'"
            echo "========================================================================"
            exit 1
        fi
        # Show more verbose info every 10 attempts
        if [ $((retry_count % 10)) -eq 0 ]; then
            echo "Database not ready, waiting... ($retry_count/$max_retries) - Testing: mariadb -h $db_host -u$db_user -p*** $db_name"
        else
            echo "Database not ready, waiting... ($retry_count/$max_retries)"
        fi
        sleep 2
    done

    echo "Database ${db_name} is ready!"
}

# Waits for an HTTP service to become available by polling a URL.
#
# Parameters:
#   $1 - Service name (for display purposes)
#   $2 - Service URL to check (must return HTTP 200 OK when ready)
#   $3 - Maximum retry attempts (optional, default: 30)
#
# Returns:
#   0 if service becomes available
#   1 if service is not available after max_retries (also exits the script)
#
# Example:
#   wait_for_service "Keystone" "http://keystone:5000/v3" 30
wait_for_service() {
    local service_name="$1"
    local service_url="$2"
    local max_retries="${3:-30}"

    echo "Waiting for ${service_name}..."
    local retry_count=0

    for _ in $(seq 1 "$max_retries"); do
        if curl -sf "$service_url" &>/dev/null; then
            echo "${service_name} is ready!"
            return 0
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge "$max_retries" ]; then
            echo "ERROR: ${service_name} not available after ${max_retries} attempts ($((max_retries * 2)) seconds)"
            echo "       URL: ${service_url}"
            exit 1
        fi
        sleep 2
    done
}

# Waits for Keystone authentication service to become fully operational.
# Tests Keystone by attempting to issue an authentication token using OpenStack CLI.
# Automatically configures OpenStack client environment variables for admin user.
#
# Parameters:
#   $1 - Maximum retry attempts (optional, default: 60)
#   $2 - Keystone URL (optional, default: http://keystone:5000/v3)
#
# Environment Variables Required:
#   KEYSTONE_ADMIN_PASSWORD - Admin user password for authentication
#
# Returns:
#   0 if Keystone becomes available and can issue tokens
#   1 if Keystone is not available after max_retries (also exits the script)
#
# Example:
#   wait_for_keystone 60 "http://keystone:5000/v3"
wait_for_keystone() {
    local max_retries="${1:-60}"
    local keystone_url="${2:-http://keystone:5000/v3}"

    export OS_USERNAME=admin
    export OS_PASSWORD=${KEYSTONE_ADMIN_PASSWORD}
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL="$keystone_url"
    export OS_IDENTITY_API_VERSION=3

    echo "Waiting for Keystone..."
    local retry_count=0

    for _ in $(seq 1 "$max_retries"); do
        if openstack token issue &>/dev/null; then
            echo "Keystone is ready!"
            return 0
        fi
        retry_count=$((retry_count + 1))

        # Show progress every 10 attempts
        if [ $((retry_count % 10)) -eq 0 ]; then
            echo "Still waiting... ($retry_count/$max_retries) - Testing: openstack token issue"
            # Show actual error on every 10th attempt
            openstack token issue 2>&1 | head -5
        fi

        if [ $retry_count -ge "$max_retries" ]; then
            echo ""
            echo "========================================================================"
            echo "ERROR: Keystone not available after ${max_retries} attempts ($((max_retries * 2)) seconds)"
            echo "========================================================================"
            echo ""
            echo "Last authentication attempt error:"
            openstack token issue 2>&1 | head -10
            echo ""
            echo "Check: podman logs hotstack-os-keystone"
            echo "========================================================================"
            exit 1
        fi
        sleep 2
    done
}

# Configures OpenStack client environment variables for admin user authentication.
# Sets up credentials to interact with OpenStack services via the OpenStack CLI.
#
# Environment Variables Required:
#   KEYSTONE_ADMIN_PASSWORD - Admin user password
#
# Environment Variables Exported:
#   OS_USERNAME - Set to "admin"
#   OS_PASSWORD - Set to KEYSTONE_ADMIN_PASSWORD value
#   OS_PROJECT_NAME - Set to "admin"
#   OS_USER_DOMAIN_NAME - Set to "Default"
#   OS_PROJECT_DOMAIN_NAME - Set to "Default"
#   OS_AUTH_URL - Set to "http://keystone:5000/v3"
#   OS_IDENTITY_API_VERSION - Set to "3"
#
# Example:
#   setup_os_admin_credentials
#   openstack project list
setup_os_admin_credentials() {
    export OS_USERNAME=admin
    export OS_PASSWORD=${KEYSTONE_ADMIN_PASSWORD}
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://keystone:5000/v3
    export OS_IDENTITY_API_VERSION=3
}

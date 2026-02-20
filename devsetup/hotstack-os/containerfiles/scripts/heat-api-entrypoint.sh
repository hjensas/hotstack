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

set -e

# Source common functions
# shellcheck disable=SC1091
source /usr/local/lib/common.sh

# Validate required environment variables
validate_required_env HEAT_DB_PASSWORD SERVICE_PASSWORD KEYSTONE_ADMIN_PASSWORD REGION_NAME

# Wait for database
wait_for_database "mariadb" "openstack" "${HEAT_DB_PASSWORD}" "heat"

# Sync database
echo "Syncing Heat database..."
heat-manage db_sync

# Register service in Keystone if OS_BOOTSTRAP is set
if [ "${OS_BOOTSTRAP:-true}" = "true" ]; then
    echo "Registering Heat service in Keystone..."

    setup_os_admin_credentials

    # Wait for Keystone
    wait_for_keystone

    echo "  Creating heat user and assigning admin role..."
    if ! openstack user show heat >/dev/null 2>&1; then
        openstack user create --domain default --password "${SERVICE_PASSWORD}" heat
    fi
    openstack role add --project service --user heat admin 2>/dev/null || true
    openstack role add --project service --user heat service 2>/dev/null || true

    echo "  Creating heat domain..."
    if ! openstack domain show heat >/dev/null 2>&1; then
        openstack domain create --description "Stack projects and users" heat
    fi

    echo "  Creating heat_domain_admin user..."
    if ! openstack user show --domain heat heat_domain_admin >/dev/null 2>&1; then
        openstack user create --domain heat --password "${SERVICE_PASSWORD}" heat_domain_admin
    fi
    openstack role add --domain heat --user heat_domain_admin admin 2>/dev/null || true

    echo "  Creating heat roles..."
    openstack role show heat_stack_owner >/dev/null 2>&1 || openstack role create heat_stack_owner
    openstack role show heat_stack_user >/dev/null 2>&1 || openstack role create heat_stack_user

    echo "  Creating heat service..."
    if ! openstack service show heat >/dev/null 2>&1; then
        openstack service create --name heat --description "Orchestration" orchestration
    fi

    echo "  Creating heat endpoints..."
    HEAT_SERVICE_ID=$(openstack service show heat -f value -c id)
    for endpoint_type in public internal admin; do
        if ! openstack endpoint list --service heat --interface ${endpoint_type} --region "${REGION_NAME}" -f value -c ID | grep -q .; then
            # shellcheck disable=SC2016
            openstack endpoint create --region "${REGION_NAME}" "${HEAT_SERVICE_ID}" ${endpoint_type} 'http://heat.hotstack-os.local:8004/v1/$(project_id)s'
        fi
    done

    echo "Heat service registered!"
fi

# Start Heat API
echo "Starting Heat API service..."
exec heat-api --config-file=/etc/heat/heat.conf

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
validate_required_env NOVA_DB_PASSWORD SERVICE_PASSWORD KEYSTONE_ADMIN_PASSWORD REGION_NAME RABBITMQ_USER RABBITMQ_PASS

# Wait for database
wait_for_database "mariadb" "openstack" "${NOVA_DB_PASSWORD}" "nova_api"

# Sync databases
echo "Syncing Nova databases..."
nova-manage api_db sync
nova-manage cell_v2 map_cell0
nova-manage db sync

# Register service in Keystone if OS_BOOTSTRAP is set
if [ "${OS_BOOTSTRAP:-true}" = "true" ]; then
    echo "Registering Nova service in Keystone..."

    setup_os_admin_credentials

    # Wait for Keystone and Placement
    wait_for_keystone
    wait_for_service "Placement" "http://placement:8778/"

    echo "  Creating nova user and assigning admin role..."
    if ! openstack user show nova >/dev/null 2>&1; then
        openstack user create --domain default --password "${SERVICE_PASSWORD}" nova
    fi
    openstack role add --project service --user nova admin 2>/dev/null || true
    openstack role add --project service --user nova service 2>/dev/null || true

    echo "  Creating nova service..."
    if ! openstack service show nova >/dev/null 2>&1; then
        openstack service create --name nova --description "OpenStack Compute" compute
    fi

    echo "  Creating nova endpoints..."
    NOVA_SERVICE_ID=$(openstack service show nova -f value -c id)
    for endpoint_type in public internal admin; do
        if ! openstack endpoint list --service nova --interface ${endpoint_type} --region "${REGION_NAME}" -f value -c ID | grep -q .; then
            openstack endpoint create --region "${REGION_NAME}" "${NOVA_SERVICE_ID}" ${endpoint_type} http://nova.hotstack-os.local:8774/v2.1
        fi
    done

    echo "  Creating Nova cell1..."
    nova-manage cell_v2 create_cell --name=cell1 --verbose || true

    echo "Nova service registered!"
fi

# Start Nova API
echo "Starting Nova API service..."
exec nova-api --config-file=/etc/nova/nova.conf

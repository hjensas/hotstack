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
validate_required_env GLANCE_DB_PASSWORD SERVICE_PASSWORD KEYSTONE_ADMIN_PASSWORD REGION_NAME

# Wait for database
wait_for_database "mariadb" "openstack" "${GLANCE_DB_PASSWORD}" "glance"

# Sync database
echo "Syncing Glance database..."
glance-manage db_sync

# Register service in Keystone if OS_BOOTSTRAP is set
if [ "${OS_BOOTSTRAP:-true}" = "true" ]; then
    echo "Registering Glance service in Keystone..."

    setup_os_admin_credentials

    # Wait for Keystone
    wait_for_keystone

    echo "  Creating glance user and assigning admin role..."
    if ! openstack user show glance >/dev/null 2>&1; then
        openstack user create --domain default --password "${SERVICE_PASSWORD}" glance
    fi
    openstack role add --project service --user glance admin 2>/dev/null || true
    openstack role add --project service --user glance service 2>/dev/null || true

    echo "  Creating glance service..."
    if ! openstack service show glance >/dev/null 2>&1; then
        openstack service create --name glance --description "OpenStack Image" image
    fi

    echo "  Creating glance endpoints..."
    GLANCE_SERVICE_ID=$(openstack service show glance -f value -c id)
    for endpoint_type in public internal admin; do
        if ! openstack endpoint list --service glance --interface ${endpoint_type} --region "${REGION_NAME}" -f value -c ID | grep -q .; then
            openstack endpoint create --region "${REGION_NAME}" "${GLANCE_SERVICE_ID}" ${endpoint_type} http://glance.hotstack-os.local:9292
        fi
    done

    echo "Glance service registered!"
fi

# Start Glance API
echo "Starting Glance API service..."
exec glance-api --config-file=/etc/glance/glance-api.conf

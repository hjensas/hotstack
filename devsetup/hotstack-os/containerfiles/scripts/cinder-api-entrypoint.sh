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
validate_required_env CINDER_DB_PASSWORD SERVICE_PASSWORD KEYSTONE_ADMIN_PASSWORD REGION_NAME

# Wait for database
wait_for_database "mariadb" "openstack" "${CINDER_DB_PASSWORD}" "cinder"

# Sync database
echo "Syncing Cinder database..."
cinder-manage db sync

# Register service in Keystone if OS_BOOTSTRAP is set
if [ "${OS_BOOTSTRAP:-true}" = "true" ]; then
    echo "Registering Cinder service in Keystone..."

    setup_os_admin_credentials

    # Wait for Keystone
    wait_for_keystone

    echo "  Creating cinder user and assigning admin role..."
    if ! openstack user show cinder >/dev/null 2>&1; then
        openstack user create --domain default --password "${SERVICE_PASSWORD}" cinder
    fi
    openstack role add --project service --user cinder admin 2>/dev/null || true
    openstack role add --project service --user cinder service 2>/dev/null || true

    echo "  Creating cinder service..."
    if ! openstack service show cinderv3 >/dev/null 2>&1; then
        openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
    fi

    echo "  Creating cinder endpoints..."
    CINDER_SERVICE_ID=$(openstack service show cinderv3 -f value -c id)
    for endpoint_type in public internal admin; do
        if ! openstack endpoint list --service cinderv3 --interface ${endpoint_type} --region "${REGION_NAME}" -f value -c ID | grep -q .; then
            # shellcheck disable=SC2016
            openstack endpoint create --region "${REGION_NAME}" "${CINDER_SERVICE_ID}" ${endpoint_type} 'http://cinder.hotstack-os.local:8776/v3/$(project_id)s'
        fi
    done

    echo "Cinder service registered!"
fi

# Start Cinder API
echo "Starting Cinder API service..."
exec cinder-api --config-file=/etc/cinder/cinder.conf

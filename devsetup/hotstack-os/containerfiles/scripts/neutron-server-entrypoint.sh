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
validate_required_env NEUTRON_DB_PASSWORD SERVICE_PASSWORD KEYSTONE_ADMIN_PASSWORD REGION_NAME

# Wait for database
wait_for_database "mariadb" "openstack" "${NEUTRON_DB_PASSWORD}" "neutron"

# Sync database
echo "Syncing Neutron database..."
neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

# Register service in Keystone if OS_BOOTSTRAP is set
if [ "${OS_BOOTSTRAP:-true}" = "true" ]; then
    echo "Registering Neutron service in Keystone..."

    setup_os_admin_credentials

    # Wait for Keystone
    wait_for_keystone

    echo "  Creating neutron user and assigning admin role..."
    if ! openstack user show neutron >/dev/null 2>&1; then
        openstack user create --domain default --password "${SERVICE_PASSWORD}" neutron
    fi
    openstack role add --project service --user neutron admin 2>/dev/null || true
    openstack role add --project service --user neutron service 2>/dev/null || true

    echo "  Creating neutron service..."
    if ! openstack service show neutron >/dev/null 2>&1; then
        openstack service create --name neutron --description "OpenStack Networking" network
    fi

    echo "  Creating neutron endpoints..."
    NEUTRON_SERVICE_ID=$(openstack service show neutron -f value -c id)
    for endpoint_type in public internal admin; do
        if ! openstack endpoint list --service neutron --interface ${endpoint_type} --region "${REGION_NAME}" -f value -c ID | grep -q .; then
            openstack endpoint create --region "${REGION_NAME}" "${NEUTRON_SERVICE_ID}" ${endpoint_type} http://neutron.hotstack-os.local:9696
        fi
    done

    echo "Neutron service registered!"
fi

# Start Neutron Server
echo "Starting Neutron Server..."
exec neutron-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini

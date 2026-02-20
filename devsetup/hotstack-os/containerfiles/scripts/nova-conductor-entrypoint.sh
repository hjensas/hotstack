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
validate_required_env NOVA_DB_PASSWORD SERVICE_PASSWORD RABBITMQ_USER RABBITMQ_PASS

# Wait for database
wait_for_database "mariadb" "openstack" "${NOVA_DB_PASSWORD}" "nova"

# Wait for Nova API to be ready
wait_for_service "Nova API" "http://nova:8774/" 60

# Start Nova Conductor
echo "Starting Nova Conductor service..."
exec nova-conductor --config-file=/etc/nova/nova.conf

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

echo "Initializing OVN databases..."

# Create required directories if they don't exist
mkdir -p /var/lib/ovn /run/ovn /var/run/openvswitch

# Initialize OVN NB database if it doesn't exist
if [ ! -f /var/lib/ovn/ovnnb_db.db ]; then
    echo "Creating OVN Northbound database..."
    ovsdb-tool create /var/lib/ovn/ovnnb_db.db /usr/share/ovn/ovn-nb.ovsschema
fi

# Initialize OVN SB database if it doesn't exist
if [ ! -f /var/lib/ovn/ovnsb_db.db ]; then
    echo "Creating OVN Southbound database..."
    ovsdb-tool create /var/lib/ovn/ovnsb_db.db /usr/share/ovn/ovn-sb.ovsschema
fi

echo "Starting OVN databases..."

# Start OVN NB database (both unix socket and TCP)
ovsdb-server --detach --pidfile=/run/ovn/ovnnb_db.pid \
    --remote=punix:/run/ovn/ovnnb_db.sock \
    --remote=ptcp:6641:0.0.0.0 \
    --remote=db:OVN_Northbound,NB_Global,connections \
    --private-key=db:OVN_Northbound,SSL,private_key \
    --certificate=db:OVN_Northbound,SSL,certificate \
    --ca-cert=db:OVN_Northbound,SSL,ca_cert \
    /var/lib/ovn/ovnnb_db.db

# Start OVN SB database (both unix socket and TCP)
ovsdb-server --detach --pidfile=/run/ovn/ovnsb_db.pid \
    --remote=punix:/run/ovn/ovnsb_db.sock \
    --remote=ptcp:6642:0.0.0.0 \
    --remote=db:OVN_Southbound,SB_Global,connections \
    --private-key=db:OVN_Southbound,SSL,private_key \
    --certificate=db:OVN_Southbound,SSL,certificate \
    --ca-cert=db:OVN_Southbound,SSL,ca_cert \
    /var/lib/ovn/ovnsb_db.db

echo "OVN databases started"

# Start OVN northd in foreground
echo "Starting OVN northd..."
exec ovn-northd \
    --ovnnb-db=unix:/run/ovn/ovnnb_db.sock \
    --ovnsb-db=unix:/run/ovn/ovnsb_db.sock \
    --pidfile=/run/ovn/ovn-northd.pid

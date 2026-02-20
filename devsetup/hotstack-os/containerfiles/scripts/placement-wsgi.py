#!/usr/bin/env python3
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

"""WSGI entry point for Placement API."""

import os
import sys

from oslo_config import cfg
from oslo_log import log as logging

from placement import conf
from placement import db_api
from placement import deploy

CONF = cfg.CONF

# Set config file location from environment or use default
config_files = ["/etc/placement/placement.conf"]
if "OS_PLACEMENT_CONFIG_FILES" in os.environ:
    config_files = os.environ["OS_PLACEMENT_CONFIG_FILES"].split(",")

# Parse configuration
conf.register_opts(CONF)
CONF([], project="placement", default_config_files=config_files)

# Setup logging
logging.setup(CONF, "placement")

# Configure database - required before loadapp()
db_api.configure(CONF)

# Create the WSGI application
application = deploy.loadapp(CONF)

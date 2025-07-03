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

import re
import time
from subprocess import Popen, PIPE, TimeoutExpired
import yaml

from ansible.module_utils.basic import AnsibleModule


ANSIBLE_METADATA = {
    "metadata_version": "1.1",
    "status": ["preview"],
    "supported_by": "community",
}

DOCUMENTATION = r"""
---
module: hotloop_wait_for_bmh

short_description: Wait for a BaremetalHost resource to reach a target state

version_added: "2.8"

description:
    - Wait for a BaremetalHost resource to reach one of the target states
    - Target states are: available, provisioned, provisioning
    - Polls the resource status at regular intervals until timeout or success

options:
  namespace:
    description:
      - The namespace where the BaremetalHost resource is located
    type: str
    required: true
  bmh:
    description:
      - The name of the BaremetalHost resource to monitor
    type: str
    required: true
  timeout:
    description:
      - Maximum time to wait in seconds before timing out
    type: int
    default: 300
  poll_interval:
    description:
      - Time in seconds between status checks
    type: int
    default: 10
  target_states:
    description:
      - List of acceptable target states to wait for
    type: list
    default: ['available', 'provisioned', 'provisioning']

author:
    - Harald Jensås <hjensas@redhat.com>
"""

EXAMPLES = r"""
- name: Wait for BaremetalHost to be available
  hotloop_wait_for_bmh:
    namespace: openstack
    bmh: bmh3
    timeout: 300

- name: Wait for BaremetalHost with custom timeout and poll interval
  hotloop_wait_for_bmh:
    namespace: openstack
    bmh: bmh3
    timeout: 600
    poll_interval: 5

- name: Wait for specific states only
  hotloop_wait_for_bmh:
    namespace: openstack
    bmh: bmh3
    target_states: ['available', 'provisioned']
"""

RETURN = r"""
state:
    description: The final state of the BaremetalHost resource
    type: str
    returned: success
    sample: 'available'
elapsed:
    description: Time elapsed while waiting (in seconds)
    type: int
    returned: always
    sample: 45
"""


def get_bmh_state(namespace, bmh, timeout=30):
    """Get the current provisioning state of a BaremetalHost resource.

    :param namespace: The namespace of the BaremetalHost resource
    :param bmh: The name of the BaremetalHost resource
    :param timeout: Timeout for the oc command
    :returns: A tuple containing (success, state, error_message)
    """
    cmd = [
        "oc",
        "get",
        "-n",
        namespace,
        "baremetalhosts.metal3.io",
        bmh,
        "-o",
        "jsonpath='{.status.provisioning.state}'",
    ]

    try:
        proc = Popen(cmd, stdout=PIPE, stderr=PIPE)
        outs, errs = proc.communicate(timeout=timeout)

        rc = proc.returncode
        stdout = outs.decode("utf-8").strip()
        stderr = errs.decode("utf-8").strip()

        if rc == 0:
            return True, stdout, None
        else:
            return False, None, stderr

    except TimeoutExpired:
        proc.kill()
        return False, None, "Command timed out"
    except Exception as e:
        return False, None, str(e)


def wait_for_bmh_state(namespace, bmh, target_states, timeout, poll_interval):
    """Wait for a BaremetalHost to reach one of the target states.

    :param namespace: The namespace of the BaremetalHost resource
    :param bmh: The name of the BaremetalHost resource
    :param target_states: List of acceptable target states
    :param timeout: Maximum time to wait in seconds
    :param poll_interval: Time between checks in seconds
    :returns: A tuple containing (success, final_state, elapsed_time, error_message)
    """
    start_time = time.time()

    while True:
        elapsed = time.time() - start_time

        # Check if we've exceeded the timeout
        if elapsed >= timeout:
            return False, None, elapsed, f"Timeout after {timeout} seconds"

        # Get current state
        success, current_state, error = get_bmh_state(namespace, bmh)

        if not success:
            return False, None, elapsed, f"Failed to get BMH state: {error}"

        # Check if current state matches any target state
        if current_state in target_states:
            return True, current_state, elapsed, None

        # Wait before next check (but don't exceed timeout)
        remaining_time = timeout - elapsed
        sleep_time = min(poll_interval, remaining_time)

        if sleep_time <= 0:
            return False, None, elapsed, f"Timeout after {timeout} seconds"

        time.sleep(sleep_time)


def run_module():
    argument_spec = yaml.safe_load(DOCUMENTATION)["options"]
    module = AnsibleModule(argument_spec, supports_check_mode=False)

    result = dict(changed=False, state="", elapsed=0, msg="")

    namespace = module.params["namespace"]
    bmh = module.params["bmh"]
    timeout = module.params["timeout"]
    poll_interval = module.params["poll_interval"]
    target_states = module.params["target_states"]

    try:
        success, final_state, elapsed, error = wait_for_bmh_state(
            namespace, bmh, target_states, timeout, poll_interval
        )

        result["elapsed"] = int(elapsed)

        if success:
            result["state"] = final_state
            result["msg"] = (
                f"BaremetalHost {bmh} reached target state '{final_state}' after {int(elapsed)} seconds"
            )
            module.exit_json(**result)
        else:
            result["msg"] = f"Failed to wait for BaremetalHost {bmh}: {error}"
            module.fail_json(**result)

    except Exception as e:
        result["msg"] = (
            f"Unexpected error while waiting for BaremetalHost {bmh}: {str(e)}"
        )
        module.fail_json(**result)


def main():
    run_module()


if __name__ == "__main__":
    main()

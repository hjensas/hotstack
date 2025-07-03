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

import os

from ansible.plugins.action import ActionBase
from ansible.errors import AnsibleActionFail


class ActionModule(ActionBase):
    """
    Action plugin for hotloop_stage_executor

    This plugin runs on the controller and orchestrates stage execution by:
    1. Handling file operations (copy/template) for manifests
    2. Calling specialized modules in sequence for different stage types
    3. Aggregating results from all modules

    Wait conditions are handled separately as plain Ansible tasks.
    Templating is detected automatically based on .j2 file extension.
    """

    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = dict()

        result = super(ActionModule, self).run(tmp, task_vars)
        del tmp  # tmp no longer has any effect

        # Get module arguments
        module_args = self._task.args.copy()
        stage = module_args.get("stage", {})
        work_dir = module_args.get("work_dir", "")
        manifests_dir = module_args.get("manifests_dir", "")
        template_vars = module_args.get("template_vars", task_vars)

        stage_name = stage.get("name", "Unknown")

        # Initialize result structure
        result.update({"changed": False, "actions_performed": [], "results": {}})

        try:
            # Handle file operations for manifest stages
            if "manifest" in stage:
                manifest_path = stage["manifest"]
                # Detect if templating is needed based on .j2 extension
                if manifest_path.endswith(".j2"):
                    self._handle_template_manifest(
                        stage, work_dir, manifests_dir, task_vars, template_vars
                    )
                else:
                    self._handle_static_manifest(
                        stage, work_dir, manifests_dir, task_vars
                    )

            # Execute command or shell if present
            if "command" in stage:
                cmd_result = self._execute_builtin_command(stage, task_vars)
                if cmd_result.get("failed", False):
                    raise AnsibleActionFail(
                        f"Command failed: {stage['command']} - {cmd_result.get('msg', 'Unknown error')}"
                    )
                result["actions_performed"].append("command")
                result["results"]["command_execution"] = cmd_result
                if cmd_result.get("changed", False):
                    result["changed"] = True

            if "shell" in stage:
                shell_result = self._execute_builtin_shell(stage, task_vars)
                if shell_result.get("failed", False):
                    raise AnsibleActionFail(
                        f"Shell script failed: {stage['shell']} - {shell_result.get('msg', 'Unknown error')}"
                    )
                result["actions_performed"].append("shell")
                result["results"]["shell_execution"] = shell_result
                if shell_result.get("changed", False):
                    result["changed"] = True

            # Process manifest if present
            if "manifest" in stage:
                manifest_result = self._execute_manifest_module(
                    stage, manifests_dir, task_vars
                )
                result["actions_performed"].append(manifest_result["action_performed"])
                result["results"]["manifest_processing"] = manifest_result["result"]
                if manifest_result["changed"]:
                    result["changed"] = True

            # If no actions were performed, that's unusual but not an error
            if not result["actions_performed"]:
                result["actions_performed"].append("no_action")
                result["results"][
                    "message"
                ] = f"Stage '{stage_name}' had no recognized actions to perform"

        except Exception as e:
            raise AnsibleActionFail(f"Stage '{stage_name}' failed: {str(e)}")

        return result

    def _handle_static_manifest(self, stage, work_dir, manifests_dir, task_vars):
        """Handle static manifest file operations"""
        manifest_path = stage["manifest"]
        src_path = os.path.join(work_dir, manifest_path)

        # Determine destination path structure (matching original logic)
        manifest_dir = os.path.join(
            manifests_dir, os.path.basename(os.path.dirname(manifest_path))
        )
        dest_filename = os.path.basename(manifest_path)
        dest_path = os.path.join(manifest_dir, dest_filename)

        # Ensure destination directory exists on remote
        dir_result = self._execute_module(
            module_name="ansible.builtin.file",
            module_args={"path": manifest_dir, "state": "directory", "mode": "0755"},
            task_vars=task_vars,
        )

        if dir_result.get("failed"):
            raise AnsibleActionFail(
                f"Failed to create directory {manifest_dir}: {dir_result.get('msg', 'Unknown error')}"
            )

        # Copy manifest file from controller/work_dir to remote
        copy_result = self._execute_module(
            module_name="ansible.builtin.copy",
            module_args={"src": src_path, "dest": dest_path, "backup": True},
            task_vars=task_vars,
        )

        if copy_result.get("failed"):
            raise AnsibleActionFail(
                f"Failed to copy manifest {src_path} to {dest_path}: {copy_result.get('msg', 'Unknown error')}"
            )

    def _handle_template_manifest(
        self, stage, work_dir, manifests_dir, task_vars, template_vars
    ):
        """Handle templated manifest file operations"""
        manifest_path = stage["manifest"]  # Now using manifest key for .j2 files too
        src_path = os.path.join(work_dir, manifest_path)

        # Determine destination path structure (matching original logic)
        manifest_dir = os.path.join(
            manifests_dir, os.path.basename(os.path.dirname(manifest_path))
        )
        dest_filename = os.path.splitext(os.path.basename(manifest_path))[
            0
        ]  # Remove .j2 extension
        dest_path = os.path.join(manifest_dir, dest_filename)

        # Ensure destination directory exists on remote
        dir_result = self._execute_module(
            module_name="ansible.builtin.file",
            module_args={"path": manifest_dir, "state": "directory", "mode": "0755"},
            task_vars=task_vars,
        )

        if dir_result.get("failed"):
            raise AnsibleActionFail(
                f"Failed to create directory {manifest_dir}: {dir_result.get('msg', 'Unknown error')}"
            )

        # Template the file from controller/work_dir to remote
        template_result = self._execute_module(
            module_name="ansible.builtin.template",
            module_args={"src": src_path, "dest": dest_path},
            task_vars=task_vars,
        )

        if template_result.get("failed"):
            raise AnsibleActionFail(
                f"Failed to template {src_path} to {dest_path}: {template_result.get('msg', 'Unknown error')}"
            )

    def _execute_builtin_command(self, stage, task_vars):
        """Execute the builtin command module"""
        return self._execute_module(
            module_name="ansible.builtin.command",
            module_args={"cmd": stage["command"]},
            task_vars=task_vars,
        )

    def _execute_builtin_shell(self, stage, task_vars):
        """Execute the builtin shell module"""
        return self._execute_module(
            module_name="ansible.builtin.shell",
            module_args={"cmd": stage["shell"]},
            task_vars=task_vars,
        )

    def _execute_manifest_module(self, stage, manifests_dir, task_vars):
        """Execute the manifest processor module"""
        return self._execute_module(
            module_name="hotloop_manifest_processor",
            module_args={"stage": stage, "manifests_dir": manifests_dir},
            task_vars=task_vars,
        )

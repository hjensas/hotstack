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

"""
Process configuration files by performing string substitutions.

This script replaces placeholder strings in configuration files with their
actual values. It handles multi-line replacements and special characters
properly, unlike shell-based approaches.
"""

import sys
import argparse
from pathlib import Path


# File extensions to process
CONFIG_EXTENSIONS = {".conf", ".ini", ".cfg", ".yaml", ".yml", ".example"}


def find_config_files(config_dir):
    """
    Find all configuration files in the given directory.

    Args:
        config_dir: Directory to search for config files

    Returns:
        List of Path objects for config files
    """
    config_path = Path(config_dir)
    if not config_path.exists():
        print(f"Error: Config directory {config_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    config_files = []
    for ext in CONFIG_EXTENSIONS:
        config_files.extend(config_path.rglob(f"*{ext}"))

    return config_files


def process_single_file(config_file, replacements):
    """
    Process a single config file with the given replacements.

    Args:
        config_file: Path object for the config file
        replacements: List of (search, replace) tuples
    """
    try:
        content = config_file.read_text()
        modified = False

        # Apply all replacements
        for search, replace in replacements:
            if search in content:
                content = content.replace(search, replace)
                modified = True

        # Write back if modified
        if modified:
            config_file.write_text(content)

    except Exception as e:
        print(f"Error processing {config_file}: {e}", file=sys.stderr)
        sys.exit(1)


def process_config_files(config_dir, replacements):
    """
    Process all config files in the directory with the given replacements.

    Args:
        config_dir: Directory containing config files
        replacements: List of (search, replace) tuples
    """
    # Find all config files
    config_files = find_config_files(config_dir)

    if not config_files:
        print(f"Warning: No config files found in {config_dir}", file=sys.stderr)
        return

    # Process each file
    for config_file in config_files:
        process_single_file(config_file, replacements)


def main():
    parser = argparse.ArgumentParser(
        description="Process configuration files by performing string substitutions.",
        epilog="Replacement arguments must be provided in pairs: search1 replace1 search2 replace2 ...",
    )

    parser.add_argument(
        "config_dir", help="Directory containing configuration files to process"
    )

    parser.add_argument(
        "replacements",
        nargs="*",
        help="Search/replace pairs (must be even number of arguments)",
    )

    args = parser.parse_args()

    # Validate replacement pairs
    if len(args.replacements) % 2 != 0:
        parser.error("Replacement arguments must come in pairs (search replace)")

    # Build replacement list
    replacements = []
    for i in range(0, len(args.replacements), 2):
        search = args.replacements[i]
        replace = args.replacements[i + 1]
        replacements.append((search, replace))

    process_config_files(args.config_dir, replacements)


if __name__ == "__main__":
    main()

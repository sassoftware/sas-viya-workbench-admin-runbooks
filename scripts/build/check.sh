#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Shell script linting checker for workbench-admin-runbooks project.
# Runs shellcheck on all .sh files in the scripts directory
# Validates script syntax and best practices compliance.
# Also checks formatting.

set -euf -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

find "${WORKSPACE_DIR}/scripts" -type f -name "*.sh" | while read -r script; do
  dir=$(dirname "$script")
  file=$(basename "$script")
  echo "Checking ${script} ..."
  cd "${dir}"
  shellcheck -x "${file}"
done

echo
echo "Checking formatting ..."
shfmt -d -i 2 -ci -s "${WORKSPACE_DIR}/scripts"

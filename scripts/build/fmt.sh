#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Shell script formatter for workbench-admin-runbooks project
# Formats all .sh files in the scripts directory using shfmt
# Applies consistent indentation and style formatting

set -euf -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${WORKSPACE_DIR}"

shfmt -d -i 2 -ci -s -w "${WORKSPACE_DIR}/scripts"

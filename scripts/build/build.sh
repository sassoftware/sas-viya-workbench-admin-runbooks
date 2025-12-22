#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Build script for workbench-admin-runbooks project
# Generates single executable scripts from runbook source files
# Creates distribution files in the dist/ directory for each cloud provider

set -euf -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

rm -rf "${WORKSPACE_DIR}/dist"
mkdir -p "${WORKSPACE_DIR}/dist"

# Generates each runbook into single executable script.
find "${WORKSPACE_DIR}/scripts/runbooks" -mindepth 1 -maxdepth 1 -type d | while read -r runbook_dir; do
  if [[ "$(basename "${runbook_dir}")" == "commons" ]]; then
    continue
  fi

  runbook_name="$(basename "${runbook_dir}")"

  find "${runbook_dir}" -mindepth 1 -maxdepth 1 -type d | while read -r cloud_provider_dir; do
    if [[ "$(basename "${cloud_provider_dir}")" != "aws" ]] && [[ "$(basename "${cloud_provider_dir}")" != "azure" ]]; then
      continue
    fi

    cloud_provider_name="$(basename "${cloud_provider_dir}")"

    echo "Building ${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh ..."

    echo "" >"${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh"
    first=true
    while IFS= read -r line; do
      if [[ ${line} == source\ \"\$\(dirname\ \"\$0\"\)* ]]; then
        src_file=$(echo "${line}" | sed -E "s/^source \"\\\$\\(\\s*dirname \"\\\$0\"\\s*\\)(\\/.*)\"$/\1/")

        cat "${cloud_provider_dir}/${src_file}" >>"${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh"
      else
        if "${first}"; then
          echo "$line" >"${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh"
        else
          echo "$line" >>"${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh"
        fi
      fi
      first=false
    done <"${cloud_provider_dir}/main.sh"
    chmod +x "${WORKSPACE_DIR}/dist/${cloud_provider_name}_${runbook_name}.sh"
  done
done

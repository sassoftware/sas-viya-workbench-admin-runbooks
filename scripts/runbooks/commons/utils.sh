#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

install_dependencies() {
  local deps=("${@}")
  local confirm
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
      log_info "Do you want to install ${dep}? [y/N]: "
      read -r confirm
      if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_error "Dependency ${dep} not installed. Aborting."
        return 1
      fi
      log_progress "${dep} is not installed. Attempting to install..."

      # Detect package manager and install dependency
      if command -v yum &>/dev/null; then
        sudo yum install -y "${dep}"
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${dep}"
      elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y "${dep}"
      else
        log_error "No supported package manager found. Please install ${dep} manually."
        return 1
      fi
    fi
  done
}

# Verify required dependencies are installed
check_dependencies() {
  local deps=("${@}")

  log_progress "Checking whether dependencies are installed..."
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
      log_error "${dep} is required but not installed."
      return 1
    fi
  done
  log_success "Completed dependency check.."
  log ""
}

# Make sure these env vars are set
set_env_vars() {
  local env_vars=("${@}")

  log_progress "Setting env variables..."

  # Prompt for missing environment variables
  for env_var in "${env_vars[@]}"; do
    while [ -z "${!env_var:-}" ]; do
      log_info "Environment variable ${env_var} is not set."
      log -n "Enter value for ${env_var}: "
      read -r value
      if [ -n "${value}" ]; then
        export "${env_var}=${value}"
      fi
    done
  done
  log_success "Completed setting environment variables."
  log ""
}

# Interactive selection from a list of values with grid layout
# Displays options in a multi-column format for better readability
# Returns the selected item or prompts until valid choice is made
select_from_values() {
  local type="${1}"
  shift
  local items=("${@}")

  log ""
  log "Select ${type}:"

  # Get terminal width
  local width
  width=$(tput cols 2>/dev/null || echo 80)

  # Create numbered items
  local numbered_items=()
  for i in "${!items[@]}"; do
    numbered_items+=("$((i + 1)). ${items[i]}")
  done

  # Calculate layout
  local max_len=0
  for item in "${numbered_items[@]}"; do
    if ((${#item} > max_len)); then
      max_len=${#item}
    fi
  done
  max_len=$((max_len + 4)) # Add spacing

  local cols=$((width / max_len))
  if ((cols < 1)); then
    cols=1
  fi

  local rows=$(((${#numbered_items[@]} + cols - 1) / cols))

  # Print items in grid
  for ((r = 0; r < rows; r++)); do
    for ((c = 0; c < cols; c++)); do
      local i=$((c * rows + r))
      if ((i < ${#numbered_items[@]})); then
        printf "%-${max_len}s" "${numbered_items[i]}" >&2
      fi
    done
    log ""
  done

  log ""
  while true; do
    log "Enter ${type} number (1-${#items[@]}): "
    read -r choice
    if [[ ${choice} =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
      echo "${items[$((choice - 1))]}"
      return 0
    else
      log_error "Invalid choice. Try again."
    fi
  done
}

# Verify Vault authentication.
# Checks valid credentials are available
check_vault_login() {
  log_progress "Checking whether user have valid vault credentials..."

  local capabilities
  if ! capabilities=$(vault token capabilities "${SAS_WORKBENCH_SITE_ID}/workbench" 2>&1); then
    log_error "Vault is not authenticated. Please set valid environment variables 'VAULT_ADDR' and 'VAULT_TOKEN'."
    return 1
  fi

  if [ "${capabilities}" = "deny" ]; then
    log_error "Vault token does not have access to path '${SAS_WORKBENCH_SITE_ID}/workbench'. Please check 'VAULT_TOKEN' validity."
    return 1
  fi

  log_success "Completed check. Vault is authenticated."
  log ""
}

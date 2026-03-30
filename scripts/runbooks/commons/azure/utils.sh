#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Get timezone for Azure region
# Maps Azure region names to timezone identifiers compatible with Azure App Service/Functions WEBSITE_TIME_ZONE
# Returns Windows timezone ID for Azure Functions on Windows plans
# For Linux plans, use TZ environment variable with standard IANA timezone names
get_timezone() {
  local region="${1}"

  # Azure Functions WEBSITE_TIME_ZONE requires Windows timezone IDs
  # Reference: https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings#website_time_zone
  local -A azure_timezones=(
    ["australiacentral"]="AUS Eastern Standard Time"
    ["australiacentral2"]="AUS Eastern Standard Time"
    ["australiaeast"]="AUS Eastern Standard Time"
    ["australiasoutheast"]="AUS Eastern Standard Time"
    ["brazilsouth"]="E. South America Standard Time"
    ["brazilsoutheast"]="E. South America Standard Time"
    ["canadacentral"]="Eastern Standard Time"
    ["canadaeast"]="Eastern Standard Time"
    ["centralindia"]="India Standard Time"
    ["centralus"]="Central Standard Time"
    ["eastasia"]="China Standard Time"
    ["eastus"]="Eastern Standard Time"
    ["eastus2"]="Eastern Standard Time"
    ["francecentral"]="Romance Standard Time"
    ["francesouth"]="Romance Standard Time"
    ["germanynorth"]="W. Europe Standard Time"
    ["germanywestcentral"]="W. Europe Standard Time"
    ["japaneast"]="Tokyo Standard Time"
    ["japanwest"]="Tokyo Standard Time"
    ["koreacentral"]="Korea Standard Time"
    ["koreasouth"]="Korea Standard Time"
    ["northcentralus"]="Central Standard Time"
    ["northeurope"]="GMT Standard Time"
    ["norwayeast"]="W. Europe Standard Time"
    ["norwaywest"]="W. Europe Standard Time"
    ["southafricanorth"]="South Africa Standard Time"
    ["southafricawest"]="South Africa Standard Time"
    ["southcentralus"]="Central Standard Time"
    ["southeastasia"]="Singapore Standard Time"
    ["southindia"]="India Standard Time"
    ["swedencentral"]="W. Europe Standard Time"
    ["switzerlandnorth"]="W. Europe Standard Time"
    ["switzerlandwest"]="W. Europe Standard Time"
    ["uaecentral"]="Arabian Standard Time"
    ["uaenorth"]="Arabian Standard Time"
    ["uksouth"]="GMT Standard Time"
    ["ukwest"]="GMT Standard Time"
    ["westcentralus"]="Mountain Standard Time"
    ["westeurope"]="W. Europe Standard Time"
    ["westindia"]="India Standard Time"
    ["westus"]="Pacific Standard Time"
    ["westus2"]="Pacific Standard Time"
    ["westus3"]="US Mountain Standard Time"
  )

  if [[ -n ${azure_timezones[${region}]} ]]; then
    echo "${azure_timezones[${region}]}"
  else
    log_error "Time zone not found for region: '${region}'"
    return 1
  fi
}

# Azure CLI wrapper with error handling
az_cmd() {
  local output
  if ! output=$(az "${@}" 2>&1); then
    log_error "Azure CLI command failed: az ${*}"
    log_error "Output: ${output}"

    if echo "${output}" | grep -q "ResourceNotFound"; then
      return "${STATUS_CODE_RESOURCE_NOT_FOUND}"
    fi

    if echo "${output}" | grep -q "(ResourceGroupNotFound)"; then
      return "${STATUS_CODE_RESOURCE_NOT_FOUND}"
    fi

    return "${STATUS_CODE_ERROR}"
  fi
  echo "${output}"
}

# Verify Azure authentication.
# Checks valid credentials are available
check_az_login() {
  log_progress "Checking whether user have valid Azure credentials..."

  if ! az_cmd account show >/dev/null 2>&1; then
    log_error "Azure CLI is not authenticated."
    return 1
  fi

  log_success "Completed check. User has valid Azure credentials."
  log ""
}

# Determines Azure region from environment or interactive selection
# First attempts to retrieve region from Azure CLI config
# Falls back to AZURE_LOCATION environment variable
# If no valid region found, prompts user to select from available regions
# Returns validated region name for subsequent Azure operations
select_region() {
  log_progress "Checking whether region is set..."

  local region

  local available_regions
  if ! available_regions=$(
    az_cmd account list-locations \
      --query '[].name' \
      --output tsv | tr '\t' '\n' | sort
  ); then
    return 1
  fi

  region="${AZURE_LOCATION:-}"
  if [[ -n ${region} ]]; then
    # Validate region
    if echo "${available_regions}" | grep -q "^${region}$"; then
      log_success "Using region: ${region}."
      log ""
      echo "${region}"
      return 0
    else
      log_warning "Configured region '${region}' is not valid."
    fi
  fi

  log_info "Region is not selected."
  local available_regions_array
  readarray -t available_regions_array < <(echo "${available_regions}")
  region=$(select_from_values "region" "${available_regions_array[@]}")

  log_success "Using region: ${region}."
  log ""
  echo "${region}"
}

# Selects an AKS cluster in the specified region. Uses CLUSTER_NAME environment variable if set,
# otherwise prompts user to choose from available clusters. Returns the selected cluster name.
select_aks_cluster() {
  local region="${1}"
  log_progress "Checking whether cluster is set..."

  local cluster_name

  local cluster_names
  if ! cluster_names=$(
    az_cmd aks list \
      --query "[?location=='${region}'].name" \
      --output tsv | tr '\t' '\n' | sort
  ); then
    return 1
  fi

  if [[ -z ${cluster_names} ]]; then
    log_error "No EKS clusters found."
    return 1
  fi

  local cluster_name="${CLUSTER_NAME:-}"
  if [[ -n ${cluster_name} ]]; then
    if echo "${cluster_names}" | grep -q "^${cluster_name}$"; then
      log_success "Selected cluster: ${cluster_name}."
      log ""
      echo "${cluster_name}"
      return 0
    else
      log_warning "Configured cluster '${cluster_name}' is not valid."
    fi
  fi

  local cluster_names_array
  readarray -t cluster_names_array < <(echo "${cluster_names}")
  cluster_name=$(select_from_values "cluster" "${cluster_names_array[@]}")

  log_success "Selected cluster: ${cluster_name}."
  log ""
  echo "${cluster_name}"
}

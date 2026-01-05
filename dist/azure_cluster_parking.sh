#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -euf -o pipefail

#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Logging functions
# Note: All logging functions use >&2 to redirect output to stderr instead of stdout
# This separates log messages from actual program output, allowing proper piping and redirection

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Displays informational messages with blue color and info icon
log_info() {
  local spaces
  spaces=$(printf '%*s' "${INDENT}" '')
  echo -e "${BLUE}${spaces}ℹ️  ${1}${NC}" >&2
}

# Displays success messages with green color and checkmark icon
log_success() {
  local spaces
  spaces=$(printf '%*s' "${INDENT}" '')
  echo -e "${GREEN}${spaces}✅ ${1}${NC}" >&2
}

# Displays warning messages with yellow color and warning icon
log_warning() {
  local spaces
  spaces=$(printf '%*s' "${INDENT}" '')
  echo -e "${YELLOW}${spaces}⚠️  ${1}${NC}" >&2
}

# Displays error messages with red color and error icon
log_error() {
  local spaces
  spaces=$(printf '%*s' "${INDENT}" '')
  echo -e "${RED}${spaces}❌ Error: ${1}${NC}" >&2
}

# Displays progress messages with blue color and hourglass icon
log_progress() {
  local spaces
  spaces=$(printf '%*s' "${INDENT}" '')
  echo -e "${BLUE}${spaces}⏳ ${1}${NC}" >&2
}

# Displays plain messages without formatting to stderr
log() {
  echo "${@}" >&2
}
#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Success status code
export STATUS_CODE_SUCCESS=0
# General error status code
export STATUS_CODE_ERROR=1
# Resource not found status code
export STATUS_CODE_RESOURCE_NOT_FOUND=100
# Resource already exists status code
export STATUS_CODE_RESOURCE_ALREADY_EXISTS=101
# Role not assumable status code
export STATUS_CODE_NOT_ASSUMABLE=102
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

#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Prefix used for naming all Azure resources related to cluster parking
# This ensures consistent naming across all resources
export RESOURCES_PREFIX="cluster-parking"
# Name of the Azure Resource Group that will contain all cluster parking resources
export RESOURCE_GROUP_NAME="${RESOURCES_PREFIX}-rg"
# Name of the Azure Storage Account used by the Function App
# Special characters are removed to comply with storage account naming requirements (alphanumeric only)
export STORAGE_ACCOUNT_NAME="${RESOURCES_PREFIX//[^a-z0-9]/}sa"
# Name of the Azure Function App that hosts the parking functions
export FUNCTION_APP_NAME="${RESOURCES_PREFIX}-function-app"
# Name of the Function within the Function App responsible for starting parked clusters
export START_FUNCTION_NAME="${RESOURCES_PREFIX}-start-function"
# Name of the Function within the Function App responsible for stopping/parking clusters
export STOP_FUNCTION_NAME="${RESOURCES_PREFIX}-stop-function"
#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Overrides default Azure resource names with custom prefix if RESOURCES_PREFIX_OVERRIDE is set
# Generates consistent naming across resource group, storage account, and function app resources
# Storage account name is sanitized to alphanumeric characters only per Azure requirements
override_azure_resources_names() {
  if [[ -z ${RESOURCES_PREFIX_OVERRIDE:-} ]]; then
    return 0
  fi

  # Prefix used for naming all Azure resources related to cluster parking
  # This ensures consistent naming across all resources
  export RESOURCES_PREFIX="${RESOURCES_PREFIX_OVERRIDE}"
  # Name of the Azure Resource Group that will contain all cluster parking resources
  export RESOURCE_GROUP_NAME="${RESOURCES_PREFIX}-rg"
  # Name of the Azure Storage Account used by the Function App
  # Special characters are removed to comply with storage account naming requirements (alphanumeric only)
  export STORAGE_ACCOUNT_NAME="${RESOURCES_PREFIX//[^a-z0-9]/}sa"
  # Name of the Azure Function App that hosts the parking functions
  export FUNCTION_APP_NAME="${RESOURCES_PREFIX}-function-app"
  # Name of the Function within the Function App responsible for starting parked clusters
  export START_FUNCTION_NAME="${RESOURCES_PREFIX}-start-function"
  # Name of the Function within the Function App responsible for stopping/parking clusters
  export STOP_FUNCTION_NAME="${RESOURCES_PREFIX}-stop-function"
}

# Constructs and validates a cron expression for starting or stopping clusters
# Accepts a region and status ("start" or "stop") as parameters
# Returns a validated cron expression, either from environment variables or user input
construct_cron() {
  local region="$1"
  local status="$2"

  local INDENT=$((INDENT + 2))
  log_progress "Constructing ${status} cron expressions..."

  local response
  local status_code

  local cron
  local header
  if [[ ${status} == "start" ]]; then
    cron="${START_CRON:-}"
    header="Enter cron expression for starting cluster: "
  else
    cron="${STOP_CRON:-}"
    header="Enter cron expression for stopping cluster: "
  fi

  if [[ -n ${cron} ]]; then
    response=$(validate_cron "${cron}" 2>&1)
    status_code="${?}"

    if [ "${status_code}" -eq 0 ]; then
      log_success "Using configured ${status} cron expression: '${cron}'."
      log ""
      echo "${cron}"
      return 0
    else
      log_warning "${response}"
      log_warning "Configured ${status} cron expression '${cron}' is not valid."
      cron=""
    fi
  fi

  while true; do
    if [[ -z ${cron} ]]; then
      log -n "${header}"
      read -r cron
    fi

    response=$(validate_cron "${cron}" 2>&1)
    status_code="${?}"

    if [ "${status_code}" -eq 0 ]; then
      log_success "Using ${status} cron expression: '${cron}'."
      log ""
      echo "${cron}"
      break
    else
      log_warning "${response}"
      log_warning "Invalid cron expression '${cron}', please try again."
      cron=""
    fi
  done
}

# Creates or updates an Azure Resource Group in the specified region
upsert_resource_group() {
  local region="$1"

  local response
  local status_code

  log_progress "Upserting resource group '${RESOURCE_GROUP_NAME}'..."
  local INDENT=$((INDENT + 2))
  response=$(
    az_cmd group show \
      --name "${RESOURCE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  if [ "${status_code}" -eq "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_progress "Creating resource group '${RESOURCE_GROUP_NAME}'..."
    if ! az_cmd group create \
      --name "${RESOURCE_GROUP_NAME}" \
      --location "${region}" >/dev/null; then
      return 1
    fi
  else
    log_progress "Updating resource group '${RESOURCE_GROUP_NAME}'..."
    if ! az_cmd group update \
      --name "${RESOURCE_GROUP_NAME}" >/dev/null; then
      return 1
    fi
  fi
  INDENT=$((INDENT - 2))
  log_success "Resource group ${RESOURCE_GROUP_NAME} is upserted."
  log ""
}

# Creates or updates an Azure Storage Account in the specified region
# Uses Standard_LRS SKU and enforces TLS 1.2 minimum version for security
upsert_storage_account() {
  local region="$1"

  local response
  local status_code

  log_progress "Upserting storage account '${STORAGE_ACCOUNT_NAME}'..."
  local INDENT=$((INDENT + 2))
  response=$(
    az_cmd storage account show \
      --name "${STORAGE_ACCOUNT_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi
  if [ "${status_code}" -eq "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_progress "Creating storage account '${STORAGE_ACCOUNT_NAME}'..."
    if ! az_cmd storage account create \
      --name "${STORAGE_ACCOUNT_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --location "${region}" \
      --sku Standard_LRS \
      --min-tls-version TLS1_2 >/dev/null; then
      return 1
    fi
  else
    log_progress "Updating storage account '${STORAGE_ACCOUNT_NAME}'..."
    if ! az_cmd storage account update \
      --name "${STORAGE_ACCOUNT_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --sku Standard_LRS \
      --min-tls-version TLS1_2 >/dev/null; then
      return 1
    fi
  fi

  INDENT=$((INDENT - 2))
  log_success "Storage account ${STORAGE_ACCOUNT_NAME} is upserted."
  log ""
}

# Creates or updates an Azure Function App in the specified region with PowerShell runtime
# Configures managed identity and assigns Contributor role to the AKS cluster for start/stop operations
# Sets timezone and app settings for proper function execution
upsert_function_app() {
  local region="$1"
  local cluster_name="$2"

  local response
  local status_code

  log_progress "Upserting function app '${FUNCTION_APP_NAME}'..."
  local INDENT=$((INDENT + 2))
  response=$(
    az_cmd functionapp show \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  if [ "${status_code}" -eq "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_progress "Creating function app '${FUNCTION_APP_NAME}'..."
    if ! az_cmd functionapp create \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --storage-account "${STORAGE_ACCOUNT_NAME}" \
      --consumption-plan-location "${region}" \
      --functions-version 4 \
      --runtime powershell \
      --os-type Windows >/dev/null; then
      return 1
    fi
  fi

  log_progress "Updating function app '${FUNCTION_APP_NAME}'..."
  if ! az_cmd functionapp update \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --set publicNetworkAccess=Disabled httpsOnly=true >/dev/null; then
    return 1
  fi

  local timezone
  if ! timezone=$(get_timezone "${region}"); then
    return 1
  fi

  log_progress "Configuring settings for function app '${FUNCTION_APP_NAME}'..."
  if ! az_cmd functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --settings "PSWorkerInProcConcurrencyUpperBound=1" "FUNCTIONS_WORKER_RUNTIME_VERSION=7.2" "WEBSITE_TIME_ZONE=${timezone}" >/dev/null; then
    return 1
  fi

  log_progress "Creating role assignment for function app '${FUNCTION_APP_NAME}'..."
  if ! az_cmd functionapp identity assign \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" >/dev/null; then
    return 1
  fi
  local function_app_principal_id
  if ! function_app_principal_id=$(az_cmd functionapp identity show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --query principalId -o tsv 2>&1); then
    return 1
  fi

  local cluster_id
  if ! cluster_id=$(az_cmd aks list \
    --query "([?location=='${region}' && name=='${cluster_name}'] | [0]).id" \
    --output tsv 2>&1); then
    return 1
  fi

  local retry_count=0
  local max_retries=1
  local retry_delay=1
  while [ "${retry_count}" -lt "${max_retries}" ]; do
    response=$(
      az_cmd role assignment create \
        --assignee-object-id "${function_app_principal_id}" \
        --assignee-principal-type ServicePrincipal \
        --role "Contributor" \
        --scope "${cluster_id}" 2>&1
    )
    status_code="${?}"
    if [ "${status_code}" -eq "${STATUS_CODE_SUCCESS}" ]; then
      break
    fi
    retry_count=$((retry_count + 1))
    if [ "${retry_count}" -lt "${max_retries}" ]; then
      log_warning "Role assignment failed, retrying in ${retry_delay} seconds (attempt ${retry_count}/${max_retries})..."
      sleep "${retry_delay}"
    else
      log_error "${response}"
      log_error "Role assignment failed after ${max_retries} attempts."
      return 0
    fi
  done

  INDENT=$((INDENT - 2))
  log_success "Function app '${FUNCTION_APP_NAME}' is upserted."
  log ""
}

# Creates and deploys PowerShell functions to Azure Function App for starting/stopping AKS clusters
# Generates function.json with cron schedules and run.ps1 scripts with cluster details
# Temporarily enables public access for deployment, then disables it after successful deployment
upsert_functions() {
  local region="$1"
  local cluster_name="$2"
  local start_cron="$3"
  local stop_cron="$4"

  log_progress "Upserting functions in function app '${FUNCTION_APP_NAME}'..."
  local INDENT=$((INDENT + 2))

  local temp_dir
  temp_dir=$(mktemp -d)

  log_progress "Preparing function app package in directory '${temp_dir}'..."

  cat >"${temp_dir}/requirements.psd1" <<'EOF'
@{
  'Az.Accounts' = '2.*'
  'Az.Aks'      = '6.*'
}
EOF

  cat >"${temp_dir}/profile.ps1" <<'EOF'
# Azure Functions profile.ps1
# Modules are automatically loaded by the Azure Functions runtime
Write-Host "Profile loaded successfully"
Import-Module Az.Accounts
Import-Module Az.Aks
EOF

  local cluster_resource_group
  if ! cluster_resource_group=$(
    az_cmd aks list \
      --query "([?location=='${region}' && name=='${cluster_name}'] | [0]).resourceGroup" \
      --output tsv
  ); then
    return 1
  fi

  mkdir -p "${temp_dir}/start-aks"
  local start_function_json
  start_function_json=$(
    cat <<'EOF'
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 START_CRON_PLACEHOLDER"
    }
  ]
}
EOF
  )
  start_function_json=${start_function_json//START_CRON_PLACEHOLDER/${start_cron}}
  echo "${start_function_json}" >"$temp_dir/start-aks/function.json"

  local start_script
  start_script=$(
    cat <<'EOF'
param($Timer)

$resourceGroup = "RESOURCE_GROUP_PLACEHOLDER"
$clusterName = "CLUSTER_NAME_PLACEHOLDER"

try {
  Write-Host "Starting AKS cluster $clusterName in resource group $resourceGroup"

  # Authenticate using Managed Identity
  if ($env:MSI_SECRET) {
    Write-Host "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity
    Write-Host "Authentication successful"
  }

  # Start the cluster
  Start-AzAksCluster -ResourceGroupName $resourceGroup -Name $clusterName -NoWait
  Write-Host "Start request for AKS cluster $clusterName submitted successfully"
}
catch {
  Write-Error "Error starting AKS cluster: $_"
  throw
}
EOF
  )
  start_script=${start_script//RESOURCE_GROUP_PLACEHOLDER/${cluster_resource_group}}
  start_script=${start_script//CLUSTER_NAME_PLACEHOLDER/${cluster_name}}
  echo "${start_script}" >"${temp_dir}/start-aks/run.ps1"

  mkdir -p "${temp_dir}/stop-aks"
  local stop_function_json
  stop_function_json=$(
    cat <<'EOF'
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 STOP_CRON_PLACEHOLDER"
    }
  ]
}
EOF
  )
  stop_function_json=${stop_function_json//STOP_CRON_PLACEHOLDER/${stop_cron}}
  echo "${stop_function_json}" >"$temp_dir/stop-aks/function.json"

  local stop_script
  stop_script=$(
    cat <<'EOF'
param($Timer)

$resourceGroup = "RESOURCE_GROUP_PLACEHOLDER"
$clusterName = "CLUSTER_NAME_PLACEHOLDER"

try {
  Write-Host "Stopping AKS cluster $clusterName in resource group $resourceGroup"

  # Authenticate using Managed Identity
  if ($env:MSI_SECRET) {
    Write-Host "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity
    Write-Host "Authentication successful"
  }

  # Stop the cluster
  Stop-AzAksCluster -ResourceGroupName $resourceGroup -Name $clusterName -NoWait
  Write-Host "Stop request for AKS cluster $clusterName submitted successfully"
}
catch {
  Write-Error "Error stopping AKS cluster: $_"
  throw
}
EOF
  )
  stop_script=${stop_script//RESOURCE_GROUP_PLACEHOLDER/${cluster_resource_group}}
  stop_script=${stop_script//CLUSTER_NAME_PLACEHOLDER/${cluster_name}}
  echo "${stop_script}" >"${temp_dir}/stop-aks/run.ps1"

  (cd "${temp_dir}" && zip -r "function-app.zip" . -x "function-app.zip") >/dev/null

  if ! az_cmd functionapp update \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --set publicNetworkAccess=Enabled >/dev/null; then
    return 1
  fi

  log_progress "Deploying function app package to function app '${FUNCTION_APP_NAME}'..."
  if ! az_cmd functionapp deployment source config-zip \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --src "${temp_dir}/function-app.zip" >/dev/null; then
    return 1
  fi

  if ! az_cmd functionapp update \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --set publicNetworkAccess=Disabled >/dev/null; then
    return 1
  fi

  if ! az_cmd functionapp restart \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" >/dev/null; then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Functions in function app '${FUNCTION_APP_NAME}' are deployed."
  log ""
}
#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Validates a 5-part cron expression (minute hour day month weekday).
# Checks each field is within valid ranges, supports wildcards, ranges, and comma-separated values.
# Ensures day of month and day of week aren't both specified (at least one must be *).
validate_cron() {
  local cron="$1"

  if [[ -z ${cron} ]]; then
    log "Cron expression must be specified."
    return 1
  fi

  IFS=' ' read -ra cron_parts <<<"${cron}"
  if [[ ${#cron_parts[@]} -ne 5 ]]; then
    log "Cron expression must have exactly 5 space-separated parts."
    return 1
  fi

  local minute="${cron_parts[0]}"
  local hour="${cron_parts[1]}"
  local day_of_month="${cron_parts[2]}"
  local month="${cron_parts[3]}"
  local day_of_week="${cron_parts[4]}"

  # Common function to validate a cron field with ranges, comma-separated values, or wildcards
  validate_cron_field() {
    local field_name="${1}"
    local field_value="${2}"
    local min_value="${3}"
    local max_value="${4}"

    if [[ ${field_value} =~ ^[0-9,\-]+$ ]]; then
      # Check ranges (e.g., 0-30)
      if [[ ${field_value} =~ - ]]; then
        IFS='-' read -ra range <<<"${field_value}"
        if [[ ${#range[@]} -ne 2 ]] || [[ ${range[0]} -lt ${min_value} ]] || [[ ${range[1]} -gt ${max_value} ]] || [[ ${range[0]} -gt ${range[1]} ]]; then
          log "${field_name} range must be in format ${min_value}-${max_value} with valid start and end values."
          return 1
        fi
      # Check comma-separated values (e.g., 0,15,30,45)
      elif [[ ${field_value} =~ , ]]; then
        IFS=',' read -ra values <<<"${field_value}"
        for val in "${values[@]}"; do
          if [[ ! ${val} =~ ^[0-9]+$ ]] || [[ ${val} -lt ${min_value} ]] || [[ ${val} -gt ${max_value} ]]; then
            log "Each ${field_name} value must be a number between ${min_value} and ${max_value}."
            return 1
          fi
        done
      # Check single value
      else
        if [[ ${field_value} -lt ${min_value} ]] || [[ ${field_value} -gt ${max_value} ]]; then
          log "${field_name} must be between ${min_value} and ${max_value}."
          return 1
        fi
      fi
    elif [[ ${field_value} == "*" ]]; then
      # Wildcard is valid
      return 0
    else
      log "${field_name} must be a number, range (${min_value}-${max_value}), comma-separated values, or *."
      return 1
    fi
  }

  # Validate each field using the common function
  validate_cron_field "Minutes" "${minute}" 0 59 || return 1
  validate_cron_field "Hours" "${hour}" 0 23 || return 1
  validate_cron_field "Day of month" "${day_of_month}" 1 31 || return 1
  validate_cron_field "Month" "${month}" 1 12 || return 1
  validate_cron_field "Day of week" "${day_of_week}" 0 6 || return 1

  # Validate that both day_of_month and day_of_week are not specified at the same time
  if [[ ${day_of_month} != "*" ]] && [[ ${day_of_week} != "*" ]]; then
    log "Both day of month and day of week cannot be specified. At least one must be *."
    return 1
  fi
}
#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Schedules automatic start/stop operations for an AKS cluster using Azure Functions.
# Creates necessary Azure resources (resource group, storage account, function app) and configures
# cron-based triggers, storing schedule information in Vault.
schedule() {
  if ! install_dependencies "zip"; then
    return 1
  fi

  if ! check_dependencies "az" "vault"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_az_login; then
    return 1
  fi

  # if ! check_vault_login; then
  #   return 1
  # fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  local cluster_name
  if ! cluster_name=$(select_aks_cluster "${region}"); then
    return 1
  fi

  if ! override_azure_resources_names; then
    return 1
  fi

  log_info "🚀 Starting scheduling..."

  local start_cron
  if ! start_cron=$(construct_cron "${region}" "start"); then
    return 1
  fi

  local stop_cron
  if ! stop_cron=$(construct_cron "${region}" "stop"); then
    return 1
  fi

  local INDENT=$((INDENT + 2))
  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   start_cron="${start_cron}" \
  #   stop_cron="${stop_cron}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="creating" >/dev/null; then
  #   return 1
  # fi
  # log_success "Updated vault with scheduling info."
  # log ""

  if ! upsert_resource_group "${region}"; then
    return 1
  fi

  if ! upsert_storage_account "${region}"; then
    return 1
  fi

  if ! upsert_function_app "${region}" "${cluster_name}"; then
    return 1
  fi

  if ! upsert_functions "${region}" "${cluster_name}" "${start_cron}" "${stop_cron}"; then
    return 1
  fi

  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   start_cron="${start_cron}" \
  #   stop_cron="${stop_cron}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="created" >/dev/null; then
  #   return 1
  # fi
  # log_success "Updated vault with scheduling info."
  # log ""
  INDENT=$((INDENT - 2))

  log_success "Completed scheduling."
}

# Starts an Azure AKS cluster after validating dependencies, environment variables, and credentials.
# Prompts user to select region and cluster, then starts the cluster and updates Vault with scheduling info.
start() {
  if ! check_dependencies "aws" "jq"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_az_login; then
    return 1
  fi

  # if ! check_vault_login; then
  #   return 1
  # fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  local cluster_name
  if ! cluster_name=$(select_aks_cluster "${region}"); then
    return 1
  fi

  if ! override_azure_resources_names; then
    return 1
  fi

  log_progress "Starting the AKS cluster..."
  local INDENT=$((INDENT + 2))

  local cluster_resource_group
  cluster_resource_group=$(
    az_cmd aks list \
      --query "([?location=='${region}' && name=='${cluster_name}'] | [0]).resourceGroup" \
      --output tsv
  )

  if ! az_cmd aks start \
    --name "${cluster_name}" \
    --resource-group "${cluster_resource_group}" \
    --no-wait >/dev/null; then
    return 1
  fi

  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="manually started" >/dev/null; then
  #   return 1
  # fi
  # log_success "Updated vault with scheduling info."

  INDENT=$((INDENT - 2))

  log_success "Started EKS cluster."
  log ""
}

# Stops an Azure AKS cluster after validating dependencies, authentication, and environment variables.
# Prompts user to select a region and cluster, then stops the cluster and updates Vault with scheduling info.
stop() {
  if ! check_dependencies "aws" "jq"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_az_login; then
    return 1
  fi

  # if ! check_vault_login; then
  #   return 1
  # fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  local cluster_name
  if ! cluster_name=$(select_aks_cluster "${region}"); then
    return 1
  fi

  if ! override_azure_resources_names; then
    return 1
  fi

  log_progress "Stopping the AKS cluster..."
  local INDENT=$((INDENT + 2))

  local cluster_resource_group
  cluster_resource_group=$(
    az_cmd aks list \
      --query "([?location=='${region}' && name=='${cluster_name}'] | [0]).resourceGroup" \
      --output tsv
  )

  if ! az_cmd aks stop \
    --name "${cluster_name}" \
    --resource-group "${cluster_resource_group}" \
    --no-wait >/dev/null; then
    return 1
  fi

  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="manually stopped" >/dev/null; then
  #   return 1
  # fi
  # log_success "Updated vault with scheduling info."

  INDENT=$((INDENT - 2))
  log_success "Stopped EKS cluster."
  log ""
}

# Deletes Azure resources for cluster parking scheduling including function app role assignments,
# resource groups, and updates Vault with deletion status. Validates dependencies and Azure/Vault
# authentication before proceeding with resource cleanup.
delete() {
  if ! check_dependencies "az" "jq"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_az_login; then
    return 1
  fi

  # if ! check_vault_login; then
  #   return 1
  # fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  local cluster_name
  if ! cluster_name=$(select_aks_cluster "${region}"); then
    return 1
  fi

  if ! override_azure_resources_names; then
    return 1
  fi

  local response
  local status_code

  log_progress "🚀 Starting deleting resources of scheduling..."

  local INDENT=$((INDENT + 2))

  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="deleting" >/dev/null; then
  #   return 1
  # fi

  log_progress "Deleting role assignment..."

  response=$(
    az_cmd functionapp identity show \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP_NAME}" \
      --query principalId -o tsv 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  if [ "${status_code}" -eq "${STATUS_CODE_SUCCESS}" ]; then
    local function_app_principal_id="${response}"
    local cluster_id
    cluster_id=$(az_cmd aks list --query "[?location=='${region}' && name=='${cluster_name}'].id" | jq -r '.[0]')

    az_cmd role assignment delete \
      --assignee-object-id "${function_app_principal_id}" \
      --role "Contributor" \
      --scope "${cluster_id}" >/dev/null
  fi

  log_progress "Deleting resource group..."
  response=$(
    az_cmd group delete \
      --name "${RESOURCE_GROUP_NAME}" \
      --yes 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  # log_progress "Updating vault with scheduling info..."
  # if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
  #   date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  #   status="deleted" >/dev/null; then
  #   return 1
  # fi

  INDENT=$((INDENT - 2))
  log_success "Completed deleting created resources of scheduling'."
}

# Usage functions
# Display main help message with available actions
usage() {
  cat <<EOF
Usage: $0 <action> [options]

Actions:
    schedule    Schedule start/stop Azure functions using timer triggers
    delete      Delete created resources for scheduling
    start       Starts AKS cluster
    stop        Stops AKS cluster

Use '$0 <action> --help' for action-specific help.

Examples:
    $0 schedule --help
    $0 delete --help
    $0 start --help
    $0 stop --help

EOF
}

# Show help for schedule action
usage_schedule() {
  cat <<EOF
Usage: $0 schedule [options]

Schedule start/stop Azure functions using timer triggers

Options:
    -h, --help             Show this help message

Examples:
    $0 schedule
    $0 schedule --help

Environment variables:
    AZURE_LOCATION                    Azure location to use
    CLUSTER_NAME                      AKS cluster name
    START_CRON                        Cron expression for starting nodes
    STOP_CRON                         Cron expression for stopping nodes
    RESOURCES_PREFIX_OVERRIDE         Override default Azure resources prefix (cluster-parking)
EOF
}

# Show help for start action
usage_start() {
  cat <<EOF
Usage: $0 start [options]

Starts AKS cluster.

Options:
    -h, --help             Show this help message

Examples:
    $0 start
    $0 start --help

Environment variables:
    AZURE_LOCATION                    Azure location to use
    CLUSTER_NAME                      AKS cluster name
    RESOURCES_PREFIX_OVERRIDE         Override default Azure resources prefix (cluster-parking)
EOF
}

# Show help for stop action
usage_stop() {
  cat <<EOF
Usage: $0 stop [options]

Stops AKS cluster.

Options:
    -h, --help             Show this help message

Examples:
    $0 stop
    $0 stop --help

Environment variables:
    AZURE_LOCATION                    Azure location to use
    CLUSTER_NAME                      AKS cluster name
    RESOURCES_PREFIX_OVERRIDE         Override default Azure resources prefix (cluster-parking)
EOF
}

# Show help for delete action
usage_delete() {
  cat <<EOF
Usage: $0 delete

Delete created resources for scheduling, including Azure function, EventBridge rules, IAM roles, and log groups.

Options:
    -h, --help             Show this help message

Examples:
    $0 delete
    $0 delete --help

Environment variables:
    AZURE_LOCATION                    Azure location to use
    CLUSTER_NAME                      AKS cluster name
    RESOURCES_PREFIX_OVERRIDE         Override default Azure resources prefix (cluster-parking)
EOF
}

# Main entry point for script execution
# Parses command line arguments and routes to appropriate action
main() {
  export INDENT=0
  export AWS_PAGER=""

  # Parse arguments
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local action="$1"
  shift

  case "$action" in
    schedule)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h | --help)
            usage_schedule
            return 0
            ;;
          *)
            log_error "Unknown option: $1"
            usage_schedule
            return 1
            ;;
        esac
      done

      if ! schedule; then
        log_error "Schedule operation failed."
        return 1
      fi
      ;;
    start)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h | --help)
            usage_start
            return 0
            ;;
          *)
            log_error "Unknown option: $1"
            usage_start
            return 1
            ;;
        esac
      done

      if ! start; then
        log_error "Start operation failed."
        return 1
      fi
      ;;
    stop)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h | --help)
            usage_stop
            return 0
            ;;
          *)
            log_error "Unknown option: $1"
            usage_stop
            return 1
            ;;
        esac
      done

      if ! stop; then
        log_error "Stop operation failed."
        return 1
      fi
      ;;
    delete)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h | --help)
            usage_delete
            return 0
            ;;
          *)
            log_error "Unknown option: $1"
            usage_delete
            return 1
            ;;
        esac
      done

      if ! delete; then
        log_error "Delete operation failed."
        return 1
      fi
      ;;

    -h | --help)
      usage
      return 0
      ;;

    *)
      log_error "Unknown action: $action"
      usage
      return 1
      ;;
  esac
}

if ! main "${@}"; then
  exit 1
fi

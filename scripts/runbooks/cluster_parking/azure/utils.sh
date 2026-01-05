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

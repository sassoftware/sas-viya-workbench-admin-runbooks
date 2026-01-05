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

  if ! check_vault_login; then
    return 1
  fi

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
  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    start_cron="${start_cron}" \
    stop_cron="${stop_cron}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="creating" >/dev/null; then
    return 1
  fi
  log_success "Updated vault with scheduling info."
  log ""

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

  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    start_cron="${start_cron}" \
    stop_cron="${stop_cron}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="created" >/dev/null; then
    return 1
  fi
  log_success "Updated vault with scheduling info."
  log ""
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

  if ! check_vault_login; then
    return 1
  fi

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

  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="manually started" >/dev/null; then
    return 1
  fi
  log_success "Updated vault with scheduling info."

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

  if ! check_vault_login; then
    return 1
  fi

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

  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="manually stopped" >/dev/null; then
    return 1
  fi
  log_success "Updated vault with scheduling info."

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

  if ! check_vault_login; then
    return 1
  fi

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

  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="deleting" >/dev/null; then
    return 1
  fi

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

  log_progress "Updating vault with scheduling info..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="deleted" >/dev/null; then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Completed deleting created resources of scheduling'."
}

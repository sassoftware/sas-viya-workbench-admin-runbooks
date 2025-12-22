#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Creates AWS infrastructure for automated EKS cluster start/stop scheduling.
# Sets up Lambda function, EventBridge schedules, IAM roles.
# Configures cron-based schedules for cluster lifecycle management.
schedule() {
  if ! install_dependencies "zip"; then
    return 1
  fi

  if ! check_dependencies "aws" "jq" "zip"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_aws_login; then
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
  if ! cluster_name=$(select_eks_cluster "${region}"); then
    return 1
  fi

  if ! override_aws_resources_names; then
    return 1
  fi

  log_info "🚀 Starting scheduling  ..."

  local start_cron
  if ! start_cron=$(construct_cron "${region}" "start"); then
    return 1
  fi

  local stop_cron
  if ! stop_cron=$(construct_cron "${region}" "stop"); then
    return 1
  fi

  local INDENT=$((INDENT + 2))
  log_progress "Updating vault with scheduling info ..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    start_cron="${start_cron}" \
    stop_cron="${stop_cron}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="creating" >/dev/null; then
    return 1
  fi
  log_success "Updated vault with scheduling info."
  log ""
  INDENT=$((INDENT - 2))

  local lambda_role_arn
  if ! lambda_role_arn=$(upsert_lambda_role "${region}" "${cluster_name}"); then
    return 1
  fi

  local lambda_function_arn
  if ! lambda_function_arn=$(upsert_lambda_function "${region}" "${lambda_role_arn}"); then
    return 1
  fi

  local schedule_role_arn
  if ! schedule_role_arn=$(upsert_schedule_role "${region}"); then
    return 1
  fi

  if ! upsert_schedules "${region}" "${lambda_function_arn}" "${schedule_role_arn}" "${start_cron}" "${stop_cron}"; then
    return 1
  fi
  log ""

  INDENT=$((INDENT + 2))
  log_progress "Updating vault with scheduling info ..."
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

# Manually triggers the Lambda function to start the EKS cluster.
# Validates dependencies, AWS/Vault credentials, and invokes Lambda with 'start' action.
start() {
  if ! install_dependencies "zip"; then
    return 1
  fi

  if ! check_dependencies "aws" "jq" "zip"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_aws_login; then
    return 1
  fi

  if ! check_vault_login; then
    return 1
  fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  if ! override_aws_resources_names; then
    return 1
  fi

  log_progress "Starting the EKS cluster ..."
  local INDENT=$((INDENT + 2))

  if ! call_lambda_function "${region}" "start"; then
    return 1
  fi

  log_progress "Updating vault with scheduling info ..."
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

# Manually triggers the Lambda function to stop the EKS cluster.
# Validates dependencies, AWS/Vault credentials, and invokes Lambda with 'stop' action.
stop() {
  if ! install_dependencies "zip"; then
    return 1
  fi

  if ! check_dependencies "aws" "jq" "zip"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_aws_login; then
    return 1
  fi

  if ! check_vault_login; then
    return 1
  fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  if ! override_aws_resources_names; then
    return 1
  fi

  log_progress "Stopping the EKS cluster ..."
  local INDENT=$((INDENT + 2))

  if ! call_lambda_function "${region}" "stop"; then
    return 1
  fi

  log_progress "Updating vault with scheduling info ..."
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

# Remove all AWS resources created by the schedule action
# Cleans up Lambda function, EventBridge schedules, IAM roles and policies
delete() {
  if ! install_dependencies "zip"; then
    return 1
  fi

  if ! check_dependencies "aws" "jq" "zip"; then
    return 1
  fi

  if ! set_env_vars "VAULT_ADDR" "VAULT_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "SAS_WORKBENCH_SITE_ID"; then
    return 1
  fi

  if ! check_aws_login; then
    return 1
  fi

  if ! check_vault_login; then
    return 1
  fi

  local region
  if ! region=$(select_region); then
    return 1
  fi

  if ! override_aws_resources_names; then
    return 1
  fi

  local response
  local status_code

  log_progress "🚀 Starting deleting resources of scheduling' ..."

  local INDENT=$((INDENT + 2))

  log_progress "Updating vault with scheduling info ..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="deleting" >/dev/null; then
    return 1
  fi

  log_progress "Deleting start schedule ..."

  response=$(
    aws_cmd scheduler delete-schedule \
      --region "${region}" \
      --name "${FUNCTION_START_SCHEDULE_NAME}" \
      --group-name "${SCHEDULE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting stop schedule ..."
  response=$(
    aws_cmd scheduler delete-schedule \
      --region "${region}" \
      --name "${FUNCTION_STOP_SCHEDULE_NAME}" \
      --group-name "${SCHEDULE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting schedule group ..."
  response=$(
    aws_cmd scheduler delete-schedule-group \
      --region "${region}" \
      --name "${SCHEDULE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting lambda function's log group ..."
  response=$(
    aws_cmd logs delete-log-group \
      --region "${region}" \
      --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting lambda function ..."
  response=$(
    aws_cmd lambda delete-function \
      --region "${region}" \
      --function-name "${LAMBDA_FUNCTION_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting lambda IAM role policy ..."
  response=$(
    aws_cmd iam delete-role-policy \
      --region "${region}" \
      --role-name "${LAMBDA_ROLE_NAME}" \
      --policy-name "${LAMBDA_POLICY_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting lambda IAM role ..."
  response=$(
    aws_cmd iam delete-role \
      --region "${region}" \
      --role-name "${LAMBDA_ROLE_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting schedule IAM role policy ..."
  response=$(
    aws_cmd iam delete-role-policy \
      --region "${region}" \
      --role-name "${SCHEDULE_ROLE_NAME}" \
      --policy-name "${SCHEDULE_POLICY_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting schedule IAM role ..."
  response=$(
    aws_cmd iam delete-role \
      --region "${region}" \
      --role-name "${SCHEDULE_ROLE_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Deleting SSM parameter ..."
  response=$(
    aws_cmd ssm delete-parameter \
      --region "${region}" \
      --name "/SASWorkbench/lambda/${LAMBDA_FUNCTION_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_NOT_FOUND}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Updating vault with scheduling info ..."
  if ! vault kv put "${SAS_WORKBENCH_SITE_ID}/workbench/workbench-admin-runbooks/cluster_parking/${RESOURCES_PREFIX}" \
    date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    status="deleted" >/dev/null; then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Completed deleting created resources of scheduling'."
}

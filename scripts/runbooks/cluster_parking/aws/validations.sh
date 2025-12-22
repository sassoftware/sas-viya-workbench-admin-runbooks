#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Validates a cron expression by creating and deleting a temporary AWS EventBridge rule
# Returns 0 if valid, 1 if invalid or empty
validate_cron() {
  local cron="$1"
  local region="$2"

  local INDENT=$((INDENT + 2))
  if [[ -z ${cron} ]]; then
    log_error "Cron expression must be specified."
    return 1
  fi

  log_progress "Adding dummy cron expression event rule ..."
  if ! aws_cmd events put-rule \
    --region "${region}" \
    --name "${FUNCTION_TEMP_SCHEDULE_NAME}" \
    --state DISABLED \
    --schedule-expression "cron(${cron})" >/dev/null; then
    return 1
  fi

  log_progress "Deleting dummy cron expression event rule ..."
  aws_cmd events delete-rule \
    --region "${region}" \
    --name "${FUNCTION_TEMP_SCHEDULE_NAME}" \
    --force >/dev/null
}

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

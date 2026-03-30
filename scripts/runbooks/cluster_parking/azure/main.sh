#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -euf -o pipefail

source "$(dirname "$0")/../../commons/logs.sh"
source "$(dirname "$0")/../../commons/constants.sh"
source "$(dirname "$0")/../../commons/utils.sh"
source "$(dirname "$0")/../../commons/azure/utils.sh"

source "$(dirname "$0")/constants.sh"
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/validations.sh"
source "$(dirname "$0")/actions.sh"

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

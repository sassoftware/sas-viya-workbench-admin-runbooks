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

get_timezone() {
  local region="${1}"

  local -A aws_timezones=(
    ["af-south-1"]="Africa/Johannesburg"
    ["ap-east-1"]="Asia/Hong_Kong"
    ["ap-east-2"]="Asia/Kolkata"
    ["ap-northeast-1"]="Asia/Tokyo"
    ["ap-northeast-2"]="Asia/Seoul"
    ["ap-northeast-3"]="Asia/Tokyo"
    ["ap-south-1"]="Asia/Kolkata"
    ["ap-south-2"]="Asia/Kolkata"
    ["ap-southeast-1"]="Asia/Singapore"
    ["ap-southeast-2"]="Australia/Sydney"
    ["ap-southeast-3"]="Asia/Jakarta"
    ["ap-southeast-4"]="Australia/Melbourne"
    ["ap-southeast-5"]="Asia/Kuala_Lumpur"
    ["ap-southeast-6"]="Asia/Manila"
    ["ap-southeast-7"]="Asia/Bangkok"
    ["ca-central-1"]="America/Regina"
    ["ca-west-1"]="America/Vancouver"
    ["eu-central-1"]="Europe/Berlin"
    ["eu-central-2"]="Europe/Zurich"
    ["eu-north-1"]="Europe/Stockholm"
    ["eu-south-1"]="Europe/Rome"
    ["eu-south-2"]="Europe/Madrid"
    ["eu-west-1"]="Europe/Dublin"
    ["eu-west-2"]="Europe/London"
    ["eu-west-3"]="Europe/Paris"
    ["il-central-1"]="Asia/Jerusalem"
    ["me-central-1"]="Asia/Dubai"
    ["me-south-1"]="Asia/Bahrain"
    ["mx-central-1"]="America/Mexico_City"
    ["sa-east-1"]="America/Sao_Paulo"
    ["us-east-1"]="America/New_York"
    ["us-east-2"]="America/Chicago"
    ["us-gov-east-1"]="America/New_York"
    ["us-gov-west-1"]="America/Los_Angeles"
    ["us-west-1"]="America/Los_Angeles"
    ["us-west-2"]="America/Los_Angeles"
  )

  if [[ -n ${aws_timezones[${region}]} ]]; then
    echo "${aws_timezones[${region}]}"
  else
    log_error "Time zone not found for region: '${region}'"
    return 1
  fi
}

# AWS CLI wrapper with error handling
aws_cmd() {
  local output
  if ! output=$(aws "${@}" 2>&1); then
    log_error "AWS CLI command failed: aws ${*}"
    log_error "Output: ${output}"
    if echo "${output}" | grep -q "(ResourceNotFoundException)"; then
      return "${STATUS_CODE_RESOURCE_NOT_FOUND}"
    fi
    if echo "${output}" | grep -q "(NoSuchEntity)"; then
      return "${STATUS_CODE_RESOURCE_NOT_FOUND}"
    fi
    if echo "${output}" | grep -q "(ParameterNotFound)"; then
      return "${STATUS_CODE_RESOURCE_NOT_FOUND}"
    fi

    if echo "${output}" | grep -q "(ResourceAlreadyExistsException)"; then
      return "${STATUS_CODE_RESOURCE_ALREADY_EXISTS}"
    fi
    if echo "${output}" | grep -q "(ResourceConflictException)"; then
      return "${STATUS_CODE_RESOURCE_ALREADY_EXISTS}"
    fi
    if echo "${output}" | grep -q "(ConflictException)"; then
      return "${STATUS_CODE_RESOURCE_ALREADY_EXISTS}"
    fi

    if echo "${output}" | grep -q "cannot be assumed"; then
      return "${STATUS_CODE_NOT_ASSUMABLE}"
    fi
    if echo "${output}" | grep -q "The execution role you provide must allow AWS EventBridge Scheduler to assume the role."; then
      return "${STATUS_CODE_NOT_ASSUMABLE}"
    fi

    return "${STATUS_CODE_ERROR}"
  fi
  echo "${output}"
}

# Verify AWS authentication.
# Checks valid credentials are available
check_aws_login() {
  log_progress "Checking whether user have valid AWS credentials..."

  if ! aws_cmd --region "us-east-1" sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS CLI is not authenticated. Please set valid environment variables 'AWS_ACCESS_KEY_ID' and 'AWS_SECRET_ACCESS_KEY'."
    return 1
  fi

  log_success "Completed check. User has valid AWS credentials."
  log ""
}

# Determines AWS region from EC2 metadata, environment, or interactive selection
# First attempts to retrieve region from EC2 instance metadata service
# Falls back to AWS_REGION/AWS_DEFAULT_REGION environment variables or AWS CLI config
# If no valid region found, prompts user to select from available regions
# Returns validated region name for subsequent AWS operations
select_region() {
  log_progress "Checking whether region is set..."

  local region
  region=$(
    curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
      -H "X-aws-ec2-metadata-token: $(
        curl -s -X PUT "http://169.254.169.254/latest/api/token" \
          -H "X-aws-ec2-metadata-token-ttl-seconds: 30"
      )" |
      jq -r '.region' 2>/dev/null || true
  )

  if [[ -n ${region} ]]; then
    log_success "Using region: ${region}."
    log ""
    echo "${region}"
    return 0
  fi

  local available_regions
  if ! available_regions=$(
    aws_cmd ec2 describe-regions \
      --region us-east-1 \
      --query 'Regions[].RegionName' \
      --output text | tr '\t' '\n' | sort
  ); then
    return 1
  fi

  # Check for region in various places
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
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

# Selects EKS cluster from the region
# First attempts to retrieve cluster name from Terraform state
# Falls back to CLUSTER_NAME environment variable
# If no valid cluster found, prompts user to select from available clusters
# Returns validated cluster name for subsequent operations
select_eks_cluster() {
  local region="${1}"
  log_progress "Checking whether cluster is set..."

  local cluster_name
  cluster_name=$(
    jq -r '.outputs.cluster_name.value' ~/system-poi/state/aws/terraform.tfstate 2>/dev/null || true
  )
  if [[ -n ${cluster_name} ]]; then
    log_success "Using cluster: ${cluster_name}."
    log ""
    echo "${cluster_name}"
    return 0
  fi

  local cluster_names
  if ! cluster_names=$(
    aws_cmd eks list-clusters \
      --region "${region}" \
      --query 'clusters[]' \
      --output text | tr '\t' '\n' | sort
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

# Cluster Parking AWS Infrastructure Constants
# Contains all the constants used across the cluster parking AWS deployment scripts
# It defines Lambda function names, IAM roles, EventBridge schedules and related policies

export RESOURCES_PREFIX="update-wb-asg-sizes"
# Lambda function name for updating workbench ASG sizes
export LAMBDA_FUNCTION_NAME="${RESOURCES_PREFIX}-lambda-function"
# IAM execution role name for the Lambda function
export LAMBDA_ROLE_NAME="${RESOURCES_PREFIX}-lambda-role"
# IAM policy name attached to the lambda role
export LAMBDA_POLICY_NAME="${RESOURCES_PREFIX}-lambda-policy"
# Group name for schedules
export SCHEDULE_GROUP_NAME="${RESOURCES_PREFIX}-schedule-group"
# IAM execution role name for the Schedule
export SCHEDULE_ROLE_NAME="${RESOURCES_PREFIX}-schedule-role"
# IAM policy name attached to the schedule role
export SCHEDULE_POLICY_NAME="${RESOURCES_PREFIX}-schedule-policy"
# Temporary schedule name to test cron expressions
export FUNCTION_TEMP_SCHEDULE_NAME="${RESOURCES_PREFIX}-temp-schedule"
# Start schedule name for start operations
export FUNCTION_START_SCHEDULE_NAME="${RESOURCES_PREFIX}-start-schedule"
# Stop schedule name for stop operations
export FUNCTION_STOP_SCHEDULE_NAME="${RESOURCES_PREFIX}-stop-schedule"
#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Sets resource names for Lambda function and related AWS resources
# Uses RESOURCES_PREFIX_OVERRIDE if set, otherwise defaults to standard names
# Ensures consistent naming for IAM roles, policies, schedule groups, and schedules
override_aws_resources_names() {
  if [[ -z ${RESOURCES_PREFIX_OVERRIDE:-} ]]; then
    return 0
  fi

  export RESOURCES_PREFIX="${RESOURCES_PREFIX_OVERRIDE}"
  export LAMBDA_FUNCTION_NAME="${RESOURCES_PREFIX}-lambda-function"
  # IAM execution role name for the Lambda function
  export LAMBDA_ROLE_NAME="${RESOURCES_PREFIX}-lambda-role"
  # IAM policy name attached to the lambda role
  export LAMBDA_POLICY_NAME="${RESOURCES_PREFIX}-lambda-policy"
  # Group name for schedules
  export SCHEDULE_GROUP_NAME="${RESOURCES_PREFIX}-schedule-group"
  # IAM execution role name for the Schedule
  export SCHEDULE_ROLE_NAME="${RESOURCES_PREFIX}-schedule-role"
  # IAM policy name attached to the schedule role
  export SCHEDULE_POLICY_NAME="${RESOURCES_PREFIX}-schedule-policy"
  # Temporary schedule name to test cron expressions
  export FUNCTION_TEMP_SCHEDULE_NAME="${RESOURCES_PREFIX}-temp-schedule"
  # Start schedule name for start operations
  export FUNCTION_START_SCHEDULE_NAME="${RESOURCES_PREFIX}-start-schedule"
  # Stop schedule name for stop operations
  export FUNCTION_STOP_SCHEDULE_NAME="${RESOURCES_PREFIX}-stop-schedule"
}

# Creates and validates cron expressions for start/stop scheduling
# Prompts user for cron input if not configured via environment
# Returns validated cron expression for EventBridge scheduling
construct_cron() {
  local region="$1"
  local status="$2"

  local INDENT=$((INDENT + 2))
  log_progress "Constructing ${status} cron expressions ..."

  local cron
  local header
  if [[ ${status} == "start" ]]; then
    cron="${START_CRON:-}"
    header="Enter cron expression for starting nodes: "
  else
    cron="${STOP_CRON:-}"
    header="Enter cron expression for stopping nodes: "
  fi

  if [[ -n ${cron} ]]; then
    if validate_cron "${cron}" "${region}" 2>/dev/null; then
      log_success "Using configured ${status} cron expression: '${cron}'."
      log ""
      echo "${cron}"
      return 0
    else
      log_warning "Configured ${status} cron expression '${cron}' is not valid."
    fi
  fi

  while true; do
    if [[ -z ${cron} ]]; then
      log -n "${header}"
      read -r cron
    fi

    if validate_cron "${cron}" "${region}"; then
      log_success "Using ${status} cron expression: '${cron}'."
      log ""
      echo "${cron}"
      break
    else
      log_error "Invalid cron expression '${cron}', please try again."
      cron=""
    fi
  done
}

# Creates or updates IAM role with permissions for Lambda execution
# Configures trust policy and permissions required for lambda execution
# Returns role ARN for Lambda function association
upsert_lambda_role() {
  local region="${1}"
  local cluster_name="${2}"

  local response
  local status_code

  local INDENT=$((INDENT + 2))
  log_progress "Upserting lambda IAM role..."

  local INDENT=$((INDENT + 2))

  # Trust policy
  local assume_role_policy
  assume_role_policy=$(jq -n '{
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Principal: {
        Service: "lambda.amazonaws.com"
      },
      Action: "sts:AssumeRole"
    }]
  }')

  # Check if role exists
  response=$(
    aws_cmd iam get-role \
      --region "${region}" \
      --role-name "${LAMBDA_ROLE_NAME}" 2>&1
  )
  status_code="${?}"
  case "${status_code}" in
    "${STATUS_CODE_SUCCESS}")
      log_progress "Updating IAM role '${LAMBDA_ROLE_NAME}' ..."
      if ! aws_cmd iam update-assume-role-policy \
        --region "${region}" \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-document "${assume_role_policy}" >/dev/null; then
        return 1
      fi
      ;;
    "${STATUS_CODE_RESOURCE_NOT_FOUND}")
      log_info "IAM role '${LAMBDA_ROLE_NAME}' doesn't exist."
      log_progress "Creating IAM role '${LAMBDA_ROLE_NAME}' ..."
      if ! aws_cmd iam create-role \
        --region "${region}" \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document "${assume_role_policy}" >/dev/null; then
        return 1
      fi
      ;;
    *)
      log_error "${response}"
      return 1
      ;;
  esac

  # Get account ID
  log_progress "Getting account id ..."
  local account_id
  if ! account_id=$(
    aws_cmd sts get-caller-identity \
      --region "${region}" \
      --query Account \
      --output text
  ); then
    return 1
  fi

  # Create permission policy
  local permission_policy
  permission_policy=$(
    jq -n \
      --arg region "${region}" \
      --arg cluster_name "${cluster_name}" \
      --arg account_id "${account_id}" \
      --arg function_name "${LAMBDA_FUNCTION_NAME}" \
      '{
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Action: [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            Resource: [
              "arn:aws:logs:" + $region + ":" + $account_id + ":log-group:/aws/lambda/" + $function_name,
              "arn:aws:logs:" + $region + ":" + $account_id + ":log-group:/aws/lambda/" + $function_name + ":*"
            ]
          },
          {
            Effect: "Allow",
            Action: "eks:ListNodegroups",
            Resource: [
              "arn:aws:eks:" + $region + ":" + $account_id + ":cluster/" + $cluster_name
            ]
          },
          {
              Effect: "Allow",
              Action: "eks:DescribeNodegroup",
              Resource: [
                "arn:aws:eks:" + $region + ":" + $account_id + ":nodegroup/" + $cluster_name + "/*"
              ]
          },
          {
            Effect: "Allow",
            Action: [
              "autoscaling:DescribeAutoScalingGroups"
            ],
            Resource: "*"
          },
          {
            Effect: "Allow",
            Action: [
              "autoscaling:UpdateAutoScalingGroup"
            ],
            Resource: "*",
            "Condition": {
              "StringEquals": {
                "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true",
                ("aws:ResourceTag/k8s.io/cluster-autoscaler/" + $cluster_name): "owned"
              }
            }
          },
          {
            Effect: "Allow",
            Action: [
              "ssm:GetParameter",
              "ssm:PutParameter"
            ],
            Resource: [
              "arn:aws:ssm:" + $region + ":" + $account_id + ":parameter/SASWorkbench/lambda/" + $function_name
            ]
          }
        ]
    }'
  )

  if [[ -z ${permission_policy} ]]; then
    log_error "Failed to construct permission policy for IAM role."
    return 1
  fi

  log_progress "Updating IAM role '${LAMBDA_ROLE_NAME}' with permission policy ..."
  if ! aws_cmd iam put-role-policy \
    --region "${region}" \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --policy-name "${LAMBDA_POLICY_NAME}" \
    --policy-document "${permission_policy}" >/dev/null; then
    return 1
  fi

  log_progress "Getting IAM role '${LAMBDA_ROLE_NAME}' ARN ..."
  local arn
  if ! arn=$(
    aws_cmd iam get-role \
      --region "${region}" \
      --role-name "${LAMBDA_ROLE_NAME}" \
      --query 'Role.Arn' \
      --output text
  ); then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Upserted lambda IAM role '${LAMBDA_ROLE_NAME}' with ARN '${arn}'."
  log ""

  echo "${arn}"
}

# Creates or updates IAM role with permissions for Schedule execution
# Configures trust policy and permissions required for schedule execution
# Returns role ARN for scxheduler association
upsert_schedule_role() {
  local region="${1}"

  local response
  local status_code

  local INDENT=$((INDENT + 2))
  log_progress "Upserting schedule IAM role..."

  local INDENT=$((INDENT + 2))

  # Trust policy
  local assume_role_policy
  assume_role_policy=$(jq -n '{
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Principal: {
        Service: "scheduler.amazonaws.com"
      },
      Action: "sts:AssumeRole"
    }]
  }')

  # Check if role exists
  response=$(
    aws_cmd iam get-role \
      --region "${region}" \
      --role-name "${SCHEDULE_ROLE_NAME}" 2>&1
  )
  status_code="${?}"
  case "${status_code}" in
    "${STATUS_CODE_SUCCESS}")
      log_progress "Updating IAM role '${SCHEDULE_ROLE_NAME}' ..."
      if ! aws_cmd iam update-assume-role-policy \
        --region "${region}" \
        --role-name "${SCHEDULE_ROLE_NAME}" \
        --policy-document "${assume_role_policy}" >/dev/null; then
        return 1
      fi
      ;;
    "${STATUS_CODE_RESOURCE_NOT_FOUND}")
      log_info "IAM role '${SCHEDULE_ROLE_NAME}' doesn't exist."
      log_progress "Creating IAM role '${SCHEDULE_ROLE_NAME}' ..."
      if ! aws_cmd iam create-role \
        --region "${region}" \
        --role-name "${SCHEDULE_ROLE_NAME}" \
        --assume-role-policy-document "${assume_role_policy}" >/dev/null; then
        return 1
      fi
      ;;
    *)
      log_error "${response}"
      return 1
      ;;
  esac

  # Get account ID
  log_progress "Getting account id ..."
  local account_id
  if ! account_id=$(
    aws_cmd sts get-caller-identity \
      --region "${region}" \
      --query Account \
      --output text
  ); then
    return 1
  fi

  # Create permission policy
  local permission_policy
  permission_policy=$(
    jq -n \
      --arg region "${region}" \
      --arg account_id "${account_id}" \
      --arg function_name "${LAMBDA_FUNCTION_NAME}" \
      '{
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: "lambda:InvokeFunction",
              Resource: [
                "arn:aws:lambda:" + $region + ":" + $account_id + ":function:" + $function_name
              ]
            }
          ]
      }'
  )

  if [[ -z ${permission_policy} ]]; then
    log_error "Failed to construct permission policy for IAM role."
    return 1
  fi

  log_progress "Updating IAM role '${SCHEDULE_ROLE_NAME}' with permission policy ..."
  if ! aws_cmd iam put-role-policy \
    --region "${region}" \
    --role-name "${SCHEDULE_ROLE_NAME}" \
    --policy-name "${SCHEDULE_POLICY_NAME}" \
    --policy-document "${permission_policy}" >/dev/null; then
    return 1
  fi

  log_progress "Getting IAM role '${SCHEDULE_ROLE_NAME}' ARN ..."
  local arn
  if ! arn=$(
    aws_cmd iam get-role \
      --region "${region}" \
      --role-name "${SCHEDULE_ROLE_NAME}" \
      --query 'Role.Arn' \
      --output text
  ); then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Upserted IAM role '${SCHEDULE_ROLE_NAME}' with ARN '${arn}'."
  log ""

  echo "${arn}"
}

# Creates or updates Lambda function for EKS nodegroup autoscaling
# Packages Python code, manages function configuration and log retention
# Returns function ARN for schedule association
upsert_lambda_function() {
  local region="${1}"
  local role_arn="${2}"

  local response
  local status_code

  local INDENT=$((INDENT + 2))
  log_progress "Upserting lambda function ..."

  local INDENT=$((INDENT + 2))
  # Create Lambda function code
  local lambda_code
  lambda_code=$(
    cat <<'EOF'
import boto3
import json
from botocore.exceptions import ClientError

asg_client = boto3.client('autoscaling')
ssm_client = boto3.client('ssm')
eks_client = boto3.client('eks')


def lambda_handler(event, context):
  """
  Lambda expects an event like:
  {
      "status": "start|stop"
  }
  """

  print(f"Received event: {json.dumps(event)}")

  status = event.get("status")
  if status not in ["start", "stop"]:
    return {
      "statusCode": 400,
      "body": json.dumps({"error": "invalid status"})
    }

  try:
    stored_sizes = json.loads(ssm_client.get_parameter(Name="/SASWorkbench/lambda/LAMBDA_FUNCTION_NAME_PLACEHOLDER")['Parameter']['Value'])
    print(f"Stored sizes: {json.dumps(stored_sizes)}")
  except ClientError as e:
    if e.response['Error']['Code'] == 'ParameterNotFound':
      print("No stored sizes found.")
      stored_sizes = {}
    else:
      raise

  cluster_name = "CLUSTER_NAME_PLACEHOLDER"

  try:
    ng_names = eks_client.list_nodegroups(clusterName=cluster_name).get('nodegroups', [])

    stored_sizes_updated = False
    for ng_name in ng_names:
      print(f"Processing node group {ng_name}")
      asgs_details = eks_client.describe_nodegroup(
        clusterName=cluster_name,
        nodegroupName=ng_name
      )['nodegroup']['resources']['autoScalingGroups']

      for asg_details in asgs_details:
        asg_name = asg_details['name']
        print(f"Processing auto scaling group {asg_name}")

        asg = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])['AutoScalingGroups'][0]
        min_size = asg['MinSize']
        max_size = asg['MaxSize']
        desired_capacity = asg['DesiredCapacity']
        tags = asg.get('Tags', [])

        auto_scaling_enabled = False
        for tag in tags:
          if tag['Key'] == 'k8s.io/cluster-autoscaler/enabled' and tag['Value'] == 'true':
            auto_scaling_enabled = True
            break

        if auto_scaling_enabled:
          if status == "start":
            if min_size == 0 and max_size == 0: # In Stopped State
              if ng_name in stored_sizes and asg_name in stored_sizes[ng_name]: # This ASG is updated by this function
                  stored_asg = stored_sizes[ng_name][asg_name]
                  stored_min_size = stored_asg['min_size']
                  stored_max_size = stored_asg['max_size']
                  stored_desired_capacity = stored_asg['desired_capacity']
                  asg_client.update_auto_scaling_group(
                    AutoScalingGroupName=asg_name,
                    MinSize=stored_min_size,
                    MaxSize=stored_max_size,
                    DesiredCapacity=stored_desired_capacity
                  )
                  print(f"Auto scaling group updated successfully with sizes min_size={stored_min_size}, max_size={stored_max_size}, desired_capacity={stored_desired_capacity}.")
              else:
                print(f"Auto scaling group was not updated by this function. Skipping...")
            else:
                print(f"Auto scaling group is already started. Skipping...")
          else: # status == "stop"
            if max_size != 0: # In Started state
              if ng_name not in stored_sizes:
                stored_sizes[ng_name] = {}
              if asg_name not in stored_sizes[ng_name]:
                stored_sizes[ng_name][asg_name] = {}
              stored_sizes[ng_name][asg_name] = {
                'min_size': min_size,
                'max_size': max_size,
                'desired_capacity': desired_capacity
              }
              stored_sizes_updated = True
              print(f"Storing current sizes min_size={min_size}, max_size={max_size}, desired_capacity={desired_capacity}.")

              asg_client.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                MinSize=0,
                MaxSize=0,
                DesiredCapacity=0
              )
              print(f"Auto scaling group updated successfully.")
            else:
              print(f"Auto scaling group is already stopped. Skipping...")
        else:
          print(f"Auto scaling group does not have autoscaler enabled. Skipping...")
      if stored_sizes_updated:
        ssm_client.put_parameter(
          Name="/SASWorkbench/lambda/LAMBDA_FUNCTION_NAME_PLACEHOLDER",
          Value=json.dumps(stored_sizes),
          Type="String",
          Overwrite=True
        )
        print(f"Updated stored sizes in SSM parameter.")

    return {
      "statusCode": 200
    }
  except ClientError as e:
    print(e)
    return {
      "statusCode": 500,
      "body": json.dumps({"error": str(e)})
    }
EOF
  )
  lambda_code="${lambda_code//LAMBDA_FUNCTION_NAME_PLACEHOLDER/${LAMBDA_FUNCTION_NAME}}"
  lambda_code="${lambda_code//CLUSTER_NAME_PLACEHOLDER/${cluster_name}}"

  # Create ZIP file
  local zip_file="lambda_function.zip"
  log_progress "Packaging Lambda Function ZIP at: ${zip_file}"
  echo "${lambda_code}" >"lambda_function.py"
  zip -q "${zip_file}" lambda_function.py

  log_progress "Getting lambda function ..."
  response=$(
    aws_cmd lambda get-function \
      --region "${region}" \
      --function-name "${LAMBDA_FUNCTION_NAME}" \
      --region "${region}" 2>&1
  )
  status_code="${?}"
  case "${status_code}" in
    "${STATUS_CODE_SUCCESS}")
      log_progress "Updating Lambda function configuration ..."
      if ! aws_cmd lambda update-function-configuration \
        --region "${region}" \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime "python3.13" >/dev/null; then
        return 1
      fi

      # Wait for update to complete
      while true; do
        log_progress "Checking lambda function last update status ..."
        local status
        if ! status=$(
          aws_cmd lambda get-function-configuration \
            --region "${region}" \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --query 'LastUpdateStatus' \
            --output text
        ); then
          return 1
        fi
        if [[ ${status} == "Successful" || ${status} == "Failed" ]]; then
          break
        fi
        sleep 2
      done

      log_progress "Updating Lambda function code ..."
      if ! aws_cmd lambda update-function-code \
        --region "${region}" \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --zip-file "fileb://${zip_file}" >/dev/null; then
        return 1
      fi
      ;;
    "${STATUS_CODE_RESOURCE_NOT_FOUND}")
      log_info "Lambda function not found."
      log_progress "Creating lambda function ..."
      INDENT=$((INDENT + 2))
      while true; do
        response=$(
          aws_cmd lambda create-function \
            --region "${region}" \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime "python3.13" \
            --role "${role_arn}" \
            --handler "lambda_function.lambda_handler" \
            --zip-file "fileb://${zip_file}" 2>&1
        )
        status_code="${?}"
        if [ "${status_code}" -eq "${STATUS_CODE_SUCCESS}" ]; then
          break
        elif [ "${status_code}" -eq "${STATUS_CODE_NOT_ASSUMABLE}" ]; then
          log_progress "Role cannot be assumed by Lambda. Waiting..."
          sleep 2
        else
          log_error "${response}"
          return 1
        fi
      done
      INDENT=$((INDENT - 2))
      ;;
    *)
      log_error "${response}"
      return 1
      ;;
  esac

  # Manage log group
  local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"

  log_progress "Creating log group for lambda function logs ..."
  response=$(
    aws_cmd logs create-log-group \
      --region "${region}" \
      --log-group-name "${log_group_name}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne 0 ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_ALREADY_EXISTS}" ]; then
    log_error "${response}"
    return 1
  fi

  log_progress "Setting retention policy for lambda function logs ..."
  if ! aws_cmd logs put-retention-policy \
    --region "${region}" \
    --log-group-name "${log_group_name}" \
    --retention-in-days 30 >/dev/null; then
    return 1
  fi

  log_progress "Checking lambda function ..."
  local arn
  if ! arn=$(
    aws_cmd lambda get-function \
      --region "${region}" \
      --function-name "${LAMBDA_FUNCTION_NAME}" \
      --query 'Configuration.FunctionArn' \
      --output text
  ); then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Upserted lambda function '${LAMBDA_FUNCTION_NAME}' with ARN '${arn}'."
  log ""

  echo "${arn}"
}

# Creates or updates EventBridge schedules for Lambda function execution
# Sets up both start and stop schedules with specified cron expressions
# Manages schedule group creation and individual schedule configuration
upsert_schedules() {
  local region="${1}"
  local lambda_function_arn="${2}"
  local schedule_role_arn="${3}"
  local start_cron="${4}"
  local stop_cron="${5}"

  local response
  local status_code

  local region_timezone
  if ! region_timezone=$(get_timezone "${region}"); then
    return 1
  fi

  local INDENT=$((INDENT + 2))
  log_progress "Upserting schedules ..."

  INDENT=$((INDENT + 2))
  log_progress "Creating schedule group ..."
  response=$(
    aws_cmd scheduler create-schedule-group \
      --region "${region}" \
      --name "${SCHEDULE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ] && [ "${status_code}" -ne "${STATUS_CODE_RESOURCE_ALREADY_EXISTS}" ]; then
    log_error "${response}"
    return 1
  fi

  if ! upsert_schedule "${region}" "${region_timezone}" "${lambda_function_arn}" "${schedule_role_arn}" "start" "${start_cron}"; then
    return 1
  fi

  if ! upsert_schedule "${region}" "${region_timezone}" "${lambda_function_arn}" "${schedule_role_arn}" "stop" "${stop_cron}"; then
    return 1
  fi

  INDENT=$((INDENT - 2))
  log_success "Upserted schedules."
}

# Creates or updates a single EventBridge schedule for Lambda execution
# Configures schedule with cron expression and target Lambda function
# Handles both start and stop schedule types based on status parameter
upsert_schedule() {
  local region="${1}"
  local region_timezone="${2}"
  local lambda_function_arn="${3}"
  local schedule_role_arn="${4}"
  local status="${5}"
  local cron="${6}"

  local response
  local status_code

  local schedule_name
  if [[ ${status} == "start" ]]; then
    schedule_name="${FUNCTION_START_SCHEDULE_NAME}"
  else
    schedule_name="${FUNCTION_STOP_SCHEDULE_NAME}"
  fi

  log_progress "Upserting '${status}' schedule ..."

  INDENT=$((INDENT + 2))
  log_progress "Getting '${status}' schedule ..."
  response=$(
    aws_cmd scheduler get-schedule \
      --region "${region}" \
      --name "${schedule_name}" \
      --group-name "${SCHEDULE_GROUP_NAME}" 2>&1
  )
  status_code="${?}"
  case "${status_code}" in
    "${STATUS_CODE_SUCCESS}")
      log_progress "Updating '${status}' schedule configuration ..."
      if ! aws_cmd scheduler update-schedule \
        --region "${region}" \
        --name "${schedule_name}" \
        --schedule-expression-timezone "${region_timezone}" \
        --schedule-expression "cron(${cron})" \
        --flexible-time-window "Mode=OFF" \
        --target "{\"Arn\":\"${lambda_function_arn}\",\"RoleArn\":\"${schedule_role_arn}\",\"Input\":\"{\\\"status\\\":\\\"${status}\\\"}\"}" \
        --group-name "${SCHEDULE_GROUP_NAME}" >/dev/null; then
        return 1
      fi
      ;;
    "${STATUS_CODE_RESOURCE_NOT_FOUND}")
      log_info "Schedule for '${status}' not found."
      log_progress "Creating schedule for '${status}' ..."
      INDENT=$((INDENT + 2))
      while true; do
        response=$(
          aws_cmd scheduler create-schedule \
            --region "${region}" \
            --name "${schedule_name}" \
            --schedule-expression-timezone "${region_timezone}" \
            --schedule-expression "cron(${cron})" \
            --flexible-time-window "Mode=OFF" \
            --target "{\"Arn\":\"${lambda_function_arn}\",\"RoleArn\":\"${schedule_role_arn}\",\"Input\":\"{\\\"status\\\":\\\"${status}\\\"}\"}" \
            --group-name "${SCHEDULE_GROUP_NAME}" 2>&1
        )
        status_code="${?}"
        if [ "${status_code}" -eq "${STATUS_CODE_SUCCESS}" ]; then
          break
        elif [ "${status_code}" -eq "${STATUS_CODE_NOT_ASSUMABLE}" ]; then
          log_progress "Role cannot be assumed by Schedule. Waiting..."
          sleep 2
        else
          log_error "${response}"
          return 1
        fi
      done
      INDENT=$((INDENT - 2))
      ;;
    *)
      log_error "${response}"
      return 1
      ;;
  esac

  INDENT=$((INDENT - 2))
  log_success "Upserted '${status}' schedule."
}

call_lambda_function() {
  local region="${1}"
  local status="${2}"

  local response
  local status_code

  log_progress "Calling lambda function with status '${status}' ..."

  local INDENT=$((INDENT + 2))
  log_progress "Checking if lambda function exists ..."
  response=$(
    aws_cmd lambda get-function \
      --region "${region}" \
      --function-name "${LAMBDA_FUNCTION_NAME}" 2>&1
  )
  status_code="${?}"
  if [ "${status_code}" -ne "${STATUS_CODE_SUCCESS}" ]; then
    log_error "Lambda function '${LAMBDA_FUNCTION_NAME}' does not exist."
    return 1
  fi

  log_progress "Invoking lambda function with status '${status}' ..."
  if ! aws_cmd lambda invoke \
    --region "${region}" \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --payload "$(echo -n "{\"status\":\"${status}\"}" | base64)" \
    response.json >/dev/null; then
    return 1
  fi

  log_info "Access logs here https://console.aws.amazon.com/cloudwatch/home?region=${region}#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F${LAMBDA_FUNCTION_NAME}"

  INDENT=$((INDENT - 2))
  log_success "Called lambda function with status '${status}'."
  log ""
}
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

# Usage functions
# Display main help message with available actions
usage() {
  cat <<EOF
Usage: $0 <action> [options]

Actions:
    schedule    Schedule Lambda function using EventBridge schedules
    delete      Delete created resources
    start       Call Lambda function with status start
    stop        Call Lambda function with status stop

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

Schedule Lambda function using EventBridge schedules.

Options:
    -h, --help             Show this help message

Examples:
    $0 schedule
    $0 schedule --help

Environment variables:
    AWS_REGION|AWS_DEFAULT_REGION     AWS region to use
    CLUSTER_NAME                      EKS cluster name
    START_CRON                        Cron expression for starting nodes
    STOP_CRON                         Cron expression for stopping nodes
    RESOURCES_PREFIX_OVERRIDE         Override default AWS resources prefix (update-wb-asg-sizes)
EOF
}

# Show help for start action
usage_start() {
  cat <<EOF
Usage: $0 start [options]

Call Lambda function with status start.

Options:
    -h, --help             Show this help message

Examples:
    $0 start
    $0 start --help

Environment variables:
    AWS_REGION|AWS_DEFAULT_REGION     AWS region to use
    RESOURCES_PREFIX_OVERRIDE         Override default AWS resources prefix (update-wb-asg-sizes)
EOF
}

# Show help for stop action
usage_stop() {
  cat <<EOF
Usage: $0 stop [options]

Call Lambda function with status stop.

Options:
    -h, --help             Show this help message

Examples:
    $0 stop
    $0 stop --help

Environment variables:
    AWS_REGION|AWS_DEFAULT_REGION     AWS region to use
    RESOURCES_PREFIX_OVERRIDE         Override default AWS resources prefix (update-wb-asg-sizes)
EOF
}

# Show help for delete action
usage_delete() {
  cat <<EOF
Usage: $0 delete

Delete created resources including Lambda function, EventBridge rules, IAM roles, and log groups.

This action does not require any options or arguments.

Options:
    -h, --help             Show this help message

Examples:
    $0 delete

Environment variables:
    AWS_REGION|AWS_DEFAULT_REGION     AWS region to use
    FUNCTION_NAME_OVERRIDE            Override default Lambda function name (update_wb_asg_sizes)

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

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

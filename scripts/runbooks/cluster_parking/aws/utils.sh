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

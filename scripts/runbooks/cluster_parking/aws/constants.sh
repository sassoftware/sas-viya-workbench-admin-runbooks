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

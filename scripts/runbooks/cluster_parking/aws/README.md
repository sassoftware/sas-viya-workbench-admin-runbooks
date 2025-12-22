# Schedule Cluster Shutdown and Start-up for AWS Infrastructure

This script sets up automated scheduling for AWS EKS Workbench to shutdown and start-up using Lambda functions and EventBridge schedules.

## Overview

The script will set up:
- **Lambda Function**: `update_wb_asg_sizes` - Updates Auto Scaling Group sizes for EKS node groups
- **EventBridge Schedules**: Scheduled triggers for start/stop operations
- **EventBridge Schedule Group**: `sas-workbench` - Groups schedules for organization
- **IAM Roles**: Execution roles with necessary permissions for Lambda and EventBridge Scheduler
- **IAM Policies**: Custom policies for Lambda execution and scheduler permissions
- **CloudWatch Logs**: Monitoring and debugging Lambda execution with 30-day retention
- **SSM Parameter**: Stores original Auto Scaling Group sizes for restoration

## Prerequisites

- Connect to your EC2 Data Plane Builder for Workbench via the AWS Console ([Workbench Doc: Steps 1-4](https://go.documentation.sas.com/doc/en/workbenchcdc/v_001/workbenchag/kubernetesupgrade.htm#p01s8cpr8ls3ujn1t5at1m242cwf)).
- [AWS CLI](https://aws.amazon.com/cli/) must be configured with appropriate credentials and permissions ([required permissions](#permissions-for-running-this-scripts))


## Setup Guide

Run the following script in your EC2 Data Plane Builder shell:

```bash
bash <(curl -s https://raw.githubusercontent.com/sassoftware/sas-viya-workbench-admin-runbooks/refs/heads/main/dist/aws_cluster_parking.sh) schedule
```

The script guides you through the setup process. You are prompted for the following information:
- Start Cron Expression: A cron expression for starting the cluster.
- Stop Cron Expression: A cron expression for stopping the cluster.

See [cron expression format](#cron-expression-format) for help writing cron expressions.

After the script has completed, a lambda function named `update_wb_asg_sizes-lambda-function` automatically runs to start-up and shutdown your SAS Viya Workbench cluster.

> Note: If you need to change your settings after initial setup, rerun the script above.

## Usage

The script provides two main commands:

### 1. Schedule

Deploys the Lambda function and EventBridge schedules:

```bash
./dist/aws_cluster_parking.sh schedule [options]
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `AWS_REGION` or `AWS_DEFAULT_REGION`: AWS region to use
- `CLUSTER_NAME`: EKS cluster name
- `START_CRON`: Cron expression for starting nodes.
- `STOP_CRON`: Cron expression for stopping nodes.
- `RESOURCES_PREFIX_OVERRIDE`: AWS resources name prefix. Default is `update-wb-asg-sizes`

> Note: AWS Region and EKS Cluster are already configured when running inside your EC2 Data Plane Builder.

### 2. Delete Resources

Removes all created AWS resources for scheduling:

```bash
./dist/aws_cluster_parking.sh delete
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `AWS_REGION` or `AWS_DEFAULT_REGION`: AWS region to use
- `RESOURCES_PREFIX_OVERRIDE`: AWS resources name prefix. Default is `update-wb-asg-sizes`

## Architecture

### Components Created

1. **IAM Roles**:
   - `<resources-prefix>-lambda-role`: Execution role for Lambda function
   - `<resources-prefix>-schedule-role`: Execution role for EventBridge Scheduler

2. **IAM Policies**:
   - `<resources-prefix>-lambda-policy`: Attached to Lambda role with permissions for CloudWatch Logs, EKS, Auto Scaling, and SSM
   - `<resources-prefix>-schedule-policy`: Attached to scheduler role with Lambda invoke permissions

3. **Lambda Function**: `<resources-prefix>-lambda-function`
   - Runtime: Python 3.13
   - Handler: `lambda_function.lambda_handler`
   - Timeout: Default Lambda timeout
   - [Permissions given to lambda](#permissions-given-to-lambda)

4. **CloudWatch Log Group**: `/aws/lambda/<resources-prefix>-lambda-function`
   - Log retention: 30 days
   - Monitoring and debugging Lambda execution

5. **EventBridge Schedule Group**: `sas-workbench`
   - Groups all schedules for organization

6. **EventBridge Schedules**:
   - `<resources-prefix>-start-schedule`: Triggers Lambda with "start" status
   - `<resources-prefix>-stop-schedule`: Triggers Lambda with "stop" status

7. **SSM Parameter**: `/SASWorkbench/lambda/<resources-prefix>-lambda-function`
   - Stores original Auto Scaling Group sizes for restoration during start operations

### Lambda Function Logic

The Lambda function receives events with a `status` field:
- `"start"`: Restores Auto Scaling Groups to their original sizes
- `"stop"`: Sets Auto Scaling Groups to 0 (min_size=0, max_size=0, desired_capacity=0)


## Cron Expression Format

Cron expressions use the format: `minute hour day-of-month month day-of-week year`

Examples:
- `0 8 ? * MON-FRI *`: Start at 8:00 AM region time, Monday through Friday
- `0 18 ? * MON-FRI *`: Stop at 6:00 PM region time, Monday through Friday
- `0 9 ? * 1-5 *`: Start at 9:00 AM region time, Monday through Friday (using numeric days)

> Note: Region time is based on the selected AWS Region.


## Security Considerations

- **IAM roles follow principle of least privilege**: Separate execution roles for Lambda and EventBridge Scheduler with minimal required permissions
- **Lambda function permissions**: Limited to CloudWatch Logs, EKS operations, Auto Scaling operations with resource tags conditions, and specific SSM parameter access [see details](#permissions-given-to-lambda)
- **EventBridge Scheduler permissions**: Limited to invoking only the specific Lambda function [see details](#permissions-given-to-scheduler)
- **Resource-level permissions**: Auto Scaling operations are restricted to resources with specific cluster-autoscaler tags
- **CloudWatch logs**: 30-day retention policy to limit log storage duration
- **SSM parameter encryption**: Uses default AWS managed encryption for stored Auto Scaling Group sizes
- **No sensitive data**: No credentials, secrets, or sensitive information stored in Lambda code or environment variables
- **Cross-service security**: EventBridge schedules use IAM roles for secure Lambda invocation without embedded credentials

## Troubleshooting

### Common Issues

1. **AWS CLI not configured**
   ```
   aws configure
   ```

2. **Missing dependencies**
   - Install `jq`: `sudo apt-get install jq` (Ubuntu/Debian) or `brew install jq` (macOS)
   - Install `zip`: Usually pre-installed on most systems

3. **Insufficient permissions**
   - Ensure your AWS user/role has permissions for EKS, Auto Scaling, Lambda, EventBridge Scheduler, CloudWatch Logs, SSM Parameters, and IAM
   - See the complete [required permissions](#permissions-for-running-this-scripts) for detailed policy requirements

4. **Invalid cron expression**
   - Test cron expressions using online validators
   - Remember EventBridge schedule uses region timezone

### Permissions

#### Permissions for running this scripts

Below are the minimum permissions a user needs to run these scripts.


```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": [
                "arn:aws:iam::<account_id>:role/<resources-prefix>-lambda-role",
                "arn:aws:iam::<account_id>:role/<resources-prefix>-schedule-role",
                "arn:aws:lambda:<region>:<account_id>:function:<resources-prefix>-lambda-function",
                "arn:aws:events:<region>:<account_id>:rule/<resources-prefix>-temp-schedule*",
                "arn:aws:logs:<region>:<account_id>:log-group:/aws/lambda/<resources-prefix>-lambda-function*",
                "arn:aws:ssm:<region>:<account_id>:parameter/SASWorkbench/lambda/<resources-prefix>-lambda-function",
                "arn:aws:scheduler:<region>:<account_id>:schedule-group/<resources-prefix>-schedule-group",
                "arn:aws:scheduler:<region>:<account_id>:schedule-group/<resources-prefix>-schedule-group/*",
                "arn:aws:scheduler:<region>:<account_id>:schedule/<resources-prefix>-schedule-group/*",
                "arn:aws:scheduler:<region>:<account_id>:schedule/<resources-prefix>-schedule-group/*"
            ]
        }
    ]
}
```

#### Permissions given to lambda

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:<region>:<account_id>:log-group:/aws/lambda/<resources-prefix>-lambda-function",
        "arn:aws:logs:<region>:<account_id>:log-group:/aws/lambda/<resources-prefix>-lambda-function:*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "eks:ListNodegroups",
      "Resource": [
        "arn:aws:eks:<region>:<account_id>:cluster/<cluster_name>"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "eks:DescribeNodegroup",
      "Resource": [
        "arn:aws:eks:<region>:<account_id>:nodegroup/<cluster_name>/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true",
          "aws:ResourceTag/k8s.io/cluster-autoscaler/<cluster_name>": "owned"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:PutParameter"
      ],
      "Resource": [
        "arn:aws:ssm:<region>:<account_id>:parameter/SASWorkbench/lambda/<resources-prefix>-lambda-function"
      ]
    }
  ]
}
```


#### Permissions given to scheduler

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": [
        "arn:aws:lambda:<region>:<account_id>:function:<resources-prefix>-lambda-function"
      ]
    }
  ]
}
```

# Cluster Parking Azure Infrastructure Automation

This project provides automated scheduling for Azure AKS workbench clusters using Azure Functions and cron-based triggers. It allows you to automatically start and stop entire AKS workbench clusters based on cron expressions to optimize costs.

## Overview

The automation system consists of:
- **Azure Function App**: `cluster-parking-function-app` - Contains functions for cluster parking operations
- **Azure Functions**: Individual functions for start/stop operations with timer triggers
- **Azure Resource Group**: `cluster-parking-rg` - Groups all parking resources for organization
- **Azure Storage Account**: Required for Azure Function App runtime
- **HashiCorp Vault Integration**: Stores scheduling information and status
- **AKS Integration**: Manages AKS cluster start/stop operations

## Prerequisites

- Azure CLI configured with appropriate credentials
- HashiCorp Vault access with proper authentication
- `jq` for JSON processing
- `zip` for function deployment package creation
- Required Azure permissions for the user:
  - [Check Azure permissions](#permissions-for-running-this-script)

## Usage

NOTE: Script will prompt for user input if the information is not provided.

The script provides four main actions:

### 1. Schedule

Deploys the Azure Functions and sets up cron-based scheduling:

```bash
./main.sh schedule [options]
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `SAS_WORKBENCH_SITE_ID`: SAS Workbench dataplane site id.
- `VAULT_ADDR`: HashiCorp Vault server address
- `VAULT_TOKEN`: Authentication token for Vault access
- `START_CRON`: Cron expression for starting nodes
- `STOP_CRON`: Cron expression for stopping nodes
- `RESOURCES_PREFIX_OVERRIDE`: Azure resources name prefix. Default is `cluster-parking`

**Example:**
```bash
./main.sh schedule
```

### 2. Start

Manually start the AKS cluster:

```bash
./main.sh start [options]
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `SAS_WORKBENCH_SITE_ID`: SAS Workbench dataplane site id.
- `VAULT_ADDR`: HashiCorp Vault server address
- `VAULT_TOKEN`: Authentication token for Vault access
- `RESOURCES_PREFIX_OVERRIDE`: Azure resources name prefix. Default is `cluster-parking`

### 3. Stop

Manually stop the AKS cluster:

```bash
./main.sh stop [options]
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `SAS_WORKBENCH_SITE_ID`: SAS Workbench dataplane site id.
- `VAULT_ADDR`: HashiCorp Vault server address
- `VAULT_TOKEN`: Authentication token for Vault access
- `RESOURCES_PREFIX_OVERRIDE`: Azure resources name prefix. Default is `cluster-parking`

### 4. Delete Resources

Removes all created Azure resources for scheduling:

```bash
./main.sh delete
```

**Options:**
- `-h, --help`: Show help message

**Environment Variables:**
- `SAS_WORKBENCH_SITE_ID`: SAS Workbench dataplane site id.
- `VAULT_ADDR`: HashiCorp Vault server address
- `VAULT_TOKEN`: Authentication token for Vault access
- `RESOURCES_PREFIX_OVERRIDE`: Azure resources name prefix. Default is `cluster-parking`

## Architecture

### Components Created

1. **Azure Resource Group**: `<resources-prefix>-rg`
   - Contains all cluster parking resources

2. **Azure Storage Account**: `<resources-prefix>sa`
   - Required for Azure Function App runtime
   - Stores function code and configuration
   - Name follows Azure naming constraints (alphanumeric only)

3. **Azure Function App**: `<resources-prefix>-function-app`
   - Hosts the parking functions
   - Provides start/stop azure functions to start/stop AKS cluster.
   - Runtime: Powershell

4. **HashiCorp Vault Storage**:
   - Path: `<SAS_WORKBENCH_SITE_ID>/workbench/workbench-admin-runbooks/cluster_parking/<resources-prefix>`
   - Stores scheduling information, cron expressions, and status

### Function Logic

The Azure Functions operate on entire AKS clusters:
- **Start Function**: Starts the stopped AKS cluster, restoring it to running state
- **Stop Function**: Stops the AKS cluster to minimize costs while preserving cluster configuration

## Cron Expression Format

Cron expressions use the standard 5-field format: `minute hour day-of-month month day-of-week`

Examples:
- `0 8 * * 1-5`: Start at 8:00 AM region time, Monday through Friday
- `0 18 * * 1-5`: Stop at 6:00 PM region time, Monday through Friday
- `0 9 * * *`: Daily at 9:00 AM region time

**Note**: Azure Functions use the selected Azure region's timezone for cron expressions, not UTC.

## Security Considerations

- **Azure RBAC**: Functions run with managed identity and least-privilege access
- **Resource-level permissions**: AKS operations are restricted to specific clusters for start/stop operations
- **No embedded credentials**: All authentication handled through Azure managed identity.

## Troubleshooting

### Common Issues

1. **Azure CLI not configured**
   ```bash
   az login
   az account set --subscription <your-subscription-id>
   ```

2. **Vault authentication issues**
   - Ensure `VAULT_ADDR` and `VAULT_TOKEN` are properly set
   - Verify Vault token has necessary permissions for the specified path

3. **Missing dependencies**
   - Install `jq`: `sudo apt-get install jq` (Ubuntu/Debian) or `brew install jq` (macOS)
   - Install `zip`: Usually pre-installed on most systems
   - Install Azure CLI: Follow [official documentation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

4. **Insufficient permissions**
   - Ensure your Azure account has permissions for Resource Groups, Storage Accounts, Function Apps, and AKS clusters
   - See the complete [required permissions](#permissions-for-running-this-script) for detailed requirements

5. **Invalid cron expression**
   - Test cron expressions using online validators
   - Remember Azure Functions use the selected region's timezone
   - Ensure 5-field format: `minute hour day-of-month month day-of-week`

6. **Function deployment failures**
   - Verify storage account connectivity and permissions
   - Ensure resource group exists and is accessible

### Permissions

#### Permissions for running this script

Below are the minimum Azure RBAC permissions a user needs to run these scripts:

**Specific Permissions:**
```json
{
  "Name": "ClusterParkingCustomRole",
  "IsCustom": true,
  "Description": "Custom role for cluster parking with limited permissions",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Storage/storageAccounts/write",
    "Microsoft.Storage/storageAccounts/listKeys/action",
    "Microsoft.Web/sites/read",
    "Microsoft.Web/sites/config/read",
    "Microsoft.Web/sites/write",
    "Microsoft.Web/sites/config/write",
    "Microsoft.Web/sites/config/list/action",
    "Microsoft.Web/sites/publishxml/action",
    "Microsoft.Web/sites/extensions/write",
    "Microsoft.Web/sites/basicPublishingCredentialsPolicies/read",
    "Microsoft.Web/sites/publish/action",
    "Microsoft.Web/sites/restart/action",
    "Microsoft.Web/serverfarms/read",
    "Microsoft.Web/serverfarms/write",
    "Microsoft.Authorization/roleAssignments/read",
    "Microsoft.Authorization/roleAssignments/write",
    "Microsoft.Authorization/roleAssignments/delete",
    "Microsoft.ContainerService/managedClusters/read",
    "Microsoft.ContainerService/managedClusters/start/action",
    "Microsoft.ContainerService/managedClusters/stop/action"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": []
}
```

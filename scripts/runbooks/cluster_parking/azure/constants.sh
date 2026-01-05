#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Prefix used for naming all Azure resources related to cluster parking
# This ensures consistent naming across all resources
export RESOURCES_PREFIX="cluster-parking"
# Name of the Azure Resource Group that will contain all cluster parking resources
export RESOURCE_GROUP_NAME="${RESOURCES_PREFIX}-rg"
# Name of the Azure Storage Account used by the Function App
# Special characters are removed to comply with storage account naming requirements (alphanumeric only)
export STORAGE_ACCOUNT_NAME="${RESOURCES_PREFIX//[^a-z0-9]/}sa"
# Name of the Azure Function App that hosts the parking functions
export FUNCTION_APP_NAME="${RESOURCES_PREFIX}-function-app"
# Name of the Function within the Function App responsible for starting parked clusters
export START_FUNCTION_NAME="${RESOURCES_PREFIX}-start-function"
# Name of the Function within the Function App responsible for stopping/parking clusters
export STOP_FUNCTION_NAME="${RESOURCES_PREFIX}-stop-function"

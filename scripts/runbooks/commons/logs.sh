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

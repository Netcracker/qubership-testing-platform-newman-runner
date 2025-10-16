#!/bin/bash
# # Copyright 2024-2025 NetCracker Technology Corporation
# #
# # Licensed under the Apache License, Version 2.0 (the "License");
# # you may not use this file except in compliance with the License.
# # You may obtain a copy of the License at
# #
# #      http://www.apache.org/licenses/LICENSE-2.0
# #
# # Unless required by applicable law or agreed to in writing, software
# # distributed under the License is distributed on an "AS IS" BASIS,
# # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# # See the License for the specific language governing permissions and
# # limitations under the License.

set -euo pipefail  # Strict mode: exit on errors, check for unset variables

# ============================================
# Function to load a JSON file
# Returns: file content as a compact JSON string
# Exits with code 1 if file is not found or JSON is invalid
# ============================================
load_json_file() {
  local file_path="$1"
  
  # Checking file existence
  if [ ! -f "$file_path" ]; then
    echo "Error: file '$file_path' not found" >&2
    return 1
  fi

  # Read and Validate JSON (required jq)
  if ! json_content=$(jq -c . < "$file_path" 2>/dev/null); then
    echo "Error: file '$file_path' contains invalid JSON" >&2
    return 1
  fi

  echo "$json_content"
}

# ============================================
# Set environment variables for local run and debugging
# ============================================
## Git settings. Input parameters from project
export WORK_DIR=$(pwd)
export TEST_PARAMS="{}"

# ============================================
# Run collection settings
# ============================================
export LOCAL_RUN=true
export LOCAL_COLLECTIONS_DIR="local-collection"


# ============================================
# Newman settings
# ============================================
if ! TEST_PARAMS=$(load_json_file "$(pwd)/tools/local_test_params.json"); then
  echo "Failed to load parameters from TEST_PARAMS" >&2
  exit 1
fi

# ============================================
# Performing start_tests.sh
# ============================================
# Check that start_tests.sh exists in the current directory (project root)
if [[ ! -f "start_tests.sh" ]]; then
    echo "Error: start_tests.sh not found in the current directory!" >&2
    exit 1
fi

# Run start_tests.sh
./start_tests.sh

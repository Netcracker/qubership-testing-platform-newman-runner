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


# Environment initialization module
init_environment() {
    echo "🔧 Initializing environment..."
    
    # Compute current date and time
    if [[ -z "${CURRENT_DATE}" ]]; then
        CURRENT_DATE=$(date +%F)         # e.g., 2025-04-07
    fi
    if [[ -z "${CURRENT_TIME}" ]]; then
        CURRENT_TIME=$(date +%H-%M-%S)  # e.g., 11-48-00
    fi

    # Configure AWS S3 parameters (required) - using local variables for security
    if [[ -z "${ATP_STORAGE_USERNAME}" ]]; then
        echo "❌ ATP_STORAGE_USERNAME is required but not set"
        exit 1
    fi
    if [[ -z "${ATP_STORAGE_PASSWORD}" ]]; then
        echo "❌ ATP_STORAGE_PASSWORD is required but not set"
        exit 1
    fi
    
    # Store credentials in local variables (not exported to environment)
    _LOCAL_S3_KEY="$ATP_STORAGE_USERNAME"
    _LOCAL_S3_SECRET="$ATP_STORAGE_PASSWORD"
    export AWS_ACCESS_KEY_ID="$_LOCAL_S3_KEY"
    export AWS_SECRET_ACCESS_KEY="$_LOCAL_S3_SECRET"

    # Configure additional s5cmd settings for MinIO only
    if [[ "${ATP_STORAGE_PROVIDER}" == "minio" || "${ATP_STORAGE_PROVIDER}" == "s3" ]]; then
        export AWS_ENDPOINT_URL="${ATP_STORAGE_SERVER_URL}"
        export AWS_REGION="${ATP_STORAGE_REGION}"             # Required by s5cmd even for MinIO
        export AWS_NO_VERIFY_SSL="true"           # Optional: disable SSL verification
    fi

    # Define temp clone path
    export TMP_DIR="/tmp/clone"
    mkdir -p "$TMP_DIR"

    # Remove previous contents if any
    rm -rf "${TMP_DIR:?}/"*
    
    echo "✅ Environment initialized successfully"
}

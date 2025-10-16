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

set -e

echo "ℹ️ Installed Newman version: $(newman -v)"

# Main test job entrypoint script - coordinates all modules
echo "🔧 Starting test job entrypoint script..."
echo "📁 Working directory: $(pwd)"
echo "📅 Timestamp: $(date)"

# Set default upload method
export UPLOAD_METHOD="${UPLOAD_METHOD:-sync}"
echo "📤 Upload method: $UPLOAD_METHOD"

# Import modular components
source /scripts/init.sh
source /scripts/git-clone.sh
source /scripts/runtime-setup.sh
source /scripts/test-runner.sh
source /scripts/upload-monitor.sh
source /scripts/email-notification/generate-email-notification-json.sh

# Execute main workflow
echo "🚀 Starting test execution workflow..."

init_environment
clone_repository
setup_runtime_environment
start_upload_monitoring
cp /start_tests.sh $TMP_DIR/start_tests.sh
run_tests
generate_email_notification_json
finalize_upload

echo "✅ Test job finished successfully!"

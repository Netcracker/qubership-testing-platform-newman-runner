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


# Test execution module
run_tests() {
    echo "▶ Starting test execution..."
    
    # Import upload monitoring module for security functions
    source /scripts/upload-monitor.sh
    
    # Create Allure results directory
    echo "📁 Creating Allure results directory..."
    mkdir -p $TMP_DIR/allure-results

    # Clear sensitive variables before tests
    echo "🔐 Clearing sensitive environment variables before tests..."
    clear_sensitive_vars

    # Execute test suite
    echo "🚀 Running test suite..."
    chmod +x start_tests.sh
    ./start_tests.sh || TEST_EXIT_CODE=$?

    TEST_EXIT_CODE=${TEST_EXIT_CODE:-0}
    echo "ℹ️ Test script exited with code: $TEST_EXIT_CODE (but continuing...)"
    
    echo "✅ Test execution completed"
} 
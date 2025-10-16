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


# Newman runtime environment setup module
setup_runtime_environment() {
    echo "🔧 Setting up Newman runtime environment..."

    # Node.js runtime setup
    export NODE_PATH=$TMP_DIR:$NODE_PATH
    echo "📦 Node.js path set to: $NODE_PATH"

    # Copy node_modules from container to temp directory (Newman-specific)
    echo "🔧 Copying dependencies from container..."
    cp -r /app/node_modules $TMP_DIR/node_modules

    echo "✅ Newman runtime environment setup completed"
}

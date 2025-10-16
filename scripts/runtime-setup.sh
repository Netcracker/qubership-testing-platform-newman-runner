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


# Runtime environment setup module
# This module is specific to the runtime type (Python, Node.js, Java, etc.)
setup_runtime_environment() {
    echo "🔧 Setting up runtime environment..."
    
    # Python runtime setup (for Python-based test images)
    export PYTHONPATH=$TMP_DIR/app:$PYTHONPATH
    echo "🔍 Python path set to: $PYTHONPATH"
    
    # Note: For other runtime types, this file would be replaced with:
    # - Node.js: export NODE_PATH=$TMP_DIR/app:$NODE_PATH
    # - Java: export CLASSPATH=$TMP_DIR/app:$CLASSPATH
    # - Go: export GOPATH=$TMP_DIR/app:$GOPATH
    
    echo "✅ Runtime environment setup completed"
} 
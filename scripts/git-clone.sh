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


# Git repository cloning module
clone_repository() {
    echo "📥 Cloning repository..."
    
    # Strip .git from URL and extract repo name
    REPO_PATH=$(echo "$ATP_TESTS_GIT_REPO_URL" | sed 's|\.git$||')
    GIT_BRANCH_CLEANED=$(echo "$ATP_TESTS_GIT_REPO_BRANCH" | sed 's|/|-|')
    REPO_NAME=$(basename "$REPO_PATH")
    ARCHIVE_URL="${REPO_PATH}/-/archive/${ATP_TESTS_GIT_REPO_BRANCH}/${REPO_NAME}-${GIT_BRANCH_CLEANED}.zip"

    echo "📥 Downloading archive from: $ARCHIVE_URL"
    curl -sSL --fail -H "PRIVATE-TOKEN: ${ATP_TESTS_GIT_TOKEN}" "$ARCHIVE_URL" -o "$TMP_DIR/repo.zip"

    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to download repository archive"
        exit 1
    fi

    echo "📦 Unzipping..."
    unzip -q "$TMP_DIR/repo.zip" -d "$TMP_DIR"
    mv "$TMP_DIR"/${REPO_NAME}-${GIT_BRANCH_CLEANED}/* "$TMP_DIR"

    echo "✅ Repository extracted to: $TMP_DIR"

    # Check for either 'app/' or 'tests/' directory (for different runtime types)
    if [ -d "$TMP_DIR/app" ]; then
        echo "✅ Clone successful. Found 'app/' directory in the repo."
    elif [ -d "$TMP_DIR/tests" ]; then
        echo "✅ Clone successful. Found 'tests/' directory in the repo."
    elif find "$TMP_DIR" -mindepth 1 -type f -iname "*postman_collection*" -print -quit | grep -q .; then
        echo "✅ Clone successful. Found 'postman_collection' files in the repo."
    else
        echo "❌ ERROR: Neither 'app/' nor 'tests/' directory nor 'postman_collection' file found in the cloned repo!"
        exit 1  
    fi

    # Move into the work directory
    cd $TMP_DIR

    # List contents to verify
    if [ -d "$TMP_DIR/app" ]; then
        echo "📋 Contents of $TMP_DIR/app directory:"
        ls -la app
    elif [ -d "$TMP_DIR/tests" ]; then
        echo "📋 Contents of $TMP_DIR/tests directory:"
        ls -la tests
    fi
    
    # Clear Git token from environment for security
    unset ATP_TESTS_GIT_TOKEN
    echo "🔐 Git token cleared from environment"
    
    echo "✅ Repository cloning completed successfully"
} 

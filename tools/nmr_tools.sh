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


# ============================================
# Function to check/set an environment variable
# Parameters:
#   $1 - variable name
#   $2 - expression to compute the value (if the variable is not set)
# Examples:
#   - Checks if the variable VAR_NAME is set, if not exits crashes with an error
#   check_env_var "VAR_NAME" ""
#   - Checks if the variable CURRENT_DATE is set, if not computes it using the command `date +%F`
#   check_env_var "CURRENT_DATE" "date +%F"
# ============================================
check_env_var() {
    local var_name="$1"
    local compute_expr="$2"
    local computed_value  # Announcing in advance

    # Check if the variable exists and if it is not empty
    if [[ -z "${!var_name:-}" ]]; then
        if [[ -z "$compute_expr" ]]; then
            echo "❗Error: variable '$var_name' must be specified!" >&2
            exit 1
        else
            # Calculating value
            computed_value=$(eval "$compute_expr" 2>/dev/null)

            # Verifying successful completion
            if [ $? -ne 0 ]; then
                echo "❗Error calculating the value for $var_name" >&2
                exit 1
            fi

            # Export variable
            declare -gx "$var_name"="$computed_value"
            if is_secret_var "$var_name"; then
              printf '%s = ******** (Computed)\n' "$var_name"
            else
              printf '%s = %s (Computed)\n' "$var_name" "$computed_value"
            fi
        fi
    else
        value="${!var_name}"
        if is_secret_var "$var_name"; then
          printf '%s = ********\n' "$var_name"
        else
          printf '%s = %s\n' "$var_name" "$value"
        fi
    fi
}

is_secret_var() {
  case "$1" in
    ATP_TESTS_GIT_TOKEN|ATP_STORAGE_PASSWORD) return 0 ;;
    *)                       return 1 ;;
  esac
}

# ============================================
# Function checks set of mandatory environment
# variables for running the newman collections
# Parameters:
#   N/A
# Examples:
#   check_mandatory_env_vars
# ============================================
check_mandatory_env_vars() {
    ## Check mandatory environment variables
    check_env_var "ENVIRONMENT_NAME" ""
    check_env_var "ATP_TESTS_GIT_REPO_URL" ""
    check_env_var "ATP_TESTS_GIT_REPO_BRANCH" ""
    check_env_var "TEST_PARAMS" ""

    ## Check mandatory environment variables for S3 reporting
    check_env_var "ATP_STORAGE_SERVER_URL" ""
    check_env_var "ATP_STORAGE_BUCKET" ""
    check_env_var "ATP_STORAGE_PROVIDER" ""
    check_env_var "ATP_STORAGE_SERVER_UI_URL" ""
    check_env_var "CURRENT_DATE" "date +%F"
    check_env_var "CURRENT_TIME" "date +%H-%M-%S"
}

extract_newman_collections_list () {
    local json_input="$1" output_var_name="$2"
    local -a collections=()
    
    # Extract collections by removing \r from each line
    mapfile -t collections < <(
        echo "$json_input" | \
        jq -r '(.collections[] // empty)' | \
        tr -d '\r'
    )
    # Debug: display with cat -A to see invisible characters
    # printf '%s\n' "${collections[@]}" | cat -A

    # Save to variable if name is passed
    [[ -n "$output_var_name" ]] && eval "$output_var_name=(\"\${collections[@]}\")"

    # Logging collections
    echo -e "➡️ Extracted Newman collections:"
    printf "    - %s\n" "${collections[@]}"
}

extract_flags_to_string() {
    local json_input="$1"
    local target_var_name="$2"

    # Convert the flags array to a string, joining the elements with a space
    local flags_string
    flags_string=$(echo "$json_input" | jq -r '(.flags // []) | map(sub("\\s*->\\s*"; "=")) | join(" ")')

    # Assign a value to a variable with a dynamic name
    eval "$target_var_name=\$flags_string"

    # Export variable
    export "$target_var_name"
}

# Return:
#   0 — if LOCAL_RUN=true
#   1 — if LOCAL_RUN=false or value not set/empty
#   2 — if incorrect value (not true, not false)
local_run_enabled() {

  local val="${LOCAL_RUN:-}"

  if [ -z "$val" ]; then
    return 1
  fi

  # reduce it to lowercase
  val="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"

  case "$val" in
    true)  return 0 ;;
    false) return 1 ;;
    *)
      printf '❌ Incorrect value LOCAL_RUN=%s (expected true/false)\n' "$LOCAL_RUN" >&2
      return 2
      ;;
  esac
}

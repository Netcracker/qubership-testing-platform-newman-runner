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

# Flatten ATP_ENVGENE_CONFIGURATION into Postman environment values and merge
# into the Newman --environment file.
# Uses: ATP_ENVGENE_CONFIGURATION, TMP_DIR, COMMON_ENV_FILE (in/out)
# Sets: ENVGENE_NEWMAN_ENV_APPLIED=true when a file is written
merge_envgene_newman_environment() {
    ENVGENE_NEWMAN_ENV_APPLIED=false
    export ENVGENE_NEWMAN_ENV_APPLIED

    if [[ -z "${ATP_ENVGENE_CONFIGURATION:-}" ]]; then
        echo "ℹ️ ATP_ENVGENE_CONFIGURATION is empty; skipping Newman environment merge"
        return 0
    fi

    if [[ -z "${TMP_DIR:-}" ]]; then
        echo "❌ ERROR: TMP_DIR is not set; cannot merge Newman environment" >&2
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ ERROR: 'jq' is not available; cannot merge Newman environment" >&2
        return 1
    fi

    if ! printf '%s' "$ATP_ENVGENE_CONFIGURATION" | jq empty >/dev/null 2>&1; then
        echo "❌ ERROR: Invalid JSON in ATP_ENVGENE_CONFIGURATION" >&2
        return 1
    fi

    local requested="${COMMON_ENV_FILE:-}"
    local source_path=""
    local output_path=""
    local generated_values=""
    local resolved=""

    if [[ -n "$requested" ]]; then
        if [[ "$requested" = /* ]]; then
            resolved="$requested"
        else
            resolved="${TMP_DIR%/}/${requested}"
        fi
        if [[ -f "$resolved" ]]; then
            source_path="$resolved"
            output_path="${TMP_DIR%/}/atp-generated.postman_environment.json"
        else
            output_path="$resolved"
        fi
    else
        output_path="${TMP_DIR%/}/atp-generated.postman_environment.json"
    fi

    echo "🔄 Flattening ATP_ENVGENE_CONFIGURATION into Newman environment variables..."

    generated_values="$(
        printf '%s' "$ATP_ENVGENE_CONFIGURATION" | jq -c '
          [.systems[]? | to_entries[]
           | .key as $system
           | ($system | ascii_upcase | gsub("[^A-Z0-9]"; "_")) as $sys
           | (.value.connections // [])[]
           | to_entries[]
           | .key as $conn
           | .value
           | to_entries[]
           | select(.value != null and (.value | tostring) != "")
           | {
               key: (
                 $sys
                 + "_" + ($conn | ascii_upcase | gsub("[^A-Z0-9]"; "_"))
                 + "_" + (.key | ascii_upcase | gsub("[^A-Z0-9]"; "_"))
               ),
               value: (.value | tostring),
               enabled: true,
               type: "default"
             }
          ]
        '
    )" || return 1

    mkdir -p "$(dirname "$output_path")"

    if [[ -n "$source_path" ]]; then
        if ! jq empty "$source_path" >/dev/null 2>&1; then
            echo "❌ ERROR: Invalid JSON in Newman environment file: $source_path" >&2
            return 1
        fi
        jq --argjson generated "$generated_values" '
          (.values // []) as $old
          | ($old | map({key: .key, value: .}) | from_entries) as $existing
          | ($generated | map({key: .key, value: .}) | from_entries) as $envgene
          | .values = (($existing + $envgene) | to_entries | map(.value))
          | if .name then . else . + {name: "atp-generated"} end
        ' "$source_path" > "$output_path" || return 1
        echo "✅ Merged EnvGene variables into Newman environment (source preserved): $source_path -> $output_path"
    else
        jq -n --argjson generated "$generated_values" '{
          name: "atp-generated",
          values: $generated,
          "_postman_variable_scope": "environment"
        }' > "$output_path" || return 1
        echo "✅ Created Newman environment from EnvGene variables: $output_path"
    fi

    COMMON_ENV_FILE="$output_path"
    NEWMAN_ENVIRONMENT_FILE="$output_path"
    ENVGENE_NEWMAN_ENV_APPLIED=true
    export COMMON_ENV_FILE NEWMAN_ENVIRONMENT_FILE ENVGENE_NEWMAN_ENV_APPLIED
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

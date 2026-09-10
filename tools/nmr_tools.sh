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

# Escape a value for Java .properties (Allure environment.properties).
# Uses '=' as the key/value separator, so ':' in values is kept as-is.
_escape_allure_property_value() {
    local val="${1-}"
    val="${val//\\/\\\\}"
    val="${val//$'\r'/}"
    val="${val//$'\n'/\\n}"
    printf '%s' "$val"
}

# Append KEY=VALUE to an Allure environment.properties file. Empty values are skipped.
# Parameters:
#   $1 - properties file path
#   $2 - key
#   $3 - value
append_allure_property() {
    local props_file="$1"
    local key="$2"
    local val="${3-}"
    if [[ -z "$val" ]]; then
        echo "ℹ️ Allure environment: ${key} is empty, skipping"
        return 0
    fi
    val="$(_escape_allure_property_value "$val")"
    printf '%s=%s\n' "$key" "$val" >> "$props_file"
    echo "ℹ️ Allure environment: ${key}=${val}"
}

# Write Allure environment.properties for the report Environments section.
# Allure Newman does not pick up process env vars automatically; it reads
# this file from the results directory after the run.
# Parameters:
#   $1 - allure-results directory
write_allure_environment_properties() {
    local results_dir="${1:-}"
    if [[ -z "$results_dir" ]]; then
        echo "⚠️ Skipping Allure environment.properties: results directory is empty" >&2
        return 0
    fi

    mkdir -p "$results_dir"
    local props_file="${results_dir}/environment.properties"
    : > "$props_file"

    append_allure_property "$props_file" "ATP_APPLICATION_VERSION" "${ATP_APPLICATION_VERSION:-}"
    append_allure_property "$props_file" "TRIGGER_PIPELINE_SOURCE" "${TRIGGER_PIPELINE_SOURCE:-}"

    echo "📝 Wrote Allure environment.properties to ${props_file}"
}

# Write Allure executor.json for the Executors widget.
# TRIGGER_AUTHOR is shown as executor name (same as Bruno runner).
# Parameters:
#   $1 - allure-results directory
write_allure_executor_json() {
    local results_dir="${1:-}"
    if [[ -z "$results_dir" ]]; then
        echo "⚠️ Skipping Allure executor.json: results directory is empty" >&2
        return 0
    fi

    mkdir -p "$results_dir"
    local executor_file="${results_dir}/executor.json"
    local trigger_author
    trigger_author="$(printf '%s' "${TRIGGER_AUTHOR:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$trigger_author" ]]; then
        trigger_author="runner"
        echo "ℹ️ Allure executor: TRIGGER_AUTHOR is empty, using '${trigger_author}'"
    fi

    jq -n \
      --arg name "$trigger_author" \
      --arg type "atp3-newman-runner" \
      '{name: $name, type: $type}' > "$executor_file"

    echo "📝 Wrote Allure executor.json (name=${trigger_author}) to ${executor_file}"
}

# Write Allure Environments + Executors metadata after Newman finishes.
# Parameters:
#   $1 - allure-results directory
write_allure_report_metadata() {
    write_allure_environment_properties "$1"
    write_allure_executor_json "$1"
}

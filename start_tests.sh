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

source /tools/nmr_tools.sh
source /tools/test_params_convert.sh

# Local run flag
LOCAL_RUN="${LOCAL_RUN:-false}"

# ============================================
# Environment variables check and setup
# ============================================
if ! local_run_enabled; then
check_mandatory_env_vars
fi

# Convert TEST_PARAMS to valid format
TEST_PARAMS="$(convert_line_to_test_params "$TEST_PARAMS")" || exit 1

## Check and extract input test parameters for Newman
extract_newman_collections_list "$TEST_PARAMS" "NEWMAN_COLLECTIONS_ARRAY"
extract_flags_to_string "$TEST_PARAMS" "NEWMAN_FLAGS_CLI"

PARAMS_SOURCE=$(echo "$TEST_PARAMS" | jq -r '.params_source // "collections"')
if [[ "$PARAMS_SOURCE" == "execution_list" ]]; then
  # execution_list format: env file, common chaining, and CLI flags come from shell / EXTRA_VARS
  NEWMAN_ENVIRONMENT_FILE="${NEWMAN_ENVIRONMENT_FILE:-$ENVIRONMENT_NAME}"
  COMMON_ENV_FILE="$NEWMAN_ENVIRONMENT_FILE"
  case "${COMMON_ENVIRONMENT:-}" in
    [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) COMMON_ENV="true" ;;
    *) COMMON_ENV="false" ;;
  esac
  # NEWMAN_FLAGS (EXTRA_VARS) are user CLI flags; NEWMAN_FLAGS_CLI may still hold derived flags (globals/folder/env_vars/working_dir)
  # NEWMAN_FLAGS wins over JSON-derived --working-dir (merge prepends NEWMAN_FLAGS; Newman last-wins would otherwise let JSON override)
  if [[ -n "${NEWMAN_FLAGS:-}" ]]; then
    if [[ "${NEWMAN_FLAGS}" == *"--working-dir"* ]] && [[ "${NEWMAN_FLAGS_CLI:-}" == *"--working-dir"* ]]; then
      echo "⚠️ WARNING: NEWMAN_FLAGS contains --working-dir; ignoring TEST_PARAMS.working_dir"
      NEWMAN_FLAGS_CLI="$(echo "${NEWMAN_FLAGS_CLI}" | sed -E 's/(^|[[:space:]])--working-dir[[:space:]]+[^[:space:]]+//g' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/[[:space:]]+/ /g')"
    fi
    NEWMAN_FLAGS_CLI="${NEWMAN_FLAGS}${NEWMAN_FLAGS_CLI:+ ${NEWMAN_FLAGS_CLI}}"
  fi
  echo "➡️ params_source=execution_list; NEWMAN_ENVIRONMENT_FILE='${COMMON_ENV_FILE}'; COMMON_ENVIRONMENT='${COMMON_ENV}'; NEWMAN_FLAGS='${NEWMAN_FLAGS:-}'"
else
  # legacy collections format: env + common_environment + flags from TEST_PARAMS JSON
  COMMON_ENV=$(echo "$TEST_PARAMS" | jq -r '.common_environment')
  COMMON_ENV_FILE=$(echo "$TEST_PARAMS" | jq -r '.env')
  echo "➡️ params_source=collections; env='${COMMON_ENV_FILE}'; common_environment='${COMMON_ENV}'"
fi

# ============================================
# Launching Newman collections
# ============================================
if ! local_run_enabled; then

  echo "🚀 Launching Newman collections"

  # Move into the temp directory
  cd $TMP_DIR

  NEWMAN_REPORTING="\
  --reporters cli,allure,json-summary,htmlextra \
  --reporter-allure-resultsDir ${TMP_DIR}/allure-results \
  --reporter-summary-json-export ${TMP_DIR}/attachments/summary-json.json \
  --reporter-htmlextra-export ${TMP_DIR}/attachments/htmlextra.html"

  NEWMAN_FAILED=0
  idx=0
  for collection in "${NEWMAN_COLLECTIONS_ARRAY[@]}"; do
          idx=$((idx + 1))

          if [[ "$COMMON_ENV" == "true" ]]; then
              if (( idx == 1 )); then
                  env_flags="--environment ${COMMON_ENV_FILE} --export-environment env_2.json"
              else
                  env_flags="--environment env_${idx}.json --export-environment env_$((idx+1)).json"
              fi
              nr_command="newman run '${collection}' ${NEWMAN_FLAGS_CLI} ${env_flags} ${NEWMAN_REPORTING}"
          else
              nr_command="newman run '${collection}' ${NEWMAN_FLAGS_CLI} ${NEWMAN_REPORTING}"
          fi
      echo "Running command: '${nr_command}'"

      # Disable set -e for one command
      set +e
      eval "${nr_command}" || NEWMAN_FAILED=1
      exit_code=$?
      set -e

      if (( exit_code != 0 )); then
          echo "❌ Newman failed for collection: $collection" >&2
          NEWMAN_FAILED=1
      fi
  done
fi

# ============================================
# Launching Newman collections (LOCAL) — optional (For DEBUG)
# ============================================
# To enable, set LOCAL_COLLECTIONS_DIR to a directory containing Postman collections.
# Optional: set LOCAL_COLLECTIONS_GLOB (default: **/*.postman_collection.json)
if local_run_enabled; then
  if [[ -n "${LOCAL_COLLECTIONS_DIR}" && -d "${LOCAL_COLLECTIONS_DIR}" ]]; then
    echo "Found LOCAL_COLLECTIONS_DIR='${LOCAL_COLLECTIONS_DIR}' — launching local Newman collections"
    LOCAL_COLLECTIONS_GLOB="${LOCAL_COLLECTIONS_GLOB:-**/*.postman_collection.json}"

    # Collect local collections list
    # shellcheck disable=SC2207
    mapfile -t LOCAL_COLLECTIONS_ARRAY < <(cd "${LOCAL_COLLECTIONS_DIR}" && find . -type f -name "$(basename "${LOCAL_COLLECTIONS_GLOB}")" -o -path "${LOCAL_COLLECTIONS_GLOB}" | sort)

    if (( ${#LOCAL_COLLECTIONS_ARRAY[@]} == 0 )); then
      echo "⚠️ No local collections found by pattern '${LOCAL_COLLECTIONS_GLOB}' in ${LOCAL_COLLECTIONS_DIR}"
    else

      pushd "${LOCAL_COLLECTIONS_DIR}" >/dev/null
      for collection in "${LOCAL_COLLECTIONS_ARRAY[@]}"; do
          nr_command="newman run '${collection}' ${NEWMAN_FLAGS_CLI} ${NEWMAN_REPORTING}"
          echo "Running command: '${nr_command}'"

          set +e
          eval "${nr_command}" || NEWMAN_FAILED=1
          exit_code=$?
          set -e

          if (( exit_code != 0 )); then
              echo "❌ Newman failed for collection (LOCAL): $collection" >&2
              NEWMAN_FAILED=1
          fi
      done
      popd >/dev/null
      echo "✅ Test execution completed"
    fi
  else
    echo "ℹ️ LOCAL_COLLECTIONS_DIR is not set or not a directory — skipping local collections"
  fi
fi

# If you want to fail the job when any collection failed:
if (( NEWMAN_FAILED != 0 )); then
  echo "❌ One or more Newman runs failed"
  exit 1
fi

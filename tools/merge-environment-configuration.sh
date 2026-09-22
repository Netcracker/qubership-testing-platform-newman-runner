#!/bin/bash

# Merges a Postman environment (NEWMAN_ENVIRONMENT_FILE) into the rendered
# environment-configuration.json. values[] are combined by key; the Newman
# file wins on the same key. Other top-level keys from the Newman file overwrite.
# Relative paths resolve against the clone root (TMP_DIR, else PROJECT_DIR).
merge_newman_environment_file() {
    local newman_env_file="${1:-}"
    local project_dir="${PROJECT_DIR:-${TMP_DIR:-}}"
    local base_dir="${TMP_DIR:-$project_dir}"
    local output_path="${base_dir}/environment-configuration.json"
    local resolved_path merged

    if [ -z "$newman_env_file" ]; then
        echo "❌ ERROR: NEWMAN_ENVIRONMENT_FILE is empty; cannot merge Newman environment"
        return 1
    fi

    if [ -z "$base_dir" ]; then
        echo "❌ ERROR: PROJECT_DIR or TMP_DIR is not set; cannot merge Newman environment"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ ERROR: 'jq' is not available; cannot merge Newman environment"
        return 1
    fi

    case "$newman_env_file" in
        /*) resolved_path="$newman_env_file" ;;
        *) resolved_path="${base_dir}/${newman_env_file}" ;;
    esac

    if [ ! -f "$resolved_path" ]; then
        echo "❌ ERROR: Newman environment file not found: $resolved_path"
        return 1
    fi

    if ! jq empty "$resolved_path" >/dev/null 2>&1; then
        echo "❌ ERROR: Invalid JSON in Newman environment file: $resolved_path"
        return 1
    fi

    if [ ! -f "$output_path" ]; then
        cp "$resolved_path" "$output_path"
        ATP_ENVGENE_CONFIGURATION="$(cat "$output_path")"
        export ATP_ENVGENE_CONFIGURATION
        echo "✅ No rendered configuration found; wrote Newman environment to: $output_path"
        return 0
    fi

    if ! jq empty "$output_path" >/dev/null 2>&1; then
        echo "❌ ERROR: Invalid JSON in rendered environment configuration: $output_path"
        return 1
    fi

    echo "🔄 Merging Newman environment '$resolved_path' into $output_path"

    merged="$(jq --slurpfile incoming "$resolved_path" '
        . as $base
        | $incoming[0] as $file
        | ($base.values // []) as $base_values
        | ($file.values // []) as $file_values
        | reduce ($file | to_entries[]) as $e ($base;
            if $e.key == "values" then .
            else .[$e.key] = $e.value
            end)
        | if (($base_values | length) > 0) or (($file_values | length) > 0) then
            .values = (
              reduce $file_values[] as $item ($base_values;
                if any(.[]; .key == $item.key) then
                  map(if .key == $item.key then $item else . end)
                else
                  . + [$item]
                end)
            )
          else
            .
          end
    ' "$output_path")" || return 1

    printf '%s\n' "$merged" > "$output_path"
    export ATP_ENVGENE_CONFIGURATION="$merged"
    echo "✅ Merged Newman environment into: $output_path"
}

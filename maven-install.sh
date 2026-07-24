#!/bin/bash
# Optional Maven install for collections repos that ship Java dependencies.
# Enabled via MAVEN_BUILD (EXTRA_VARS/env) or legacy TEST_PARAMS.maven_build.

_is_truthy() {
    case "${1:-}" in
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

maven_install() {
    local enabled=false
    local json_maven_build=""
    local json_has_maven_build=false

    if [[ -n "${TEST_PARAMS:-}" ]]; then
        if echo "$TEST_PARAMS" | jq -e 'has("maven_build")' >/dev/null 2>&1; then
            json_has_maven_build=true
            json_maven_build=$(echo "$TEST_PARAMS" | jq -r '.maven_build')
        fi
    fi

    if [[ -v MAVEN_BUILD ]]; then
        if [[ "$json_has_maven_build" == true ]]; then
            echo "⚠️ WARNING: Both MAVEN_BUILD env and TEST_PARAMS.maven_build are set; using MAVEN_BUILD='${MAVEN_BUILD}'"
        fi
        if _is_truthy "$MAVEN_BUILD"; then
            enabled=true
        fi
    elif [[ "$json_has_maven_build" == true ]]; then
        if [[ "$json_maven_build" == "true" ]]; then
            enabled=true
        fi
    fi

    if [[ "$enabled" != true ]]; then
        echo "ℹ️ MAVEN_BUILD is off — skipping Maven install"
        return 0
    fi

    if [[ -z "${TMP_DIR:-}" ]]; then
        echo "❌ ERROR: TMP_DIR is not set (required for Maven install)"
        return 1
    fi

    if [[ ! -f "$TMP_DIR/settings.xml" ]]; then
        echo "❌ ERROR: MAVEN_BUILD is enabled but settings.xml not found at $TMP_DIR/settings.xml"
        return 1
    fi

    if ! command -v mvn >/dev/null 2>&1; then
        echo "❌ ERROR: mvn is not installed in the container"
        return 1
    fi

    echo "📦 Running Maven install in $TMP_DIR..."
    (
        cd "$TMP_DIR" || exit 1
        mvn install -Dmaven.wagon.http.ssl.insecure=true -s ./settings.xml
    ) || {
        echo "❌ ERROR: Maven install failed"
        return 1
    }

    echo "✅ Maven install completed"
    return 0
}

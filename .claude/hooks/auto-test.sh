#!/usr/bin/env bash
# PostToolUse hook for Write|Edit|MultiEdit (async)
# Automatically runs relevant tests after source file changes.
# Reads JSON from stdin, extracts file_path and cwd via python3.

# NOTE: Do NOT use set -e here — we need to handle test failures gracefully
set -uo pipefail

DEBOUNCE_FILE="/tmp/.claude-auto-test-last-run"
LOCK_FILE="/tmp/.claude-test-lock"
DEBOUNCE_SECONDS=30

# Read JSON from stdin
INPUT=$(cat)

# Extract file_path and cwd
eval "$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    fp = data.get('tool_input', {}).get('file_path', '')
    cwd = data.get('cwd', '')
    # Shell-escape single quotes
    fp = fp.replace(\"'\", \"'\\\\''\" )
    cwd = cwd.replace(\"'\", \"'\\\\''\" )
    print(f\"FILE_PATH='{fp}'\")
    print(f\"CWD='{cwd}'\")
except Exception:
    print(\"FILE_PATH=''\")
    print(\"CWD=''\")
" 2>/dev/null)"

# Exit if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only run for recognized source files
case "$FILE_PATH" in
    *.java|*.kt|*.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs)
        ;;
    *)
        exit 0
        ;;
esac

# Excluded directories
case "$FILE_PATH" in
    */node_modules/*|*/target/*|*/build/*|*/.git/*|*/generated/*|*/dist/*|*/out/*|*/vendor/*|*/__pycache__/*)
        exit 0
        ;;
esac

# Debounce: skip if last run was less than DEBOUNCE_SECONDS ago
if [[ -f "$DEBOUNCE_FILE" ]]; then
    LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_RUN))
    if [[ $ELAPSED -lt $DEBOUNCE_SECONDS ]]; then
        exit 0
    fi
fi

# Concurrency guard using flock (if available) or a simple lock file
acquire_lock() {
    if command -v flock &>/dev/null; then
        exec 200>"$LOCK_FILE"
        flock -n 200 || return 1
    else
        # Fallback: simple lock file with PID check
        if [[ -f "$LOCK_FILE.pid" ]]; then
            OLD_PID=$(cat "$LOCK_FILE.pid" 2>/dev/null || echo "")
            if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
                return 1
            fi
        fi
        echo $$ > "$LOCK_FILE.pid"
    fi
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE.pid" 2>/dev/null
    # flock is released automatically when fd 200 closes
}

if ! acquire_lock; then
    exit 0
fi

trap release_lock EXIT

# Update debounce timestamp
date +%s > "$DEBOUNCE_FILE"

# Determine project root and build tool, then run tests
PROJECT_DIR="${CWD:-$(dirname "$FILE_PATH")}"
TEST_OUTPUT=""
TEST_EXIT=0

run_tests() {
    local dir="$1"

    # Java/Maven: detect module from file path
    if [[ -f "${dir}/mvnw" ]] || [[ -f "${dir}/pom.xml" ]]; then
        # Find nearest pom.xml by walking up from the file
        local module_dir
        module_dir=$(dirname "$FILE_PATH")
        local module_flag=""
        while [[ "$module_dir" != "/" && "$module_dir" != "$dir" ]]; do
            if [[ -f "${module_dir}/pom.xml" ]]; then
                # Calculate relative module path
                local rel_path="${module_dir#"$dir"/}"
                if [[ "$rel_path" != "$module_dir" && -n "$rel_path" ]]; then
                    module_flag="-pl ${rel_path}"
                fi
                break
            fi
            module_dir=$(dirname "$module_dir")
        done

        local mvn_cmd="./mvnw"
        if command -v mvnd &>/dev/null; then
            mvn_cmd="mvnd"
        fi
        if [[ ! -x "${dir}/mvnw" && "$mvn_cmd" == "./mvnw" ]]; then
            mvn_cmd="./mvnw"
            chmod +x "${dir}/mvnw" 2>/dev/null || true
        fi

        cd "$dir"
        TEST_OUTPUT=$($mvn_cmd test $module_flag -q --no-transfer-progress 2>&1 | tail -30) || TEST_EXIT=$?
        return
    fi

    # Gradle
    if [[ -f "${dir}/gradlew" ]]; then
        cd "$dir"
        chmod +x ./gradlew 2>/dev/null || true
        TEST_OUTPUT=$(./gradlew test --quiet 2>&1 | tail -30) || TEST_EXIT=$?
        return
    fi

    # Node.js / TypeScript / JavaScript
    if [[ -f "${dir}/package.json" ]]; then
        cd "$dir"
        if [[ -f "${dir}/node_modules/.bin/jest" ]] || grep -q '"jest"' "${dir}/package.json" 2>/dev/null; then
            TEST_OUTPUT=$(npx jest --findRelatedTests "$FILE_PATH" --passWithNoTests --no-coverage 2>&1 | tail -30) || TEST_EXIT=$?
        else
            TEST_OUTPUT=$(npm test 2>&1 | tail -30) || TEST_EXIT=$?
        fi
        return
    fi

    # Python
    if [[ -f "${dir}/pyproject.toml" ]] || [[ -f "${dir}/pytest.ini" ]] || [[ -f "${dir}/setup.py" ]]; then
        cd "$dir"
        TEST_OUTPUT=$(python3 -m pytest -x --tb=short -q 2>&1 | tail -30) || TEST_EXIT=$?
        return
    fi

    # Go
    if [[ -f "${dir}/go.mod" ]]; then
        cd "$dir"
        local pkg_dir
        pkg_dir=$(dirname "$FILE_PATH")
        local rel_pkg="${pkg_dir#"$dir"}"
        rel_pkg="${rel_pkg#/}"
        if [[ -z "$rel_pkg" ]]; then
            rel_pkg="."
        fi
        TEST_OUTPUT=$(go test "./${rel_pkg}/..." 2>&1 | tail -30) || TEST_EXIT=$?
        return
    fi

    # Rust
    if [[ -f "${dir}/Cargo.toml" ]]; then
        cd "$dir"
        TEST_OUTPUT=$(cargo test --quiet 2>&1 | tail -30) || TEST_EXIT=$?
        return
    fi
}

# Walk up to find project root (where build file lives)
find_project_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "${dir}/pom.xml" ]] || \
           [[ -f "${dir}/build.gradle" ]] || [[ -f "${dir}/build.gradle.kts" ]] || \
           [[ -f "${dir}/package.json" ]] || \
           [[ -f "${dir}/pyproject.toml" ]] || [[ -f "${dir}/pytest.ini" ]] || \
           [[ -f "${dir}/go.mod" ]] || \
           [[ -f "${dir}/Cargo.toml" ]]; then
            echo "$dir"
            return
        fi
        dir=$(dirname "$dir")
    done
    echo "$PROJECT_DIR"
}

ROOT=$(find_project_root "$(dirname "$FILE_PATH")")
run_tests "$ROOT"

# Format output
if [[ $TEST_EXIT -eq 0 ]]; then
    RESULT="Tests PASSED after editing ${FILE_PATH##*/}"
else
    RESULT="Tests FAILED after editing ${FILE_PATH##*/}. Output:\n${TEST_OUTPUT}"
fi

# Escape for JSON
RESULT_JSON=$(python3 -c "
import json, sys
print(json.dumps(sys.stdin.read().strip()))
" <<< "$RESULT")

cat <<ENDJSON
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":${RESULT_JSON}}}
ENDJSON

exit 0

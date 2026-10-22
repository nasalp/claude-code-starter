#!/usr/bin/env bash
# PreToolUse hook for Write|Edit|MultiEdit
# Checks that a test file exists before modifying production source files.
# Reads JSON from stdin, extracts tool_input.file_path via python3.
#
# WARNINGS ONLY. Always exits 0 — per harness convention hooks warn, never
# block. The agent is responsible for reading and acting on the warning.
# Set SPEC_BYPASS=true to silence the warning.

set -uo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

# Exit 0 if file_path is empty
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# --- Test files: exit 0 ---
case "$FILE_PATH" in
    *.test.*|*.spec.*|*Test.java|*Tests.java|*IT.java|*_test.go|*_test.py|test_*.py|*Properties.java)
        exit 0
        ;;
esac

# --- Config/infra files: exit 0 ---
case "$FILE_PATH" in
    *.md|*.json|*.yaml|*.yml|*.toml|*.xml|*.css|*.html|*.properties|*.gradle|*.kts|*.sh|*.sql|*.env)
        exit 0
        ;;
    *Dockerfile*|*docker-compose*|*Makefile|*.gitignore|*.claudeignore)
        exit 0
        ;;
esac

# --- Known non-test-requiring patterns: exit 0 ---
case "$FILE_PATH" in
    *SPEC*|*PLAN*|*FEATURE*|*CLAUDE*|*settings*|*package-info*|*module-info*|*migration*|*generated*)
        exit 0
        ;;
esac

# --- Excluded directories: exit 0 ---
case "$FILE_PATH" in
    */node_modules/*|*/target/*|*/build/*|*/.git/*|*/generated/*|*/dist/*|*/out/*|*/vendor/*|*/__pycache__/*)
        exit 0
        ;;
esac

# --- Allowlist: trivial files that don't need dedicated tests ---
case "$FILE_PATH" in
    */dto/*|*/model/*|*/record/*)
        exit 0
        ;;
    *Configuration.*|*Config.*)
        exit 0
        ;;
    *Exception.*|*Error.*)
        exit 0
        ;;
    *Enum.*|*Constants.*|*Constant.*)
        exit 0
        ;;
    *package-info.java)
        exit 0
        ;;
esac
# Properties in config context (not test Properties classes)
case "$FILE_PATH" in
    */config/*Properties.*|*/configuration/*Properties.*)
        exit 0
        ;;
esac

# --- Determine if this is a production source file and look for tests ---

BASENAME=$(basename "$FILE_PATH")
DIRNAME=$(dirname "$FILE_PATH")
FILENAME_NO_EXT="${BASENAME%.*}"
EXTENSION="${BASENAME##*.}"

check_test_content() {
    local test_file="$1"
    local lang="$2"

    if [[ ! -f "$test_file" ]]; then
        return 1
    fi

    case "$lang" in
        java)
            grep -q '@Test' "$test_file" 2>/dev/null && return 0
            ;;
        ts|js)
            grep -qE '\b(it|test|describe)\s*\(' "$test_file" 2>/dev/null && return 0
            ;;
        python)
            grep -q 'def test_' "$test_file" 2>/dev/null && return 0
            ;;
        go)
            grep -q 'func Test' "$test_file" 2>/dev/null && return 0
            ;;
        rust)
            grep -q '#\[test\]' "$test_file" 2>/dev/null && return 0
            ;;
    esac
    return 1
}

TEST_FOUND=false

case "$EXTENSION" in
    java)
        # Mirror src/main -> src/test
        TEST_DIR=$(echo "$DIRNAME" | sed 's|/src/main/|/src/test/|')
        for suffix in Test Tests IT Spec; do
            TEST_FILE="${TEST_DIR}/${FILENAME_NO_EXT}${suffix}.java"
            if check_test_content "$TEST_FILE" "java"; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    ts|tsx)
        # Check same dir for .test.ts / .spec.ts
        for pattern in "${DIRNAME}/${FILENAME_NO_EXT}.test.ts" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.test.tsx" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.ts" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.tsx" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.ts" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.tsx" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.ts" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.tsx"; do
            if check_test_content "$pattern" "ts"; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    js|jsx)
        for pattern in "${DIRNAME}/${FILENAME_NO_EXT}.test.js" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.test.jsx" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.js" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.jsx" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.js" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.jsx" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.js" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.jsx"; do
            if check_test_content "$pattern" "js"; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    py)
        # Check tests/ dir for test_Name.py
        # Walk up to find tests/ directory
        SEARCH_DIR="$DIRNAME"
        while [[ "$SEARCH_DIR" != "/" ]]; do
            TEST_FILE="${SEARCH_DIR}/tests/test_${FILENAME_NO_EXT}.py"
            if check_test_content "$TEST_FILE" "python"; then
                TEST_FOUND=true
                break
            fi
            TEST_FILE="${SEARCH_DIR}/test/test_${FILENAME_NO_EXT}.py"
            if check_test_content "$TEST_FILE" "python"; then
                TEST_FOUND=true
                break
            fi
            SEARCH_DIR=$(dirname "$SEARCH_DIR")
        done
        ;;
    go)
        TEST_FILE="${DIRNAME}/${FILENAME_NO_EXT}_test.go"
        if check_test_content "$TEST_FILE" "go"; then
            TEST_FOUND=true
        fi
        ;;
    rs)
        # Check for inline #[test] in the source file itself, or tests/ dir
        if grep -q '#\[test\]' "$FILE_PATH" 2>/dev/null; then
            TEST_FOUND=true
        fi
        # Check tests/ directory at crate root
        SEARCH_DIR="$DIRNAME"
        while [[ "$SEARCH_DIR" != "/" ]]; do
            if [[ -f "${SEARCH_DIR}/Cargo.toml" ]]; then
                # Look for test files in tests/ dir
                if [[ -d "${SEARCH_DIR}/tests" ]]; then
                    for tf in "${SEARCH_DIR}/tests/"*.rs; do
                        if [[ -f "$tf" ]] && grep -q '#\[test\]' "$tf" 2>/dev/null; then
                            TEST_FOUND=true
                            break
                        fi
                    done
                fi
                break
            fi
            SEARCH_DIR=$(dirname "$SEARCH_DIR")
        done
        ;;
    kt|kts)
        # Mirror src/main → src/test, suffix Test before extension.
        TEST_DIR=$(echo "$DIRNAME" | sed 's|/src/main/|/src/test/|')
        for suffix in Test Tests IT Spec; do
            for ext in kt; do
                TEST_FILE="${TEST_DIR}/${FILENAME_NO_EXT}${suffix}.${ext}"
                if [[ -f "$TEST_FILE" ]] && grep -qE '@Test\b|fun .*Test\(\)|class .*Test' "$TEST_FILE" 2>/dev/null; then
                    TEST_FOUND=true
                    break 2
                fi
            done
        done
        ;;
    scala)
        TEST_DIR=$(echo "$DIRNAME" | sed 's|/src/main/|/src/test/|')
        for suffix in Test Tests Spec IT; do
            TEST_FILE="${TEST_DIR}/${FILENAME_NO_EXT}${suffix}.scala"
            if [[ -f "$TEST_FILE" ]] && grep -qE 'class .*Test|class .*Spec|extends .*FunSuite|extends .*AnyFlatSpec' "$TEST_FILE" 2>/dev/null; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    groovy)
        TEST_DIR=$(echo "$DIRNAME" | sed 's|/src/main/|/src/test/|')
        for suffix in Test Tests Spec IT; do
            TEST_FILE="${TEST_DIR}/${FILENAME_NO_EXT}${suffix}.groovy"
            if [[ -f "$TEST_FILE" ]] && grep -qE 'class .*Test|class .*Spec|@Test\b|def "[^"]+"' "$TEST_FILE" 2>/dev/null; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    php)
        # PHPUnit / Pest convention: tests/ alongside src/, FooTest.php naming.
        SEARCH_DIR="$DIRNAME"
        while [[ "$SEARCH_DIR" != "/" ]]; do
            if [[ -f "${SEARCH_DIR}/composer.json" ]]; then
                if [[ -d "${SEARCH_DIR}/tests" ]]; then
                    for tf in "${SEARCH_DIR}/tests"/${FILENAME_NO_EXT}Test.php "${SEARCH_DIR}/tests"/**/${FILENAME_NO_EXT}Test.php; do
                        if [[ -f "$tf" ]] && grep -qE 'class .*Test\b|public function test|it\(|test\(' "$tf" 2>/dev/null; then
                            TEST_FOUND=true
                            break 2
                        fi
                    done
                fi
                break
            fi
            SEARCH_DIR=$(dirname "$SEARCH_DIR")
        done
        ;;
    mjs|cjs)
        # Same convention as ts/js, just different extension.
        for pattern in "${DIRNAME}/${FILENAME_NO_EXT}.test.${EXTENSION}" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.${EXTENSION}" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.${EXTENSION}" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.${EXTENSION}"; do
            if check_test_content "$pattern" "ts"; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    vue|svelte)
        # Component frameworks usually colocate tests as Foo.test.ts / Foo.spec.ts
        for pattern in "${DIRNAME}/${FILENAME_NO_EXT}.test.ts" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.test.tsx" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.test.js" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.ts" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.tsx" \
                       "${DIRNAME}/${FILENAME_NO_EXT}.spec.js" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.test.ts" \
                       "${DIRNAME}/__tests__/${FILENAME_NO_EXT}.spec.ts"; do
            if check_test_content "$pattern" "ts"; then
                TEST_FOUND=true
                break
            fi
        done
        ;;
    *)
        # Unknown file type — not a recognized production source, skip
        exit 0
        ;;
esac

if [[ "$TEST_FOUND" == "true" ]]; then
    exit 0
fi

# No test file found — check for bypass
if [[ "${SPEC_BYPASS:-}" == "true" ]]; then
    echo "[hook] Bypassed by SPEC_BYPASS=true" >&2
    exit 0
fi

# Warn — per harness convention, hooks emit warnings, not blocks.
# The agent is responsible for reading and acting on this warning.
MSG="[require-test-first] WARNING: No test file found for '$FILE_PATH'."
echo "$MSG" >&2
echo "[require-test-first] Rule: SPEC → TEST → IMPLEMENT (RED-GREEN-REFACTOR)." >&2
echo "[require-test-first] Write the failing test FIRST. The warning won't block but the rule still applies." >&2
exit 0

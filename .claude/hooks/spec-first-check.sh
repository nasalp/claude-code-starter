#!/usr/bin/env bash
#
# Pre-commit hook: Verify that production code changes have corresponding
# specs and tests. Language/framework agnostic.
#
# Called by Claude Code's PreToolUse hook system on Write/Edit of source files.
# Exits 0 to allow, exit 2 to block.
#
# Set SPEC_BYPASS=true to bypass blocking.
#
set -euo pipefail

# Read the tool input from stdin (JSON)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
    exit 0  # Can't determine file path, allow
fi

# --- Detect if this is a production source file ---
# Language-agnostic: check common source directories
IS_PROD_SOURCE=false

# Java/Kotlin/Scala/Groovy
if echo "$FILE_PATH" | grep -qE "src/main/(java|kotlin|scala|groovy)/"; then
    IS_PROD_SOURCE=true
fi
# Groovy scripts outside standard layout
if echo "$FILE_PATH" | grep -qE "\.groovy$" && ! echo "$FILE_PATH" | grep -qE "(test|Test|Spec)"; then
    IS_PROD_SOURCE=true
fi

# Python (not tests, not __pycache__)
if echo "$FILE_PATH" | grep -qE "\.py$" && ! echo "$FILE_PATH" | grep -qE "(test_|_test\.py|tests/|__pycache__|conftest)"; then
    IS_PROD_SOURCE=true
fi

# Go (not _test.go)
if echo "$FILE_PATH" | grep -qE "\.go$" && ! echo "$FILE_PATH" | grep -qE "_test\.go$"; then
    IS_PROD_SOURCE=true
fi

# TypeScript/JavaScript in src/ (not tests, not __tests__)
if echo "$FILE_PATH" | grep -qE "\.(ts|tsx|js|jsx)$" && echo "$FILE_PATH" | grep -qE "/src/" && ! echo "$FILE_PATH" | grep -qE "(__tests__|\.test\.|\.spec\.|test/)"; then
    IS_PROD_SOURCE=true
fi

# Rust (not in tests/)
if echo "$FILE_PATH" | grep -qE "\.rs$" && echo "$FILE_PATH" | grep -qE "/src/" && ! echo "$FILE_PATH" | grep -qE "(tests/|#\[cfg\(test\)\])"; then
    IS_PROD_SOURCE=true
fi

# Swift (not Tests/)
if echo "$FILE_PATH" | grep -qE "\.swift$" && ! echo "$FILE_PATH" | grep -qE "(Tests/|Test\.swift)"; then
    IS_PROD_SOURCE=true
fi

# C/C++ source (not test files)
if echo "$FILE_PATH" | grep -qE "\.(c|cpp|cc|cxx|h|hpp)$" && ! echo "$FILE_PATH" | grep -qE "(test|Test|_test|_Test)"; then
    IS_PROD_SOURCE=true
fi

# PHP (not tests)
if echo "$FILE_PATH" | grep -qE "\.php$" && ! echo "$FILE_PATH" | grep -qE "(Test\.php|tests/)"; then
    IS_PROD_SOURCE=true
fi

# Perl (not .t files, not t/ directory)
if echo "$FILE_PATH" | grep -qE "\.(pl|pm)$" && ! echo "$FILE_PATH" | grep -qE "(\.t$|/t/)"; then
    IS_PROD_SOURCE=true
fi

if [ "$IS_PROD_SOURCE" = false ]; then
    exit 0  # Not production source, allow
fi

# --- Skip known exceptions ---
# Configuration classes, package-info, migrations, generated code
if echo "$FILE_PATH" | grep -qE "(package-info|module-info|migration|generated|\.g\.|\.gen\.)"; then
    exit 0
fi

# --- Check: does a spec directory exist in the project? ---
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$PROJECT_ROOT" ]; then
    exit 0  # Not in a git repo, skip check
fi

SPEC_DIR="$PROJECT_ROOT/spec"
if [ ! -d "$SPEC_DIR" ]; then
    # No spec directory in project — this rule doesn't apply
    exit 0
fi

# --- Check: were spec files modified in this git session? ---
SPEC_CHANGED=$(git diff --cached --name-only 2>/dev/null | grep -c "^spec/" || true)
SPEC_UNSTAGED=$(git diff --name-only 2>/dev/null | grep -c "^spec/" || true)

if [ "$SPEC_CHANGED" -gt 0 ] || [ "$SPEC_UNSTAGED" -gt 0 ]; then
    exit 0  # Specs were modified, good
fi

# --- Check for bypass ---
if [[ "${SPEC_BYPASS:-}" == "true" ]]; then
    echo "[spec-first] Bypassed by SPEC_BYPASS=true" >&2
    exit 0
fi

# --- Warn: production source edited without spec change ---
# Per harness convention (rules/common/hooks.md): hooks emit warnings, never block.
# The agent is responsible for reading and acting on this warning.
echo "[spec-first] WARNING: Modifying production source without a spec change." >&2
echo "[spec-first] File: $FILE_PATH" >&2
echo "[spec-first] Rule: SPEC → TEST → IMPLEMENT → VERIFY" >&2
echo "[spec-first] Consider: Is there a spec in spec/features/ for this change?" >&2
echo "[spec-first] If yes: ensure the spec covers the new behavior, then continue." >&2
echo "[spec-first] If no: write/update the spec FIRST. The warning won't block but the rule still applies." >&2
exit 0

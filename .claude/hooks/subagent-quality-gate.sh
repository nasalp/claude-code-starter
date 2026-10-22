#!/usr/bin/env bash
#
# Hook: subagent-quality-gate.sh
# Purpose: Enforce quality rules on subagent tool calls based on agent_type.
# Trigger: PreToolUse on Edit|Write|Bash (fires for both main + subagents)
#
# Uses the agent_type field to apply context-specific rules:
#   - Any subagent writing source files must also write tests
#   - Any subagent writing workflows must also write BATS tests
#   - Any subagent running git push must have run tests first
#
# WARNINGS ONLY. Always exits 0 and re-emits the original tool input on stdout.
# Per harness convention all hooks warn (stderr), never block.

set -uo pipefail

INPUT=$(cat)

# Parse fields with python3 fallback (jq may be missing on minimal hosts).
parse_field() {
    local field="$1"
    if command -v jq >/dev/null 2>&1; then
        echo "$INPUT" | jq -r "$field // \"\"" 2>/dev/null || echo ""
    else
        echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # field is a jq-style path like '.agent_type' or '.tool_input.file_path'
    parts = '$field'.lstrip('.').split('.')
    cur = data
    for p in parts:
        if isinstance(cur, dict):
            cur = cur.get(p, '')
        else:
            cur = ''
            break
    print(cur if cur is not None else '')
except Exception:
    print('')
" 2>/dev/null || echo ""
    fi
}

AGENT_TYPE=$(parse_field '.agent_type')
TOOL_NAME=$(parse_field '.tool_name')
FILE_PATH=$(parse_field '.tool_input.file_path')
COMMAND=$(parse_field '.tool_input.command')

# Pass-through helper: PreToolUse hooks should re-emit the tool input on stdout
# so Claude Code can forward it untouched. Plain warning text on stdout would
# be parsed as a hook-decision JSON and (best case) ignored, (worst case) noisy.
emit_input_and_exit() {
    echo "$INPUT"
    exit 0
}

# Only apply to subagents (agent_type is empty for the main conversation).
if [[ -z "$AGENT_TYPE" ]]; then
    emit_input_and_exit
fi

# ── Rule 1: Subagent git commit/push must mention tests ──
if [[ "$TOOL_NAME" == "Bash" ]] && echo "$COMMAND" | grep -qE "git (commit|push)"; then
    {
        echo "[subagent-gate:$AGENT_TYPE] WARNING: Committing/pushing from a subagent."
        echo "  Ensure tests were written or updated alongside the changes."
        echo "  If you haven't run tests, do so before pushing."
    } >&2
    emit_input_and_exit
fi

# ── Rule 2: Subagent writing workflow files without tests dir ──
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    if [[ "$FILE_PATH" == */.github/workflows/*.yml ]] || [[ "$FILE_PATH" == */.github/workflows/*.yaml ]]; then
        PROJECT_ROOT=$(echo "$FILE_PATH" | sed 's|/.github/workflows/.*||')
        if [[ -n "$PROJECT_ROOT" ]] && [[ ! -d "$PROJECT_ROOT/tests" ]]; then
            {
                echo "[subagent-gate:$AGENT_TYPE] WARNING: Writing a workflow file without tests/ directory."
                echo "  Create BATS tests in $PROJECT_ROOT/tests/ for workflow shell logic."
                echo "  Per harness convention, the parent agent must read this warning."
            } >&2
        fi
    fi
fi

# ── Rule 3: Subagent writing JVM source must have corresponding test ──
# Java + Kotlin + Scala + Groovy in src/main/<lang>/...
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    if echo "$FILE_PATH" | grep -qE '/src/main/(java|kotlin|scala|groovy)/.*\.(java|kt|scala|groovy)$'; then
        # Derive expected test path via portable parameter manipulation:
        # swap src/main → src/test in the directory, suffix Test before extension.
        SRC_DIR=$(dirname "$FILE_PATH")
        TEST_DIR=$(echo "$SRC_DIR" | sed 's|/src/main/|/src/test/|')
        SRC_BASE=$(basename "$FILE_PATH")
        SRC_EXT="${SRC_BASE##*.}"
        SRC_NAME="${SRC_BASE%.*}"
        TEST_PATH="${TEST_DIR}/${SRC_NAME}Test.${SRC_EXT}"
        if [[ ! -f "$TEST_PATH" ]]; then
            {
                echo "[subagent-gate:$AGENT_TYPE] WARNING: Writing JVM production source without a test."
                echo "  Source: $FILE_PATH"
                echo "  Expected test: $TEST_PATH"
                echo "  Write the test first or alongside the implementation."
            } >&2
        fi
    fi
fi

# ── Rule 4: Subagent writing TypeScript/JavaScript source must have a test ──
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    if echo "$FILE_PATH" | grep -qE '/src/.*\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$'; then
        # Skip test files themselves
        if [[ "$FILE_PATH" != *test* ]] && [[ "$FILE_PATH" != *Test* ]] && [[ "$FILE_PATH" != *spec* ]]; then
            BASENAME=$(basename "$FILE_PATH" | sed -E 's/\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$//')
            PROJECT_ROOT=$(echo "$FILE_PATH" | sed 's|/src/.*||')
            if [[ -n "$PROJECT_ROOT" ]] && ! find "$PROJECT_ROOT" -path "*${BASENAME}*test*" -o -path "*${BASENAME}*Test*" 2>/dev/null | grep -q .; then
                {
                    echo "[subagent-gate:$AGENT_TYPE] WARNING: Writing TypeScript/JavaScript source without a test."
                    echo "  Source: $FILE_PATH"
                    echo "  Write a corresponding test file."
                } >&2
            fi
        fi
    fi
fi

emit_input_and_exit

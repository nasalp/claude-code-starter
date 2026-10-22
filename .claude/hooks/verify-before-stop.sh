#!/usr/bin/env bash
# Stop hook: runs the full test suite before allowing session to end.
# Reads JSON from stdin, extracts cwd and stop_hook_active via python3.

set -uo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract cwd and stop_hook_active. Use a sentinel-separated stdout instead of
# `eval` so even pathological cwd values (single quotes, $(), backticks) cannot
# influence shell parsing.
PYOUT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    cwd = data.get('cwd', '')
    active = data.get('stop_hook_active', False)
    print(cwd)
    print('true' if active else 'false')
except Exception:
    print('')
    print('false')
" 2>/dev/null) || PYOUT=$'\nfalse'

CWD=$(printf '%s\n' "$PYOUT" | sed -n '1p')
STOP_HOOK_ACTIVE=$(printf '%s\n' "$PYOUT" | sed -n '2p')

# Recursion guard
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# Escape hatch — total silence (no reminder, no run)
if [[ "${SKIP_VERIFY_STOP:-false}" == "true" ]]; then
    exit 0
fi

# Default: warn-only. Running the full build/test suite on EVERY Stop is too
# heavy — Stop fires at every turn end, not just at true task-end, so this
# would re-run a multi-minute `verify` repeatedly and duplicate the agent's
# own pre-push obligation. Emit a reminder the agent must act on; gate the
# actual full run behind an explicit opt-in.
if [[ "${RUN_VERIFY_STOP:-false}" != "true" ]]; then
    echo "[verify-before-stop] Reminder: before declaring this done, run the canonical verify gate (scripts/verify-like-ci.sh, or the full build/test for this stack) and confirm it is green — per git-workflow.md. (Opt-in auto-run here: RUN_VERIFY_STOP=true. Silence: SKIP_VERIFY_STOP=true.)" >&2
    exit 0
fi

# RUN_VERIFY_STOP=true — execute the full suite below.
# Need a working directory
if [[ -z "$CWD" ]]; then
    echo "WARNING: No working directory provided to verify-before-stop hook." >&2
    exit 0
fi

cd "$CWD" || exit 0

# Detect build tool and run full test suite
TEST_OUTPUT=""
TEST_EXIT=0

run_full_tests() {
    # Java/Maven
    if [[ -f "mvnw" ]] || [[ -f "pom.xml" ]]; then
        local mvn_cmd="./mvnw"
        if command -v mvnd &>/dev/null; then
            mvn_cmd="mvnd"
        fi
        if [[ -f "mvnw" ]]; then
            chmod +x ./mvnw 2>/dev/null || true
        fi
        TEST_OUTPUT=$($mvn_cmd verify -q --no-transfer-progress 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # Gradle
    if [[ -f "gradlew" ]]; then
        chmod +x ./gradlew 2>/dev/null || true
        TEST_OUTPUT=$(./gradlew build --quiet 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # Node.js
    if [[ -f "package.json" ]]; then
        TEST_OUTPUT=$(npm test 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # Python
    if [[ -f "pyproject.toml" ]] || [[ -f "pytest.ini" ]] || [[ -f "setup.py" ]]; then
        TEST_OUTPUT=$(python3 -m pytest --tb=short -q 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # Go
    if [[ -f "go.mod" ]]; then
        TEST_OUTPUT=$(go test ./... 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # Rust
    if [[ -f "Cargo.toml" ]]; then
        TEST_OUTPUT=$(cargo test 2>&1 | tail -50) || TEST_EXIT=$?
        return
    fi

    # No build tool found — nothing to verify
    echo "No recognized build tool found in $CWD — skipping test verification." >&2
}

run_full_tests

if [[ $TEST_EXIT -ne 0 ]]; then
    echo "========================================" >&2
    echo "[verify-before-stop] WARNING: Tests failed at session end!" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Test output (last 50 lines):" >&2
    echo "$TEST_OUTPUT" >&2
    echo "" >&2
    echo "Fix the failing tests before considering the session complete." >&2
    echo "Per harness convention, this is a warning, not a block — but the rule applies." >&2
    # Always exit 0 — warnings only.
fi

exit 0

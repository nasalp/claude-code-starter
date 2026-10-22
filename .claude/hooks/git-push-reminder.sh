#!/usr/bin/env bash
# Hook: git-push-reminder.sh
# Trigger: PreToolUse on Bash
# Purpose: Remind to review changes before pushing. WARNING ONLY — never blocks.
#
# Always exit 0. Per harness convention: hooks emit warnings, don't break.
# The real enforcement of "don't push without local verification" is on the CI side
# (see rules/common/git-workflow.md § Pre-Push Verification).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# Match git push (but not git push --help, etc.)
if echo "$COMMAND" | grep -qE '(^|[[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
    echo "[Hook] REMINDER: Review changes before push." >&2
    echo "[Hook] Per rules/common/git-workflow.md § Pre-Push Verification:" >&2
    echo "[Hook]   - Run the canonical local-CI-parity gate first" >&2
    echo "[Hook]   - Reviewer-fix follow-ups must also re-verify" >&2
    echo "[Hook]   - Skip flags (-DskipTests, -x test) are NOT a pre-push gate" >&2
fi

echo "$INPUT"
exit 0

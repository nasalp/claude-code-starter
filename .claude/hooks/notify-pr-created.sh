#!/usr/bin/env bash
# Hook: notify-pr-created.sh
# Trigger: PostToolUse on Bash
# Purpose: After a successful `gh pr create`, surface the PR URL and a
#          one-liner review command so the operator can act on it without
#          searching the bash output.
#
# WARNINGS ONLY (informational stderr). Always exits 0.
# Per harness convention: hooks never block.

set -uo pipefail

INPUT=$(cat)

PARSE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    cmd = data.get('tool_input', {}).get('command', '') or ''
    out = data.get('tool_output', {}).get('output', '') or ''
    print(cmd.replace('\n', ' '))
    print('---__SEP__---')
    print(out)
except Exception:
    print('')
    print('---__SEP__---')
    print('')
" 2>/dev/null) || PARSE=$'\n---__SEP__---\n'

CMD=$(printf '%s\n' "$PARSE" | sed -n '1,/^---__SEP__---$/p' | sed '$d')
OUT=$(printf '%s\n' "$PARSE" | sed -n '/^---__SEP__---$/,$p' | sed '1d')

# Only act on `gh pr create` invocations.
if ! echo "$CMD" | grep -qE 'gh pr create\b'; then
    echo "$INPUT"
    exit 0
fi

# Extract the first GitHub PR URL from the output.
PR_URL=$(echo "$OUT" | grep -Eo 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)

if [[ -n "$PR_URL" ]]; then
    REPO=$(echo "$PR_URL" | sed -E 's|https://github\.com/([^/]+/[^/]+)/pull/[0-9]+|\1|')
    PR_NUM=$(echo "$PR_URL" | sed -E 's|.+/pull/([0-9]+)|\1|')
    {
        echo "[notify-pr-created] PR created: $PR_URL"
        echo "[notify-pr-created] Review:     gh pr view $PR_NUM --repo $REPO"
    } >&2
fi

echo "$INPUT"
exit 0

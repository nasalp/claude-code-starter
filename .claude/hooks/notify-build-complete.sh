#!/usr/bin/env bash
# Hook: notify-build-complete.sh
# Trigger: PostToolUse on Bash (async)
# Purpose: After a frontend build command completes, emit a one-line marker
#          so subsequent agents/operators know the build finished. This hook
#          is a hook-style placeholder: real build analysis (size deltas,
#          regressions) belongs in a proper CI step.
#
# WARNINGS ONLY (informational stderr). Always exits 0.

set -uo pipefail

INPUT=$(cat)

CMD=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', '') or '')
except Exception:
    print('')
" 2>/dev/null) || CMD=""

if echo "$CMD" | grep -qE '\b(npm run build|pnpm build|pnpm run build|yarn build|bun run build)\b'; then
    echo "[notify-build-complete] Build finished — async analysis stub fired." >&2
fi

echo "$INPUT"
exit 0

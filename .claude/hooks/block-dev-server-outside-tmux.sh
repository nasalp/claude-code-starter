#!/usr/bin/env bash
# Hook: block-dev-server-outside-tmux.sh
# Trigger: PreToolUse on Bash
# Purpose: Block long-running dev servers (npm/pnpm/yarn/bun run dev) from
#          launching outside a tmux session, so logs are accessible after
#          the agent's bash shell exits.
#
# Exit 0 to allow, exit 2 to block.
# Skipped on Windows (no tmux convention).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# Skip on Windows
if [[ "$(uname -s)" =~ ^MINGW|MSYS|CYGWIN ]]; then
    echo "$INPUT"
    exit 0
fi

# Pattern: any of npm/pnpm/yarn/bun running a "dev" script.
# Per harness convention: warning only, never block.
if echo "$COMMAND" | grep -qE '(npm run dev|pnpm( run)? dev|yarn dev|bun run dev)\b'; then
    if [ -z "${TMUX:-}" ]; then
        echo "[block-dev-server] WARNING: Dev server should run in tmux for log access." >&2
        echo "[block-dev-server] Wrap with: tmux new-session -d -s dev '<your-command>'" >&2
        echo "[block-dev-server] Or set TMUX env var if intentionally outside a tmux session." >&2
        echo "[block-dev-server] Per harness convention, this is a warning, not a block." >&2
    fi
fi

echo "$INPUT"
exit 0

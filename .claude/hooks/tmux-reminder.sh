#!/usr/bin/env bash
# Hook: tmux-reminder.sh
# Trigger: PreToolUse on Bash
# Purpose: Remind to use tmux for long-running commands so output survives
#          the agent's bash shell. WARNING ONLY — never blocks.
#
# Always exit 0. Per harness convention: hooks emit warnings, don't break.

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

# Long-running command patterns
LONG_RUNNING_PATTERNS='npm (install|test)|pnpm (install|test)|yarn (install|test)|bun (install|test)|cargo build|make\b|docker\b|pytest|vitest|playwright|mvnd?(w)? (test|verify|install)|gradlew? (test|build)'

if echo "$COMMAND" | grep -qE "$LONG_RUNNING_PATTERNS"; then
    if [ -z "${TMUX:-}" ]; then
        echo "[Hook] WARNING: Consider running in tmux for session persistence." >&2
        echo "[Hook] Long-running output is lost when the bash shell exits." >&2
    fi
fi

echo "$INPUT"
exit 0

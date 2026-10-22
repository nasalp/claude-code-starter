#!/usr/bin/env bash
# check-cursor-available.sh — probe the Cursor `agent` CLI (Composer worker).
# Mirrors check-codex-available.sh. Exit 0 when usable; non-zero with a
# claude+sonnet fallback recommendation otherwise.
set -uo pipefail

_cursor_present() { command -v agent >/dev/null 2>&1; }

# 0 if `agent status` reports an authenticated session.
_cursor_authed() { agent status >/dev/null 2>&1; }

check_cursor_main() {
  if ! _cursor_present; then
    echo "cursor 'agent' NOT available on PATH."
    echo "ACTION: run scripts/install-agent-clis.sh, or set BUILDER_ENGINE=claude BUILDER_MODEL=sonnet (fallback)."
    return 1
  fi
  if _cursor_authed; then
    echo "cursor 'agent' available and authed — OK (Composer builder/watcher enabled)."
    return 0
  fi
  echo "cursor 'agent' on PATH but not authed (run: agent login)."
  echo "ACTION: authenticate, or fall back to claude+sonnet (BUILDER_ENGINE=claude BUILDER_MODEL=sonnet)."
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_cursor_main
fi

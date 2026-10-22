#!/usr/bin/env bash
set -uo pipefail

# Echo a message + return 0 (codex on PATH) or 1 (missing).
# Used by Phase 2 to decide between 2-codex+1-claude (preferred) and
# 3-claude (fallback). See ../docs/phase-2-plan-consensus.md.
_codex_present() {
  command -v codex >/dev/null 2>&1
}

# Stable text the caller can grep for. STATE goes first so a one-liner
# `check-codex-available.sh | head -1 | awk '{print $1}'` works.
_status_line() {
  if _codex_present; then
    echo "AVAILABLE codex on PATH at $(command -v codex)"
  else
    echo "MISSING codex CLI not installed"
  fi
}

# Human-readable second line: what the orchestrator should do.
_action_hint() {
  if _codex_present; then
    echo "ACTION spawn 2 codex + 1 claude opus for Phase 2 plan-consensus"
  else
    echo "ACTION fallback to 3 claude opus with sharply different brief framings; install codex: https://github.com/openai/codex-cli"
  fi
}

check_codex_main() {
  _status_line
  _action_hint
  _codex_present
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  check_codex_main "$@"
fi

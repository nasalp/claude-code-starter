#!/usr/bin/env bash
# install-agent-clis.sh [--check]
# Idempotent installer for the worker CLIs used by the mixed-model harness:
#   - Cursor `agent` (Composer)  via  curl https://cursor.com/install -fsS | bash
#   - `gemini`                   via  npm i -g @google/gemini-cli
# --check reports presence without installing. Present CLIs are never reinstalled.
# Surfaced from setup.sh; never auto-run unattended.
set -uo pipefail

check_only=false
[[ "${1:-}" == "--check" ]] && check_only=true

# _ensure <binary> <human-name> <install-command...>
_ensure() {
  local bin="$1" name="$2"; shift 2
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  ✓ $name ($bin) already installed: $(command -v "$bin")"
    return 0
  fi
  if $check_only; then
    echo "  ✗ $name ($bin) MISSING — would install: $*"
    return 0
  fi
  echo "  → installing $name: $*"
  "$@"
}

install_agent_clis() {
  echo "Installing worker CLIs (idempotent)…"
  # Cursor agent: the official installer pipes a script into bash.
  if command -v agent >/dev/null 2>&1; then
    echo "  ✓ cursor agent already installed: $(command -v agent)"
  elif $check_only; then
    echo "  ✗ cursor agent MISSING — would install: curl https://cursor.com/install -fsS | bash"
  else
    echo "  → installing cursor agent: curl https://cursor.com/install -fsS | bash"
    curl https://cursor.com/install -fsS | bash
  fi
  _ensure gemini "Gemini CLI" npm i -g @google/gemini-cli
  echo "Done. (Authenticate with: agent login ; gemini  then /auth)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_agent_clis
fi

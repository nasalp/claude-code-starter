#!/usr/bin/env bash
# PreToolUse(Edit|Write) guard: when the session is the mixed-model ORCHESTRATOR
# (AGENT_ROLE=orchestrator), Claude must DELEGATE implementation to a builder
# (agent_spawn / launch-builder) rather than edit production source itself.
#
# Warn-only (exit 0), per the harness hook convention — the agent MUST read the
# warning. Inert unless AGENT_ROLE=orchestrator, so normal sessions and builder
# sessions are unaffected. See ~/.claude/rules/build-via-orchestrator.md and
# docs/mixed-model-agents.md.
set -uo pipefail

# Only the orchestrator role is gated.
[[ "${AGENT_ROLE:-}" == "orchestrator" ]] || exit 0

input="$(cat 2>/dev/null || true)"
file="$(printf '%s' "$input" \
  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[[ -z "$file" ]] && exit 0

# Allowlist: artifacts the orchestrator legitimately authors itself.
case "$file" in
  *.md|*.txt|*.json|*.yml|*.yaml) exit 0 ;;
  */spec/*|*/docs/*|*/packets/*|*/.claude/*|*/plans/*) exit 0 ;;
esac

cat >&2 <<EOF
[orchestrator-no-direct-impl] WARNING: orchestrator session is editing production
source directly:
    $file
The manager-model directive says Claude orchestrates and DELEGATES implementation.
Route this through a builder instead, e.g.:
    scripts/agent-spawn.sh builder composer <worktree> <packet>
(or launch-builder.sh). If this edit is genuinely orchestrator-owned scaffolding,
ignore this warning. To enforce hard, deny Edit/Write for source paths in the
orchestrator's .claude/settings.json.
EOF
exit 0

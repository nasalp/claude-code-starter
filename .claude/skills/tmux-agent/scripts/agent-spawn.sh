#!/usr/bin/env bash
# agent_spawn <role> <provider> <worktree> <prompt_file>
# Unified role+provider spawner. provider="auto" resolves via agent-routing.
# Composes the provider's CLI command, mounts rules for no-add-dir providers,
# writes a cost-ledger row + budget counter, and starts a named tmux session.
#
# Existing launch-builder.sh / watcher-loop.sh keep working; this is additive.
set -uo pipefail

SPAWN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/agent-providers.sh
source "$SPAWN_DIR/lib/agent-providers.sh"
# shellcheck source=lib/agent-routing.sh
source "$SPAWN_DIR/lib/agent-routing.sh"
# shellcheck source=lib/cost-ledger.sh
source "$SPAWN_DIR/lib/cost-ledger.sh"
# shellcheck source=lib/agent-budget.sh
source "$SPAWN_DIR/lib/agent-budget.sh"

agent_spawn() {
  local role="$1" provider="$2" wt="$3" prompt="$4"
  [[ -n "$role" && -n "$provider" && -n "$wt" && -n "$prompt" ]] || {
    echo "usage: agent_spawn <role> <provider> <worktree> <prompt_file>" >&2; return 2; }

  [[ "$provider" == "auto" ]] && provider="$(route_role "$role")" || true
  [[ -n "$provider" ]] || { echo "agent-spawn: could not resolve provider for role $role" >&2; return 1; }

  local bin; bin="$(provider_command "$provider")" || return 1
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "agent-spawn: provider '$provider' command '$bin' not found on PATH —" >&2
    echo "             run scripts/install-agent-clis.sh (or pick another provider)." >&2
    return 1
  fi

  local run_id="${RUN_ID:-adhoc}"
  local out_base="${RUN_DIR:-$wt}"
  local out="$out_base/agent-${role}-${provider}.out"

  # Providers without --add-dir (e.g. Cursor agent) need the rules staged in-workspace.
  if [[ "$(provider_add_dir_supported "$provider")" == "false" ]]; then
    bash "$SPAWN_DIR/mount-rules-into-worktree.sh" "$wt" >/dev/null 2>&1 || \
      echo "agent-spawn: warning — rules mount failed for $wt" >&2
  fi

  local cmd tier effort
  effort="$(role_effort "$role" 2>/dev/null || echo medium)"
  cmd="$(compose_provider_cmd "$provider" "" "$wt" "$prompt" "$out" "$effort" "$role")" || return 1
  tier="$(provider_tier "$provider")"

  # Cost attribution + budget counter (best-effort; only when a RUN_DIR exists).
  if [[ -n "${RUN_DIR:-}" ]]; then
    ledger_append "$RUN_DIR" \
      "$(jq -nc --arg r "$role" --arg p "$provider" --arg t "$tier" --arg e "$effort" --arg rid "$run_id" \
         '{run_id:$rid, role:$r, provider:$p, tier:$t, effort:$e, event:"spawn"}')" || true
    if [[ -f "$RUN_DIR/budget.json" ]]; then
      case "$tier" in
        premium) budget_incr "$RUN_DIR" premium_calls ;;
        cheap)   budget_incr "$RUN_DIR" cheap_calls ;;
      esac
    fi
  fi

  local session="agent-${role}-${provider}-${run_id}"
  tmux new-session -d -s "$session" "bash -c $(printf '%q' "$cmd")"
  echo "agent-spawn: started $session (provider=$provider tier=$tier) -> $out"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  agent_spawn "$@"
fi

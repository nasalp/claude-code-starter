#!/usr/bin/env bash
# Per-root-task budget counters + caps. State in <run_dir>/budget.json.
# Caps come from config/agent-routing.yml budget.*, overridable by env AGENT_MAX_*.
set -uo pipefail

_budget_lib_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

_budget_routing_path() {
  if [[ -n "${AGENT_ROUTING_CONFIG:-}" ]]; then printf '%s\n' "$AGENT_ROUTING_CONFIG"; return; fi
  printf '%s\n' "$(_budget_lib_dir)/../../config/agent-routing.yml"
}

_budget_cfg() { yq -r ".budget.$1 // \"\"" "$(_budget_routing_path)"; }

# budget_init <run_dir>
budget_init() {
  local run="$1"
  command -v jq >/dev/null 2>&1 || { echo "agent-budget: jq required" >&2; return 1; }
  mkdir -p "$run"
  local max_iter max_prem max_cheap max_cost max_wall stop_unchanged
  max_iter="${AGENT_MAX_ITERATIONS:-$(_budget_cfg max_iterations)}"
  max_prem="${AGENT_MAX_PREMIUM_CALLS:-$(_budget_cfg max_premium_calls)}"
  max_cheap="${AGENT_MAX_CHEAP_CALLS:-$(_budget_cfg max_cheap_calls)}"
  max_cost="${AGENT_MAX_ESTIMATED_COST_USD:-$(_budget_cfg max_estimated_cost_usd)}"
  max_wall="${AGENT_MAX_WALL_CLOCK_SECONDS:-$(_budget_cfg max_wall_clock_seconds)}"
  stop_unchanged="${AGENT_STOP_ON_UNCHANGED_DIFF:-$(_budget_cfg stop_on_unchanged_diff)}"
  jq -n \
    --argjson mi "${max_iter:-null}" --argjson mp "${max_prem:-null}" \
    --argjson mc "${max_cheap:-null}" --argjson mcost "${max_cost:-null}" \
    --argjson mw "${max_wall:-null}" --arg su "${stop_unchanged:-true}" \
    '{counters:{iterations:0,premium_calls:0,cheap_calls:0,est_cost_usd:0,wall_clock_seconds:0},
      caps:{max_iterations:$mi,max_premium_calls:$mp,max_cheap_calls:$mc,
            max_estimated_cost_usd:$mcost,max_wall_clock_seconds:$mw,
            stop_on_unchanged_diff:($su=="true")}}' \
    > "$run/budget.json"
}

# budget_incr <run_dir> <counter> [amount=1]
budget_incr() {
  local run="$1" counter="$2" amount="${3:-1}"
  local f="$run/budget.json" tmp
  tmp="$(mktemp)"
  jq --arg c "$counter" --argjson a "$amount" \
     '.counters[$c] = ((.counters[$c] // 0) + $a)' "$f" > "$tmp" && mv "$tmp" "$f"
}

# budget_check <run_dir> -> exit non-zero naming any exceeded cap.
budget_check() {
  local run="$1"
  local f="$run/budget.json"
  # No budget file = no caps configured -> nothing to enforce (don't hard-fail).
  [[ -f "$f" ]] || return 0
  local violated
  violated="$(jq -r '
    [ {n:"max_iterations",        c:.counters.iterations,         cap:.caps.max_iterations},
      {n:"max_premium_calls",     c:.counters.premium_calls,      cap:.caps.max_premium_calls},
      {n:"max_cheap_calls",       c:.counters.cheap_calls,        cap:.caps.max_cheap_calls},
      {n:"max_estimated_cost_usd",c:.counters.est_cost_usd,       cap:.caps.max_estimated_cost_usd},
      {n:"max_wall_clock_seconds",c:.counters.wall_clock_seconds, cap:.caps.max_wall_clock_seconds} ]
    | map(select(.cap != null and .c > .cap) | .n) | .[]' "$f")"
  if [[ -n "$violated" ]]; then
    echo "budget exceeded: $(echo "$violated" | tr "\n" " ")" >&2
    return 1
  fi
  return 0
}

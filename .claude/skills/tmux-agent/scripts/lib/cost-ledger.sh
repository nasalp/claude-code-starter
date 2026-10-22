#!/usr/bin/env bash
# Append-only cost-attribution ledger: <run_dir>/cost-ledger.jsonl, one JSON row per spawn.
# Enables: cost per accepted PR, rejection rate per builder model, escalation rate,
# reviewer disagreement rate (computed downstream from these rows).
set -uo pipefail

# ledger_append <run_dir> <json>
# Validates JSON, stamps .ts when absent, appends one line.
ledger_append() {
  local run="$1" json="$2"
  command -v jq >/dev/null 2>&1 || { echo "cost-ledger: jq required" >&2; return 1; }
  echo "$json" | jq -e . >/dev/null 2>&1 || { echo "cost-ledger: malformed json" >&2; return 1; }
  mkdir -p "$run"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$json" | jq -c --arg ts "$ts" 'if has("ts") then . else .ts = $ts end' \
    >> "$run/cost-ledger.jsonl"
}

# ledger_summary <run_dir> -> human-readable rollup for the orchestration log.
ledger_summary() {
  local run="$1"
  local f="$run/cost-ledger.jsonl"
  [[ -f "$f" ]] || { echo "(no cost ledger at $f)"; return 0; }
  echo "=== cost ledger summary ($f) ==="
  echo "total calls: $(wc -l < "$f" | tr -d ' ')"
  echo "-- by provider --"
  jq -s -r 'group_by(.provider)[] | "  \(.[0].provider // "?"): \(length)"' "$f"
  echo "-- by tier --"
  jq -s -r 'group_by(.tier)[] | "  \(.[0].tier // "?"): \(length)"' "$f"
  echo "-- by verdict --"
  jq -s -r 'group_by(.verdict)[] | "  \(.[0].verdict // "none"): \(length)"' "$f"
  echo "escalations: $(jq -s '[.[] | select(.escalated == true)] | length' "$f")"
  echo "est_cost_usd total: $(jq -s '[.[].est_cost_usd // 0] | add' "$f")"
}

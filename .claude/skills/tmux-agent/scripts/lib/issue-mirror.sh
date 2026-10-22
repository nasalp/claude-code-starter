#!/usr/bin/env bash
# GitHub issue mirroring for night-loop orchestration state.
# Source from night-loop.sh; functions are testable when sourced.
set -uo pipefail

_state_write() {
  local run_dir="$1" content="$2"
  [[ -n "$run_dir" && -d "$run_dir" ]] || return 1
  local dest="$run_dir/orchestrator-state.md"
  local tmp="${dest}.tmp.$$"
  printf '%s\n' "$content" > "$tmp" || return 1
  mv "$tmp" "$dest"
}

_issue_number_from_state() {
  local run_dir="$1"
  local state="$run_dir/orchestrator-state.md"
  [[ -f "$state" ]] || return 1
  awk -F':[[:space:]]*' '
    $1 == "issue_number" { gsub(/[^0-9]/, "", $2); print $2; exit }
  ' "$state"
}

_issue_mirror() {
  local run_dir="$1" body="$2"
  local issue
  issue=$(_issue_number_from_state "$run_dir")
  [[ -n "$issue" ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  gh issue comment "$issue" --body "$body"
}

_issue_resume() {
  local issue="$1" out_run_dir="${2:-}"
  [[ "$issue" =~ ^[0-9]+$ ]] || return 2
  command -v gh >/dev/null 2>&1 || return 1

  local body run_id run_dir base
  body="$(gh issue view "$issue" --json body --jq .body 2>/dev/null || true)"
  [[ -n "$body" ]] || return 1

  run_id="$(printf '%s\n' "$body" | awk -F':[[:space:]]*' '/RUN_ID:/ { print $2; exit }' | tr -d '[:space:]')"
  [[ -n "$run_id" ]] || return 1
  [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1

  base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  run_dir="${out_run_dir:-$base/$run_id}"
  mkdir -p "$run_dir"

  local tmp="${run_dir}/orchestrator-state.md.tmp.$$"
  {
    printf 'issue_number: %s\n' "$issue"
    printf 'run_id: %s\n' "$run_id"
    printf 'run_dir: %s\n' "$run_dir"
    printf 'resumed_from_issue: true\n'
    printf '%s\n' "$body"
  } > "$tmp"
  mv "$tmp" "$run_dir/orchestrator-state.md"

  printf 'RUN_ID=%s\nRUN_DIR=%s\n' "$run_id" "$run_dir"
}

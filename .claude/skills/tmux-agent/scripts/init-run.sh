#!/usr/bin/env bash
set -uo pipefail

# Compose RUN_ID = "<slug>-<epoch>". Both args required.
_compose_run_id() {
  local slug="$1" epoch="$2"
  [[ -z "$slug" ]] && return 2
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 2
  printf '%s-%s\n' "$slug" "$epoch"
}

# Resolve RUN_DIR under TMUX_AGENT_TMPDIR (default /tmp/tmux-agent).
_run_dir_path() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_spawn_monitor() {
  local run_id="$1" run_dir="$2"
  local interval="${TMUX_AGENT_MONITOR_INTERVAL:-300}"
  local script_dir
  script_dir=$(_script_dir)
  (
    while true; do
      bash "$script_dir/audit-cycle.sh" "$run_id"
      sleep "$interval"
    done
  ) </dev/null >> "$run_dir/monitor.out" 2>&1 &
  printf '%s\n' "$!" > "$run_dir/.monitor.pid"
}

# CLI: init_run <slug> [epoch]
init_run_main() {
  local slug="${1:-}"
  local epoch="${2:-$(date +%s)}"
  if [[ -z "$slug" ]]; then
    echo "usage: init-run.sh <feature-slug> [epoch]" >&2
    return 2
  fi
  local run_id run_dir
  run_id=$(_compose_run_id "$slug" "$epoch") || return 2
  run_dir=$(_run_dir_path "$run_id")
  mkdir -p "$run_dir"
  _spawn_monitor "$run_id" "$run_dir"
  printf 'RUN_ID=%s\nRUN_DIR=%s\n' "$run_id" "$run_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  init_run_main "$@"
fi

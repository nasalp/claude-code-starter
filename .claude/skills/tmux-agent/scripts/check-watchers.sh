#!/usr/bin/env bash
set -uo pipefail

# 0 (true) if a tmux session of the given name exists.
_session_alive() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null
}

# Echo the first PID matching `watcher-loop.sh.*<tag>`; empty if none.
_loop_pid() {
  local tag="$1"
  pgrep -f "watcher-loop.sh.*$tag" 2>/dev/null | head -1 || true
}

# Extract a single-line diagnostic summary from the latest verdict for a watcher.
# Args: TAG VERDICT_DIR
# Notes (review fixes):
#  - BLIND check restricted to the diagnostic header (first 15 lines) so audit
#    bodies discussing "blind spots" don't trigger false positives.
#  - Does NOT prepend tag — caller (check_watchers_main) owns the tag prefix
#    to avoid duplicate `OK scroll … scroll OK …` lines.
_extract_diagnostic_line() {
  local tag="$1" verdict_dir="$2"
  local latest
  latest=$(ls -t "$verdict_dir"/pass-*.md 2>/dev/null | head -1)
  if [[ -z "$latest" ]]; then
    echo "verdicts=0 (no passes yet)"
    return 0
  fi
  local header sha unchanged pass blind learnings
  header=$(head -15 "$latest")
  sha=$(echo "$header" | grep -m1 "^sha_resolved:" | awk '{print $2}')
  pass=$(echo "$header" | grep -m1 "^pass_number:" | awk '{print $2}')
  unchanged=$(echo "$header" | grep -m1 "^sha_unchanged_since_pass:" | awk '{print $2}')
  blind=$(echo "$header" | grep -c "^BLIND")
  learnings=$(echo "$header" | grep -m1 "^learnings_file:" | awk '{print $2}')
  if [[ "$blind" -gt 0 || "$sha" == "NONE" ]]; then
    echo "BLIND pass=$pass unchanged=$unchanged ref-unresolved"
  elif [[ -n "$learnings" ]]; then
    echo "OK sha=${sha:0:8} pass=$pass unchanged=$unchanged learnings=$learnings"
  else
    echo "OK sha=${sha:0:8} pass=$pass unchanged=$unchanged"
  fi
}

# CLI: check-watchers [--diagnostic --verdicts-dir DIR] <run-id> <tag1> [tag2 ...]
check_watchers_main() {
  local diagnostic_mode=0 verdicts_root=""
  while [[ "${1:-}" =~ ^-- ]]; do
    case "$1" in
      --diagnostic)    diagnostic_mode=1; shift ;;
      --verdicts-dir)  verdicts_root="$2"; shift 2 ;;
      *)               echo "unknown flag: $1" >&2; return 2 ;;
    esac
  done
  if (( $# < 2 )); then
    echo "usage: check-watchers.sh [--diagnostic --verdicts-dir DIR] RUN_ID TAG [TAG …]" >&2
    return 2
  fi
  local run_id="$1"; shift
  local rc=0
  local tag
  for tag in "$@"; do
    local session
    session="watch-${tag}-${run_id}"
    if ! _session_alive "$session"; then
      echo "DEFECT: watcher $tag session $session missing"
      rc=1
      continue
    fi
    local pid
    pid=$(_loop_pid "$tag")
    if [[ -z "$pid" ]]; then
      echo "DEFECT: watcher $tag loop PID missing"
      rc=1
      continue
    fi
    if (( diagnostic_mode == 1 )); then
      local dir
      if [[ -n "$verdicts_root" ]]; then
        dir="${verdicts_root}/${tag}-verdicts"
        [[ -d "$dir" ]] || dir="${verdicts_root}/verdicts-${tag}"
      else
        dir="/tmp/tmux-agent/${run_id}/verdicts-${tag}"
      fi
      local diag
      diag=$(_extract_diagnostic_line "$tag" "$dir")
      echo "OK $tag session=$session pid=$pid $diag"
    else
      echo "OK $tag session=$session pid=$pid"
    fi
  done
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_watchers_main "$@"
fi

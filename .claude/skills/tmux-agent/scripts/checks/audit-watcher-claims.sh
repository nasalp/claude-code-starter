#!/usr/bin/env bash
set -uo pipefail

_usage() {
  echo "usage: audit-watcher-claims.sh [--repo PATH] [--run-dir PATH|RUN_ID]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_run_dir_from_id() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_has_approve_verdict() {
  local run_dir="$1"
  [[ -d "$run_dir" ]] || return 1
  find "$run_dir" -type f -path '*/verdicts-*/*.md' -print | while IFS= read -r verdict; do
    if grep -Eq '\bAPPROVE\b' "$verdict"; then
      printf 'yes\n'
      break
    fi
  done | grep -q '^yes$'
}

_proof_commands() {
  local checklist="$1"
  [[ -f "$checklist" ]] || return 0
  awk '
    /PROOF:[[:space:]]*/ {
      line = $0
      sub(/^.*PROOF:[[:space:]]*/, "", line)
      if (line != "") print line
    }
  ' "$checklist"
}

audit_watcher_claims_main() {
  local repo="" run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo="$2"
        shift 2
        ;;
      --run-dir)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        run_dir="$2"
        shift 2
        ;;
      --proof-dir)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        shift 2
        ;;
      --help|-h)
        _usage
        return 0
        ;;
      --*)
        echo "unknown flag: $1" >&2
        return 2
        ;;
      *)
        if [[ -z "$run_dir" ]]; then
          run_dir=$(_run_dir_from_id "$1")
          shift
        else
          _usage
          return 2
        fi
        ;;
    esac
  done

  if [[ -z "$repo" ]]; then
    repo=$(_git_toplevel)
  fi
  if [[ -z "$repo" || ! -d "$repo" ]]; then
    echo "ERROR: repo not found" >&2
    return 2
  fi
  if [[ -z "$run_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$run_dir" ]]; then
    echo "ERROR: run dir not found: $run_dir" >&2
    return 2
  fi

  _has_approve_verdict "$run_dir" || return 0

  local checklist="$run_dir/checklist.md"
  local command
  while IFS= read -r command; do
    [[ -n "$command" ]] || continue
    if ! ( cd "$repo" && bash -c "$command" ); then
      echo "WARN watcher-stale: approved proof command failed: $command"
    fi
  done < <(_proof_commands "$checklist")

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  audit_watcher_claims_main "$@"
fi

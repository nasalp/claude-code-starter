#!/usr/bin/env bash
set -uo pipefail

_usage() {
  echo "usage: teardown-run.sh [--repo PATH] [--archive-root PATH] [--pr N] RUN_ID" >&2
}

_run_dir_path() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_archive_root() {
  printf '%s/.cache/tmux-agent-archive\n' "$HOME"
}

_kill_monitor() {
  local run_dir="$1"
  local pid_file="$run_dir/.monitor.pid"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid=$(cat "$pid_file")
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
  fi
}

_pr_number() {
  local run_dir="$1" explicit_pr="$2"
  if [[ -n "$explicit_pr" ]]; then
    printf '%s\n' "$explicit_pr"
    return 0
  fi
  if [[ -f "$run_dir/pr-number" ]]; then
    head -1 "$run_dir/pr-number"
  fi
}

_prune_proof_tags() {
  local pr="$1"
  [[ "$pr" =~ ^[0-9]+$ ]] || return 0
  command -v gh >/dev/null 2>&1 || return 0

  local keep_seen=0 line tag
  while IFS= read -r line; do
    tag="${line%%[[:space:]]*}"
    [[ "$tag" == proof-pr"$pr"-cycle* ]] || continue
    if (( keep_seen == 0 )); then
      keep_seen=1
      continue
    fi
    gh release delete "$tag" -y >/dev/null 2>&1
  done < <(gh release list --limit 100 2>/dev/null)
}

_remove_worktrees() {
  local repo="$1" run_dir="$2"
  [[ -n "$repo" && -d "$repo" ]] || return 0
  local list="$run_dir/worktrees.txt"
  [[ -f "$list" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$repo" worktree remove --force "$path" >/dev/null 2>&1
  done < "$list"
}

_archive_run_dir() {
  local run_id="$1" run_dir="$2" archive_root="$3"
  [[ -d "$run_dir" ]] || return 0
  local dest
  dest="$archive_root/$run_id-$(date +%s)"
  mkdir -p "$dest" || return 1
  cp -R "$run_dir"/. "$dest"/ || return 1
  rm -rf "$run_dir"
}

teardown_run_main() {
  local repo="" archive_root="" pr="" run_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo="$2"
        shift 2
        ;;
      --archive-root)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        archive_root="$2"
        shift 2
        ;;
      --pr)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        pr="$2"
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
        if [[ -n "$run_id" ]]; then
          _usage
          return 2
        fi
        run_id="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$run_id" ]]; then
    _usage
    return 2
  fi
  [[ -n "$archive_root" ]] || archive_root=$(_archive_root)

  local run_dir
  run_dir=$(_run_dir_path "$run_id")
  if [[ ! -d "$run_dir" ]]; then
    echo "ERROR: RUN_DIR missing: $run_dir" >&2
    return 2
  fi

  _kill_monitor "$run_dir"
  pr=$(_pr_number "$run_dir" "$pr")
  _prune_proof_tags "$pr"
  _remove_worktrees "$repo" "$run_dir"
  _archive_run_dir "$run_id" "$run_dir" "$archive_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  teardown_run_main "$@"
fi

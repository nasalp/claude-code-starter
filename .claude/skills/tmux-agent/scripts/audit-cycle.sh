#!/usr/bin/env bash
set -uo pipefail

AUDIT_TMPDIR=""

_cleanup_tmpdir() {
  [[ -n "$AUDIT_TMPDIR" ]] && rm -rf "$AUDIT_TMPDIR"
}

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_usage() {
  echo "usage: audit-cycle.sh [--repo PATH] [--proof-dir PATH] RUN_ID" >&2
}

_valid_run_id() {
  local run_id="$1"
  [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

_run_dir_path() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_mktemp_dir() {
  local parent="${TMPDIR:-/tmp}"
  mkdir -p "$parent" || return 1
  mktemp -d "${parent%/}/audit-cycle.XXXXXX"
}

_repo_from_state() {
  local run_dir="$1"
  local state="$run_dir/orchestrator-state.md"
  [[ -f "$state" ]] || return 1
  awk -F':[[:space:]]*' '
    $1 == "repo" || $1 == "REPO" || $1 == "repository" || $1 == "repo_path" {
      print $2
      exit
    }
  ' "$state"
}

_resolve_repo() {
  local explicit_repo="$1" run_dir="$2"
  if [[ -n "$explicit_repo" ]]; then
    printf '%s\n' "$explicit_repo"
    return 0
  fi

  local state_repo
  state_repo=$(_repo_from_state "$run_dir")
  if [[ -n "$state_repo" ]]; then
    printf '%s\n' "$state_repo"
    return 0
  fi

  git rev-parse --show-toplevel 2>/dev/null
}

_default_check_names() {
  cat <<'EOF'
verify-proof-artifacts.sh
verify-screenshot-not-blank.sh
verify-red-then-green.sh
verify-mocks-vs-e2e.sh
verify-pr-owned-mutation-score.sh
audit-watcher-claims.sh
verify-test-asserts-behavior.sh
EOF
}

_list_checks() {
  local script_dir="$1"
  local checks_dir="${AUDIT_CHECKS_DIR:-$script_dir/checks}"

  if [[ -n "${AUDIT_CHECKS_DIR:-}" ]]; then
    [[ -d "$checks_dir" ]] || return 0
    local f
    while IFS= read -r f; do
      [[ -n "$f" && -x "$f" ]] && printf '%s\n' "$f"
    done < <(find "$checks_dir" -maxdepth 1 -type f -name '*.sh' | sort)
    return 0
  fi

  local name path
  while IFS= read -r name; do
    path="$checks_dir/$name"
    [[ -x "$path" ]] && printf '%s\n' "$path"
  done < <(_default_check_names)
}

_warn_category() {
  awk '
    /^WARN [A-Za-z0-9_-]+: / {
      sub(/^WARN /, "")
      sub(/:.*/, "")
      print
      exit
    }
  ' <<<"$1"
}

_append_deduped_warns() {
  local input="$1" categories_file="$2" warnings_file="$3"
  local line category
  while IFS= read -r line; do
    [[ "$line" =~ ^WARN[[:space:]][A-Za-z0-9_-]+:[[:space:]] ]] || continue
    category=$(_warn_category "$line")
    [[ -n "$category" ]] || continue
    if grep -Fqx "$category" "$categories_file" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$category" >> "$categories_file"
    printf '%s\n' "$line" >> "$warnings_file"
  done <<<"$input"
}

_run_child_check() {
  local check="$1" repo="$2" proof_dir="$3" run_dir="$4" output_file="$5" err_file="$6"
  "$check" --repo "$repo" --proof-dir "$proof_dir" --run-dir "$run_dir" > "$output_file" 2> "$err_file"
}

audit_cycle_main() {
  local repo_arg="" proof_dir_arg="" run_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo_arg="$2"
        shift 2
        ;;
      --proof-dir)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        proof_dir_arg="$2"
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
  if ! _valid_run_id "$run_id"; then
    echo "ERROR: invalid RUN_ID: $run_id" >&2
    return 2
  fi

  local run_dir
  run_dir=$(_run_dir_path "$run_id")
  if [[ ! -d "$run_dir" ]]; then
    echo "ERROR: RUN_DIR missing: $run_dir" >&2
    return 2
  fi

  local repo
  repo=$(_resolve_repo "$repo_arg" "$run_dir")
  if [[ -z "$repo" || ! -d "$repo" ]]; then
    echo "ERROR: repo not found for RUN_ID $run_id" >&2
    return 2
  fi

  local proof_dir="${proof_dir_arg:-docs/proof}"
  local tmp
  tmp=$(_mktemp_dir) || {
    echo "ERROR: failed to create temporary audit directory" >&2
    return 1
  }
  AUDIT_TMPDIR="$tmp"
  trap _cleanup_tmpdir EXIT

  local warnings_file="$tmp/warnings.txt"
  local categories_file="$tmp/categories.txt"
  : > "$warnings_file"
  : > "$categories_file"

  local script_dir log_file
  script_dir=$(_script_dir)
  log_file="$run_dir/audit-cycle-$(date -u +%s).log"

  local rc=0 check child_out child_err output
  while IFS= read -r check; do
    [[ -n "$check" ]] || continue
    child_out="$tmp/$(basename "$check").out"
    child_err="$tmp/$(basename "$check").err"
    if ! _run_child_check "$check" "$repo" "$proof_dir" "$run_dir" "$child_out" "$child_err"; then
      {
        echo "ERROR: child check failed: $check"
        sed 's/^/stderr: /' "$child_err"
      } >> "$log_file"
      rc=1
      continue
    fi
    output=$(cat "$child_out")
    _append_deduped_warns "$output" "$categories_file" "$warnings_file"
  done < <(_list_checks "$script_dir")

  cat "$warnings_file" >> "$log_file"
  cat "$warnings_file"
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  audit_cycle_main "$@"
fi

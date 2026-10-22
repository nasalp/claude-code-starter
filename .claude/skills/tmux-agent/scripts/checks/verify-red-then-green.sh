#!/usr/bin/env bash
set -uo pipefail

_usage() {
  echo "usage: verify-red-then-green.sh [--repo PATH] [--base REF]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_is_test_file() {
  local path="$1"
  case "$path" in
    *src/test/*|*test/*|*tests/*|*__tests__/*|*Test.java|*Tests.java|*IT.java|*_test.go|*.test.*|*.spec.*)
      return 0
      ;;
  esac
  return 1
}

_is_prod_file() {
  local path="$1"
  _is_test_file "$path" && return 1
  case "$path" in
    *.java|*.kt|*.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rb|*.php)
      return 0
      ;;
  esac
  return 1
}

_stem() {
  local path="$1"
  local base="${path##*/}"
  base="${base%.*}"
  printf '%s\n' "$base"
}

_commit_changed_files() {
  local commit="$1"
  git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null
}

_parent_has_related_test() {
  local parent_commit="$1" fix_commit="$2"
  local test_files prod_files test_file prod_file stem
  test_files=$(_commit_changed_files "$parent_commit" | while IFS= read -r path; do
    _is_test_file "$path" && printf '%s\n' "$path"
  done)
  [[ -n "$test_files" ]] || return 1

  prod_files=$(_commit_changed_files "$fix_commit" | while IFS= read -r path; do
    _is_prod_file "$path" && printf '%s\n' "$path"
  done)
  [[ -n "$prod_files" ]] || return 1

  while IFS= read -r prod_file; do
    [[ -n "$prod_file" ]] || continue
    stem=$(_stem "$prod_file")
    while IFS= read -r test_file; do
      [[ -n "$test_file" ]] || continue
      if [[ "$test_file" == *"$stem"* ]]; then
        return 0
      fi
      if git show "$parent_commit:$test_file" 2>/dev/null | grep -Fq "$stem"; then
        return 0
      fi
    done <<<"$test_files"
  done <<<"$prod_files"

  return 1
}

verify_red_then_green_main() {
  local repo="" base="origin/main"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo="$2"
        shift 2
        ;;
      --base)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        base="$2"
        shift 2
        ;;
      --proof-dir|--run-dir)
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
        _usage
        return 2
        ;;
    esac
  done

  if [[ -z "$repo" ]]; then
    repo=$(_git_toplevel)
  fi
  if [[ -z "$repo" || ! -d "$repo/.git" ]]; then
    echo "ERROR: git repo not found" >&2
    return 2
  fi

  git -C "$repo" rev-parse --verify "$base" >/dev/null 2>&1 || {
    echo "ERROR: base ref not found: $base" >&2
    return 2
  }

  local commits
  commits=$(git -C "$repo" log --format='%H' --grep='^fix' "$base..HEAD" 2>/dev/null)
  [[ -n "$commits" ]] || return 0

  local commit parent subject warned=0
  while IFS= read -r commit; do
    [[ -n "$commit" ]] || continue
    parent=$(git -C "$repo" rev-parse "${commit}^" 2>/dev/null)
    if [[ -z "$parent" ]]; then
      continue
    fi
    if ! ( cd "$repo" && _parent_has_related_test "$parent" "$commit" ); then
      subject=$(git -C "$repo" log -1 --format='%s' "$commit")
      echo "WARN no-red-commit: $subject has no preceding related RED test commit"
      warned=1
    fi
  done <<<"$commits"

  : "$warned"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_red_then_green_main "$@"
fi

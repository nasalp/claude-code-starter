#!/usr/bin/env bash
set -uo pipefail

PR_OWNED_COMMITS_FILE=""

_cleanup_commits_file() {
  [[ -n "$PR_OWNED_COMMITS_FILE" ]] && rm -f "$PR_OWNED_COMMITS_FILE"
}

_usage() {
  echo "usage: verify-pr-owned-mutation-score.sh [--repo PATH] [--base REF] [--report PATH] [--threshold N]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_report_files() {
  local report="$1"
  if [[ -f "$report" ]]; then
    printf '%s\n' "$report"
    return 0
  fi
  [[ -d "$report" ]] || return 0
  find "$report" -type f \( -name '*.html' -o -name '*.json' -o -name '*.txt' -o -name '*.csv' \) | sort
}

_extract_records_from_file() {
  local report_file="$1"
  awk '
    function attr(line, key,   pattern, start, value) {
      pattern = key "=\"[^\"]+\""
      if (match(line, pattern)) {
        value = substr(line, RSTART, RLENGTH)
        sub("^" key "=\"", "", value)
        sub("\"$", "", value)
        return value
      }
      return ""
    }
    {
      status = ""
      fileline = ""

      if (match($0, /(KILLED|SURVIVED|NO_COVERAGE|NO-COVERAGE)/)) {
        status = substr($0, RSTART, RLENGTH)
      }
      if (match($0, /[-A-Za-z0-9_.\/]+\.(java|kt|ts|tsx|js|jsx|py|go|rb|php):[0-9]+/)) {
        fileline = substr($0, RSTART, RLENGTH)
      }

      attr_status = attr($0, "data-status")
      attr_file = attr($0, "data-file")
      attr_line = attr($0, "data-line")
      if (attr_status != "") status = attr_status
      if (attr_file != "" && attr_line != "") fileline = attr_file ":" attr_line

      if (status != "" && fileline != "") {
        gsub(/NO-COVERAGE/, "NO_COVERAGE", status)
        print status " " fileline
      }
    }
  ' "$report_file"
}

_extract_records() {
  local report="$1" file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    _extract_records_from_file "$file"
  done < <(_report_files "$report")
}

_is_pr_owned_commit() {
  local commit="$1" pr_commits_file="$2"
  grep -Fqx "$commit" "$pr_commits_file" 2>/dev/null
}

_resolve_mutation_file() {
  local repo="$1" file="$2"
  if [[ -f "$repo/$file" ]]; then
    printf '%s\n' "$file"
    return 0
  fi
  local basename="${file##*/}"
  local match
  match=$(git -C "$repo" ls-files "*$basename" 2>/dev/null | head -n 1)
  [[ -n "$match" ]] || return 1
  printf '%s\n' "$match"
}

_blame_commit_for_line() {
  local repo="$1" file="$2" line="$3"
  local real_file
  real_file=$(_resolve_mutation_file "$repo" "$file") || return 1
  git -C "$repo" blame -L "$line","$line" --porcelain -- "$real_file" 2>/dev/null | awk 'NR == 1 { print $1; exit }'
}

verify_pr_owned_mutation_main() {
  local repo="" base="origin/main" report="" threshold=80
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
      --report)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        report="$2"
        shift 2
        ;;
      --threshold)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        threshold="$2"
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
  if [[ -z "$report" ]]; then
    if [[ -d "$repo/target/pit-reports" ]]; then
      report="$repo/target/pit-reports"
    elif [[ -d "$repo/reports/mutation" ]]; then
      report="$repo/reports/mutation"
    else
      return 0
    fi
  fi
  if [[ ! -e "$report" ]]; then
    return 0
  fi
  [[ "$threshold" =~ ^[0-9]+$ ]] || {
    echo "ERROR: threshold must be numeric" >&2
    return 2
  }

  local pr_commits_file
  pr_commits_file=$(mktemp "${TMPDIR:-/tmp}/pr-owned-commits.XXXXXX") || return 1
  PR_OWNED_COMMITS_FILE="$pr_commits_file"
  trap _cleanup_commits_file EXIT
  git -C "$repo" rev-list "$base..HEAD" > "$pr_commits_file" 2>/dev/null || {
    echo "ERROR: cannot resolve base range: $base..HEAD" >&2
    return 2
  }

  local killed=0 survived=0 record status fileline file line commit
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    status="${record%% *}"
    fileline="${record#* }"
    file="${fileline%:*}"
    line="${fileline##*:}"
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    commit=$(_blame_commit_for_line "$repo" "$file" "$line")
    [[ -n "$commit" ]] || continue
    if ! _is_pr_owned_commit "$commit" "$pr_commits_file"; then
      continue
    fi
    case "$status" in
      KILLED) killed=$((killed + 1)) ;;
      *) survived=$((survived + 1)) ;;
    esac
  done < <(_extract_records "$report")

  local total score
  total=$((killed + survived))
  (( total > 0 )) || return 0
  score=$((killed * 100 / total))
  if (( score < threshold )); then
    echo "WARN pr-owned-mutation: PR-owned mutation score ${score}% (${killed}/${total}) below ${threshold}%"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_pr_owned_mutation_main "$@"
fi

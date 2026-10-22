#!/usr/bin/env bash
set -uo pipefail

# Enumerate gemini-code-assist findings on a PR. Used by Phase 6's hard
# pre-merge gate to make sure every finding is addressed before merge.
# See ../docs/phase-6-ship-deploy.md §6.0.
#
# Output (one finding per line, tab-separated):
#   <severity>\t<kind>\t<id>\t<location>\t<summary>
#
# severity ∈ {HIGH, MEDIUM, LOW, UNKNOWN}
# kind ∈ {INLINE, PR}
# location: "<path>:<line>" for INLINE, "PR" for PR-level body comments
# summary: first 120 chars of the body, single-line (newlines → space)
#
# Exit codes:
#   0 — success (findings printed, or clean)
#   2 — usage / arg error / gh missing
#
# WHY exit 0 on clean: callers under `set -eo pipefail` would crash on a
# non-zero exit. Use `wc -l` on the output to count findings.

# Parse the gemini severity SVG marker from a body string.
# Bodies look like: `![high](https://www.gstatic.com/codereviewagent/high-priority.svg)\n\n...`
_parse_severity() {
  local body="$1"
  case "$body" in
    *"![high]"*|*"high-priority.svg"*)     echo "HIGH" ;;
    *"![medium]"*|*"medium-priority.svg"*) echo "MEDIUM" ;;
    *"![low]"*|*"low-priority.svg"*)       echo "LOW" ;;
    *)                                      echo "UNKNOWN" ;;
  esac
}

# Trim body to a single-line summary <= 120 chars.
_summarize() {
  local body="$1"
  # Strip the leading severity marker line so the summary shows real content.
  local stripped
  stripped=$(printf '%s' "$body" | sed -E 's/!\[(high|medium|low)\]\([^)]+\)//')
  # Collapse all whitespace to single spaces, then truncate.
  local one_line
  one_line=$(printf '%s' "$stripped" | tr '\n\r\t' '   ' | sed -E 's/  +/ /g; s/^ +//; s/ +$//')
  printf '%s' "${one_line:0:120}"
}

# Emit one TSV line. Args: severity kind id location summary
_emit_finding() {
  local sev="$1" kind="$2" id="$3" loc="$4" summary="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' "$sev" "$kind" "$id" "$loc" "$summary"
}

# Fetch inline review comments (path + line) via gh api. Returns JSON array.
_fetch_inline() {
  local repo="$1" pr="$2"
  gh api "repos/${repo}/pulls/${pr}/comments" --paginate 2>/dev/null
}

# Fetch PR-level issue comments via gh api. Returns JSON array.
_fetch_pr_level() {
  local repo="$1" pr="$2"
  gh api "repos/${repo}/issues/${pr}/comments" --paginate 2>/dev/null
}

# Walk a comments-JSON array (from either endpoint), emit one TSV line per
# gemini-code-assist comment. Args: JSON KIND
#
# We round-trip through `jq -c` (compact JSON per line) instead of @tsv +
# `read -r` because consecutive tab delimiters collapse under default bash
# IFS rules (whitespace IFS merges runs), losing the empty `path` field
# that PR-level comments produce.
_walk_comments() {
  local json="$1" kind="$2"
  [[ -z "$json" || "$json" == "null" ]] && return 0
  printf '%s' "$json" \
    | jq -c '.[]
        | select(.user.login == "gemini-code-assist[bot]")
        | {id, path: (.path // ""), line: (.line // 0), body}' 2>/dev/null \
    | while IFS= read -r line_json; do
        [[ -z "$line_json" ]] && continue
        local id path line body sev loc summary
        id=$(printf '%s' "$line_json" | jq -r '.id')
        path=$(printf '%s' "$line_json" | jq -r '.path')
        line=$(printf '%s' "$line_json" | jq -r '.line')
        body=$(printf '%s' "$line_json" | jq -r '.body')
        sev=$(_parse_severity "$body")
        if [[ "$kind" == "INLINE" && -n "$path" ]]; then
          loc="${path}:${line}"
        else
          loc="PR"
        fi
        summary=$(_summarize "$body")
        _emit_finding "$sev" "$kind" "$id" "$loc" "$summary"
      done
}

# Main: list-gemini-findings.sh <PR#> [--repo owner/repo]
list_gemini_main() {
  local pr="" repo=""
  while (( $# > 0 )); do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --repo=*) repo="${1#--repo=}"; shift ;;
      -h|--help)
        echo "usage: list-gemini-findings.sh <PR-number> [--repo owner/repo]" >&2
        return 2
        ;;
      *)
        if [[ -z "$pr" ]]; then
          pr="$1"
        else
          echo "unexpected arg: $1" >&2
          return 2
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr" ]]; then
    echo "usage: list-gemini-findings.sh <PR-number> [--repo owner/repo]" >&2
    return 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not on PATH" >&2
    return 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not on PATH" >&2
    return 2
  fi

  if [[ -z "$repo" ]]; then
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
    if [[ -z "$repo" ]]; then
      echo "ERROR: could not infer repo; pass --repo owner/repo" >&2
      return 2
    fi
  fi

  local inline_json pr_json
  inline_json=$(_fetch_inline "$repo" "$pr")
  pr_json=$(_fetch_pr_level "$repo" "$pr")

  local out
  out=$(
    _walk_comments "$inline_json" "INLINE"
    _walk_comments "$pr_json" "PR"
  )

  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  list_gemini_main "$@"
fi

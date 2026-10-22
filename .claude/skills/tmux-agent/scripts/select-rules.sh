#!/usr/bin/env bash
# select-rules.sh --role <role> [--severity csv] [--ext .java]
# Print rule files (one path per line, sorted) whose frontmatter matches the role
# and severity filter. Scans .claude/rules/ (always-on) and .claude/rules-corpus/.
set -uo pipefail

role="" severity_filter="" ext=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)     role="$2"; shift 2;;
    --severity) severity_filter="$2"; shift 2;;
    --ext)      ext="$2"; shift 2;;
    *) echo "select-rules: unknown arg $1" >&2; exit 2;;
  esac
done
[[ -n "$role" ]] || { echo "usage: select-rules.sh --role <role> [--severity csv] [--ext .ext]" >&2; exit 2; }

command -v yq >/dev/null 2>&1 || { echo "select-rules: 'yq' not found on PATH — install yq v4." >&2; exit 2; }

rules_dir="${SELECT_RULES_DIR:-$HOME/.claude/rules}"
[[ -d "$rules_dir" ]] || { echo "select-rules: rules dir not found: $rules_dir" >&2; exit 2; }

corpus_dir="${SELECT_RULES_CORPUS_DIR:-}"
if [[ -z "$corpus_dir" ]]; then
  candidate="$(dirname "$rules_dir")/rules-corpus"
  if [[ -d "$candidate" ]]; then
    corpus_dir="$candidate"
  elif [[ -d "$HOME/.claude/rules-corpus" ]]; then
    corpus_dir="$HOME/.claude/rules-corpus"
  fi
fi

full_mode=false
[[ "${RULES_LOAD_MODE:-scoped}" == "full" ]] && full_mode=true

_fm() {
  local f="$1" roles sev always_on
  roles="$(yq --front-matter=extract -r '(.roles // []) | join(",")' "$f" 2>/dev/null)" || roles=""
  sev="$(yq   --front-matter=extract -r '.severity // ""'           "$f" 2>/dev/null)" || sev=""
  always_on="$(yq --front-matter=extract -r '.always_on // false' "$f" 2>/dev/null)" || always_on="false"
  printf 'ROLES=%s\nSEV=%s\nALWAYS_ON=%s\n' "$roles" "$sev" "$always_on"
}

_csv_has() { case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }

_matches() {
  local f="$1"
  local base always_on roles_csv sev meta
  base="$(basename "$f")"
  [[ "$base" == "INDEX.md" || "$base" == "README.md" ]] && return 1

  meta="$(_fm "$f")"
  roles_csv="$(printf '%s\n' "$meta" | sed -n 's/^ROLES=//p')"
  sev="$(printf '%s\n' "$meta" | sed -n 's/^SEV=//p')"
  always_on="$(printf '%s\n' "$meta" | sed -n 's/^ALWAYS_ON=//p')"
  [[ -z "$sev" ]] && sev="normal"

  if [[ -n "$ext" && "$always_on" != "true" && "$full_mode" != "true" && "$f" != *"$ext"* ]]; then
    return 1
  fi

  if [[ "$always_on" == "true" || "$full_mode" == "true" ]]; then
    :
  elif [[ -n "$roles_csv" ]]; then
    _csv_has "$roles_csv" "$role" || return 1
  fi

  if [[ -n "$severity_filter" ]]; then _csv_has "$severity_filter" "$sev" || return 1; fi
  return 0
}

_collect() {
  local root="$1" maxdepth="${2:-}"
  [[ -d "$root" ]] || return 0
  if [[ -n "$maxdepth" ]]; then
    find "$root" -maxdepth "$maxdepth" -type f -name '*.md' 2>/dev/null | sort
  else
    find "$root" -type f -name '*.md' 2>/dev/null | sort
  fi
}

selected=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if _matches "$f"; then selected+=("$f"); fi
done < <(_collect "$rules_dir" 1; _collect "$corpus_dir")

printf '%s\n' "${selected[@]}" | awk '!seen[$0]++' | sort

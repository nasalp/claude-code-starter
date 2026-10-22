#!/usr/bin/env bash
set -uo pipefail

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# shellcheck source=lib/find-sources.sh
source "$(_script_dir)/lib/find-sources.sh"

_usage() {
  echo "usage: verify-mocks-vs-e2e.sh [--repo PATH]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_is_integration_file() {
  local path="$1"
  case "$path" in
    *IT.java|*IT.kt|*.integration.test.*|*.integration.spec.*|*integration_test.py|*IntegrationTest.java|*IntegrationSpec.kt)
      return 0
      ;;
  esac
  return 1
}

_read_config_patterns() {
  local config="$1"
  [[ -f "$config" ]] || return 0
  awk '
    /^[[:space:]]*mock_patterns:[[:space:]]*$/ { in_patterns=1; next }
    in_patterns && /^[[:space:]]*-[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      gsub(/^["'\'']|["'\'']$/, "", line)
      if (line != "") print line
      next
    }
    in_patterns && /^[^[:space:]]/ { in_patterns=0 }
  ' "$config"
}

_all_patterns() {
  local repo="$1"
  _read_config_patterns "$(_script_dir)/checks-config.yml"
  _read_config_patterns "$repo/checks-config.yml"
}

_scan_file_for_patterns() {
  local file="$1"
  shift
  local pattern
  for pattern in "$@"; do
    [[ -n "$pattern" ]] || continue
    if grep -Fq "$pattern" "$file"; then
      echo "WARN mock-on-it: ${file} uses ${pattern} in integration test"
      return 0
    fi
  done
}

verify_mocks_main() {
  local repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo="$2"
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
  if [[ -z "$repo" || ! -d "$repo" ]]; then
    echo "ERROR: repo not found" >&2
    return 2
  fi

  local patterns=()
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && patterns+=("$pattern")
  done < <(_all_patterns "$repo" | awk '!seen[$0]++')
  [[ ${#patterns[@]} -gt 0 ]] || return 0

  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    _is_integration_file "$file" || continue
    _scan_file_for_patterns "$file" "${patterns[@]}"
  done < <(_find_source_files "$repo" \
    -name '*.java' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \
    -o -name '*.js' -o -name '*.jsx' -o -name '*.py')

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_mocks_main "$@"
fi

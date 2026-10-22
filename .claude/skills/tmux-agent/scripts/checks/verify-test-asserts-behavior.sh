#!/usr/bin/env bash
set -uo pipefail

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# shellcheck source=lib/find-sources.sh
source "$(_script_dir)/lib/find-sources.sh"

_usage() {
  echo "usage: verify-test-asserts-behavior.sh [--repo PATH]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_is_test_file() {
  local file="$1"
  case "$file" in
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*Test.java|*Tests.java|*IT.java|*_test.py|*test_*.py|*_test.go)
      return 0
      ;;
  esac
  return 1
}

_warn_source_regex_test() {
  local file="$1"
  if grep -Fq 'fs.readFileSync' "$file" && grep -Eq 'RegExp|\.test\(|\.match\(|\.includes\(' "$file"; then
    echo "WARN regex-over-source: $file reads source text and asserts regex/string shape"
    return 0
  fi
  return 1
}

_warn_source_literal_assertion() {
  local file="$1"
  if grep -Fq 'fs.readFileSync' "$file" \
    && grep -Eq 'expect\([^)]*\)\.(toContain|toMatch|toEqual)\(' "$file"; then
    echo "WARN regex-over-source: $file asserts source literals via expect().toContain/toMatch"
    return 0
  fi
  return 1
}

_warn_junit_without_assertion() {
  local file="$1"
  [[ "$file" == *.java ]] || return 1
  grep -Fq '@Test' "$file" || return 1
  if grep -Eq 'assertThat|assertEquals|assertTrue|assertFalse|assertThrows|verify\(|then\(|expectThrows' "$file"; then
    return 1
  fi
  echo "WARN regex-over-source: $file has @Test method(s) with no behavioral assertion"
  return 0
}

verify_test_asserts_behavior_main() {
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

  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    _is_test_file "$file" || continue
    _warn_source_regex_test "$file"
    _warn_source_literal_assertion "$file"
    _warn_junit_without_assertion "$file"
  done < <(_find_source_files "$repo" \
    -name '*.java' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \
    -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go')

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_test_asserts_behavior_main "$@"
fi

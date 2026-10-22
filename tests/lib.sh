#!/usr/bin/env bash
# Tiny assertion helpers shared by tests/test-*.sh. Source, don't execute.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
PASSES=0

pass() { PASSES=$((PASSES + 1)); echo "  ok    $*"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL  $*"; }

# assert_eq EXPECTED ACTUAL MESSAGE
assert_eq() {
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

# assert_contains HAYSTACK NEEDLE MESSAGE
assert_contains() {
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

# make_tmp — portable temp dir (works under macOS sandboxes too).
make_tmp() {
    local base="${TMPDIR:-/tmp}"
    local dir="$base/ai-rules-test.$$.$RANDOM"
    mkdir -p "$dir"
    echo "$dir"
}

finish() {
    echo "  -- $PASSES passed, $FAILS failed"
    [[ $FAILS -eq 0 ]]
}

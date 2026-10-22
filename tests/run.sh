#!/usr/bin/env bash
#
# run.sh — run every tests/test-*.sh and report. Exit 1 if any test file fails.
#
# Usage: bash tests/run.sh [tests/test-name.sh ...]

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 0 ]]; then
    files=("$@")
else
    files=("$TESTS_DIR"/test-*.sh)
fi

failed=()
for f in "${files[@]}"; do
    echo "== $(basename "$f")"
    if ! bash "$f"; then
        failed+=("$(basename "$f")")
    fi
    echo
done

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "All test files passed."

#!/usr/bin/env bash
# CI gate: committed INDEX.md must match fresh generation.
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${AI_RULES_REPO:-$HARNESS_ROOT}"
COMMITTED="$REPO_ROOT/.claude/rules/INDEX.md"
GEN="$HARNESS_ROOT/scripts/gen-rules-index.sh"

[[ -f "$COMMITTED" ]] || { echo "check-rules-index: missing $COMMITTED — run: bash scripts/gen-rules-index.sh" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cp "$COMMITTED" "$tmp"

if ! bash "$GEN" >/dev/null; then
  echo "check-rules-index: gen-rules-index.sh failed (frontmatter or yq)" >&2
  exit 1
fi

if ! diff -q "$tmp" "$COMMITTED" >/dev/null 2>&1; then
  echo "check-rules-index: INDEX.md is stale — regenerate: bash scripts/gen-rules-index.sh" >&2
  diff -u "$tmp" "$COMMITTED" >&2 || true
  exit 1
fi

echo "check-rules-index: ok"

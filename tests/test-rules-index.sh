#!/usr/bin/env bash
# .claude/rules/INDEX.md must match a fresh generation (needs mikefarah yq v4).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v yq >/dev/null 2>&1; then
    echo "  skip  yq not installed"
    finish; exit $?
fi

W=$(make_tmp)
trap 'rm -rf "$W"' EXIT
cp "$REPO_ROOT/.claude/rules/INDEX.md" "$W/INDEX.before"
AI_RULES_REPO="$REPO_ROOT" bash "$REPO_ROOT/scripts/gen-rules-index.sh" >/dev/null 2>&1
assert_eq 0 "$?" "gen-rules-index.sh runs"
# Compare as sorted sets: row order depends on the platform's sort locale.
LC_ALL=C sort "$W/INDEX.before" > "$W/before.sorted"
LC_ALL=C sort "$REPO_ROOT/.claude/rules/INDEX.md" > "$W/after.sorted"
if diff "$W/before.sorted" "$W/after.sorted" >/dev/null; then
    pass "rules INDEX.md is up to date"
else
    fail "rules INDEX.md is stale — run: bash scripts/gen-rules-index.sh"
    diff "$W/before.sorted" "$W/after.sorted" | head -20
fi
cp "$W/INDEX.before" "$REPO_ROOT/.claude/rules/INDEX.md"

finish

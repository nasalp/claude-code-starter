#!/usr/bin/env bash
# setup.sh / uninstall.sh against a throwaway HOME — never touches the real ~/.claude.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAKE_HOME=$(make_tmp)
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude"
echo '{"theme":"dark"}' > "$FAKE_HOME/.claude/settings.json"

run_setup()     { HOME="$FAKE_HOME" bash "$REPO_ROOT/setup.sh" "$@" 2>&1; }
run_uninstall() { HOME="$FAKE_HOME" bash "$REPO_ROOT/uninstall.sh" "$@" 2>&1; }

# 1. Dry run changes nothing.
before=$(ls -A "$FAKE_HOME/.claude")
run_setup --dry-run >/dev/null
assert_eq "$before" "$(ls -A "$FAKE_HOME/.claude")" "dry run leaves ~/.claude untouched"
assert_eq '{"theme":"dark"}' "$(cat "$FAKE_HOME/.claude/settings.json")" "dry run does not rewrite settings.json"

# 2. Real install.
out=$(run_setup); rc=$?
assert_eq 0 "$rc" "setup.sh exits 0"
[[ -L "$FAKE_HOME/.claude/rules" ]] && pass "rules/ is symlinked" || fail "rules/ is symlinked"
[[ -L "$FAKE_HOME/.claude/CLAUDE.md" ]] && pass "CLAUDE.md is symlinked" || fail "CLAUDE.md is symlinked"
[[ ! -e "$FAKE_HOME/.claude/rules-corpus" ]] && pass "rules-corpus stays repo-local" || fail "rules-corpus stays repo-local"
backups=$(ls "$FAKE_HOME/.claude"/settings.json.backup-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq 1 "$backups" "existing settings.json was backed up"
if jq -e '.hooks.PreToolUse | length > 0' "$FAKE_HOME/.claude/settings.json" >/dev/null; then
    pass "settings.json wires hooks"
else
    fail "settings.json wires hooks"
fi
assert_contains "$(cat "$FAKE_HOME/.claude/settings.json")" "$REPO_ROOT/.claude/hooks" "hook paths point into the repo"

# 3. Re-run is a no-op.
assert_contains "$(run_setup)" "Summary: 0 change(s)" "re-running setup.sh changes nothing"

# 4. Uninstall restores the original state.
run_uninstall >/dev/null
assert_eq '{"theme":"dark"}' "$(cat "$FAKE_HOME/.claude/settings.json")" "uninstall restores the original settings.json"
links=$(find "$FAKE_HOME/.claude" -maxdepth 1 -type l | wc -l | tr -d ' ')
assert_eq 0 "$links" "uninstall removes every symlink"

# 5. A user-owned, non-empty directory is never overwritten.
mkdir -p "$FAKE_HOME/.claude/skills/my-skill"
run_setup >/dev/null; rc=$?
assert_eq 1 "$rc" "setup.sh refuses (exit 1) when ~/.claude/skills is a user directory"
[[ -d "$FAKE_HOME/.claude/skills/my-skill" ]] && pass "user skill directory is preserved" || fail "user skill directory is preserved"

finish

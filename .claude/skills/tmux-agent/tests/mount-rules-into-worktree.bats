#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mount-rules-into-worktree.sh"
  TMP="$(mktemp -d)"; export TMP
  WT="$TMP/wt"; mkdir -p "$WT"; ( cd "$WT" && git init -q )
  RULES="$TMP/rules"; mkdir -p "$RULES"; echo "# r" > "$RULES/a.md"
  SKILLS="$TMP/skills"; mkdir -p "$SKILLS"
}
teardown() { rm -rf "$TMP"; }

@test "mount creates .cursor/rules and .cursor/skills symlinks" {
  run bash "$SCRIPT" "$WT" "$RULES" "$SKILLS"
  [ "$status" -eq 0 ]
  [ -L "$WT/.cursor/rules" ]
  [ -L "$WT/.cursor/skills" ]
  [ "$(readlink "$WT/.cursor/rules")" = "$RULES" ]
}

@test "mount points AGENTS.md at the mounted rules" {
  bash "$SCRIPT" "$WT" "$RULES" "$SKILLS"
  run grep -q '.cursor/rules' "$WT/AGENTS.md"
  [ "$status" -eq 0 ]
}

@test "mount adds the symlinks to .git/info/exclude" {
  bash "$SCRIPT" "$WT" "$RULES" "$SKILLS"
  run grep -q '.cursor/rules' "$WT/.git/info/exclude"
  [ "$status" -eq 0 ]
}

@test "mount is idempotent (no duplicate exclude entries / AGENTS marker)" {
  bash "$SCRIPT" "$WT" "$RULES" "$SKILLS"
  bash "$SCRIPT" "$WT" "$RULES" "$SKILLS"
  run bash -c "grep -c '\.cursor/rules' '$WT/.git/info/exclude'"
  [ "$output" = "1" ]
  run bash -c "grep -c 'BEGIN ai-rules mount' '$WT/AGENTS.md'"
  [ "$output" = "1" ]
}

@test "mount resolves a RELATIVE gitdir from a .git file (git worktree add style)" {
  WT2="$TMP/linked"; mkdir -p "$WT2/realgit/info"
  ( cd "$WT2" && printf 'gitdir: realgit\n' > .git )   # relative gitdir
  run bash "$SCRIPT" "$WT2" "$RULES" "$SKILLS"
  [ "$status" -eq 0 ]
  run grep -q '.cursor/rules' "$WT2/realgit/info/exclude"
  [ "$status" -eq 0 ]
}

@test "mount tolerates a non-git worktree (symlinks still created)" {
  NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
  run bash "$SCRIPT" "$NOGIT" "$RULES" "$SKILLS"
  [ "$status" -eq 0 ]
  [ -L "$NOGIT/.cursor/rules" ]
}

#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  export TMUX_AGENT_TMPDIR="$TMP/runs"
  LIB="${BATS_TEST_DIRNAME}/../scripts/teardown-run.sh"
  mkdir -p "$TMUX_AGENT_TMPDIR/run-1"
}

teardown() {
  if [[ -n "${MONITOR_PID:-}" ]]; then
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
      kill "$MONITOR_PID" 2>/dev/null
    fi
  fi
  rm -rf "$TMP"
}

@test "teardown-run kills monitor, archives run dir, and removes source run dir" {
  sleep 1000 &
  MONITOR_PID="$!"
  echo "$MONITOR_PID" > "$TMUX_AGENT_TMPDIR/run-1/.monitor.pid"
  echo "state" > "$TMUX_AGENT_TMPDIR/run-1/orchestrator-state.md"
  archive_root="$TMP/archive"

  run bash "$LIB" --archive-root "$archive_root" "run-1"

  [ "$status" -eq 0 ]
  ! kill -0 "$MONITOR_PID" 2>/dev/null
  [ ! -d "$TMUX_AGENT_TMPDIR/run-1" ]
  [ "$(find "$archive_root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "1" ]
}

@test "teardown-run prunes old proof release tags for the PR" {
  echo "12" > "$TMUX_AGENT_TMPDIR/run-1/pr-number"
  cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "release list" ]]; then
  cat <<TAGS
proof-pr12-cycle3 latest
proof-pr12-cycle2 older
proof-pr99-cycle1 other
proof-pr12-cycle1 oldest
TAGS
  exit 0
fi
if [[ "$1 $2" == "release delete" ]]; then
  echo "$3" >> "$TMP/deleted-tags"
  exit 0
fi
exit 1
EOF
  chmod +x "$TMP/gh"

  run env PATH="$TMP:$PATH" TMP="$TMP" bash "$LIB" --archive-root "$TMP/archive" "run-1"

  [ "$status" -eq 0 ]
  grep -q '^proof-pr12-cycle2$' "$TMP/deleted-tags"
  grep -q '^proof-pr12-cycle1$' "$TMP/deleted-tags"
  ! grep -q '^proof-pr12-cycle3$' "$TMP/deleted-tags"
  ! grep -q '^proof-pr99-cycle1$' "$TMP/deleted-tags"
}

@test "teardown-run removes listed builder and watcher worktrees" {
  repo="$TMP/repo"
  mkdir -p "$repo" "$TMP/wt-builder" "$TMP/wt-watcher"
  printf '%s\n%s\n' "$TMP/wt-builder" "$TMP/wt-watcher" > "$TMUX_AGENT_TMPDIR/run-1/worktrees.txt"
  cat > "$TMP/git" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMP/git-calls"
exit 0
EOF
  chmod +x "$TMP/git"

  run env PATH="$TMP:$PATH" TMP="$TMP" bash "$LIB" --repo "$repo" --archive-root "$TMP/archive" "run-1"

  [ "$status" -eq 0 ]
  grep -q "worktree remove --force $TMP/wt-builder" "$TMP/git-calls"
  grep -q "worktree remove --force $TMP/wt-watcher" "$TMP/git-calls"
}

#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  SCRIPT="${BATS_TEST_DIRNAME}/../examples/spawn-watcher.sh"
  # Hermetic: the "omits Headroom env" test must not see an ambient export
  # from the developer's shell. CI runs clean; this makes local runs match.
  unset HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON HEADROOM_LOCAL_CLAUDE_PROXY_PORT
}

teardown() {
  rm -rf "$TMP"
}

@test "spawn-watcher carries Headroom proxy env into tmux command" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
echo "$@" > "$BATS_TMPDIR/last-tmux-args"
EOF
  chmod +x "$TMP/tmux"

  run bash -c "PATH='$TMP:$PATH' BATS_TMPDIR='$TMP' HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON='$TMP/headroom-python' HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9994 bash '$SCRIPT' \
                  run1 audit /repo origin/main owner/repo /run/builder.out /run/brief.md /run/verdicts"

  [ "$status" -eq 0 ]
  args=$(cat "$TMP/last-tmux-args")
  [[ "$args" == *"new-session"* ]]
  [[ "$args" == *"watch-audit-run1"* ]]
  [[ "$args" == *"HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON=$TMP/headroom-python"* ]]
  [[ "$args" == *"HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9994"* ]]
  [[ "$args" == *"watcher-loop.sh"* ]]
  [[ "$args" == *"builder-run1"* ]]
}

@test "spawn-watcher omits Headroom env when wrapper is unavailable" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
echo "$@" > "$BATS_TMPDIR/last-tmux-args"
EOF
  chmod +x "$TMP/tmux"

  run bash -c "PATH='$TMP:$PATH' BATS_TMPDIR='$TMP' bash '$SCRIPT' \
                  run1 audit /repo origin/main owner/repo /run/builder.out /run/brief.md /run/verdicts"

  [ "$status" -eq 0 ]
  args=$(cat "$TMP/last-tmux-args")
  [[ "$args" == *"watcher-loop.sh"* ]]
  [[ "$args" != *"HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON"* ]]
}

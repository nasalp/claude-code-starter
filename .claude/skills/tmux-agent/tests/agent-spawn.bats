#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-spawn.sh"
  TMP="$(mktemp -d)"; export TMP
  BIN="$TMP/bin"; mkdir -p "$BIN"
  WT="$TMP/wt"; mkdir -p "$WT"; ( cd "$WT" && git init -q )
  echo "prompt" > "$TMP/p.md"
  RUN="$TMP/run"; mkdir -p "$RUN"; export RUN_DIR="$RUN" RUN_ID="run-1"
  # stub tmux to record args
  cat > "$BIN/tmux" <<EOF
#!/bin/bash
echo "\$@" > "$TMP/tmux-args"
EOF
  chmod +x "$BIN/tmux"
  unset HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON HEADROOM_LOCAL_CLAUDE_PROXY_PORT
}
teardown() { rm -rf "$TMP"; }

@test "agent_spawn resolves provider via routing, composes cmd, ledgers, starts named tmux session" {
  # stub gemini (reviewer provider) so command-exists check passes
  cat > "$BIN/gemini" <<'EOF'
#!/bin/bash
true
EOF
  chmod +x "$BIN/gemini"
  run bash -c "PATH='$BIN:$PATH' bash '$SCRIPT' reviewer auto '$WT' '$TMP/p.md'"
  [ "$status" -eq 0 ]
  args="$(cat "$TMP/tmux-args")"
  [[ "$args" == *"new-session"* ]]
  [[ "$args" == *"agent-reviewer-gemini-run-1"* ]]
  [ -f "$RUN/cost-ledger.jsonl" ]
  run grep -q '"provider":"gemini"' "$RUN/cost-ledger.jsonl"
  [ "$status" -eq 0 ]
}

@test "agent_spawn fails loudly with install hint when the provider CLI is missing" {
  # composer provider command is `agent`; do NOT stub it
  run bash -c "PATH='$BIN:/usr/bin:/bin' bash '$SCRIPT' builder composer '$WT' '$TMP/p.md'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"install"* ]]
}

@test "agent_spawn mounts rules into the worktree for a no-add-dir provider (composer)" {
  cat > "$BIN/agent" <<'EOF'
#!/bin/bash
true
EOF
  chmod +x "$BIN/agent"
  run bash -c "PATH='$BIN:$PATH' bash '$SCRIPT' builder composer '$WT' '$TMP/p.md'"
  [ "$status" -eq 0 ]
  [ -L "$WT/.cursor/rules" ]
}

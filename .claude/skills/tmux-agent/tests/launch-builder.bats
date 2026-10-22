#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/launch-builder.sh"
  # Hermetic: Headroom wrapper + builder engine/model are opt-in; clear ambient
  # exports so default-path assertions are deterministic.
  unset HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON HEADROOM_LOCAL_CLAUDE_PROXY_PORT
  unset BUILDER_ENGINE BUILDER_MODEL
}

teardown() {
  rm -rf "$TMP"
}

@test "_builder_cmd echoes a complete claude --print invocation" {
  run bash -c "source '$LIB'; _builder_cmd /repo /prompt.txt /run/builder.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --print"* ]]
  [[ "$output" == *"--model sonnet"* ]]
  [[ "$output" == *"--tools default"* ]]
  [[ "$output" == *"--add-dir /repo"* ]]
  [[ "$output" == *"--add-dir \$HOME/.claude/rules"* ]]
  [[ "$output" == *"--add-dir \$HOME/.claude/skills"* ]]
  [[ "$output" == *"< /prompt.txt"* ]]
  [[ "$output" == *"> /run/builder.out"* ]]
}

@test "_builder_cmd routes through Headroom wrapper when exported" {
  run bash -c "export HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON='$TMP/headroom-python' HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9997; source '$LIB'; _builder_cmd /repo /prompt.txt /run/builder.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HEADROOM_MODE=token"* ]]
  [[ "$output" == *"HEADROOM_TELEMETRY=off"* ]]
  [[ "$output" == *"HEADROOM_LOCAL_CONTROL_GUARD_ENABLED=true"* ]]
  [[ "$output" == *"headroom.cli wrap claude"* ]]
  [[ "$output" == *"--port 9997"* ]]
  [[ "$output" == *"--no-context-tool --no-mcp --no-serena -- --print"* ]]
}

@test "_builder_cmd fails when prompt path empty" {
  run bash -c "source '$LIB'; _builder_cmd /repo '' /run/builder.out"
  [ "$status" -ne 0 ]
}

@test "_session_name returns builder-<run-id>" {
  run bash -c "source '$LIB'; _session_name foo-99"
  [ "$status" -eq 0 ]
  [ "$output" = "builder-foo-99" ]
}

@test "launch_builder main invokes tmux new-session with composed name + cmd" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
echo "$@" > "$BATS_TMPDIR/last-tmux-args"
EOF
  chmod +x "$TMP/tmux"
  echo "prompt content" > "$TMP/prompt.txt"

  run bash -c "PATH='$TMP:$PATH' BATS_TMPDIR='$TMP' bash '$LIB' \
                  myrun-1 /repo '$TMP/prompt.txt' '$TMP/builder.out'"
  [ "$status" -eq 0 ]
  args=$(cat "$TMP/last-tmux-args")
  [[ "$args" == *"new-session"* ]]
  [[ "$args" == *"builder-myrun-1"* ]]
  # launch-builder.sh wraps the inner cmd in `printf '%q'` for safe
  # transport through `bash -c`, which backslash-escapes spaces. Match
  # `claude` then `--print` separately so the assertion survives that.
  [[ "$args" == *"claude"*"--print"* ]]
}

@test "launch_builder main preserves Headroom wrapper in tmux command" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
echo "$@" > "$BATS_TMPDIR/last-tmux-args"
EOF
  chmod +x "$TMP/tmux"
  echo "prompt content" > "$TMP/prompt.txt"

  run bash -c "PATH='$TMP:$PATH' BATS_TMPDIR='$TMP' HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON='$TMP/headroom-python' HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9996 bash '$LIB' \
                  myrun-1 /repo '$TMP/prompt.txt' '$TMP/builder.out'"
  [ "$status" -eq 0 ]
  args=$(cat "$TMP/last-tmux-args")
  [[ "$args" == *"HEADROOM_MODE=token"* ]]
  [[ "$args" == *"headroom.cli"*"wrap"*"claude"* ]]
  [[ "$args" == *"--port"*"9996"* ]]
  [[ "$args" == *"--print"* ]]
}

@test "launch_builder main fails when called with < 4 args" {
  run bash -c "bash '$LIB' only-three /repo /prompt"
  [ "$status" -ne 0 ]
}

@test "_builder_cmd honors BUILDER_MODEL override on the default claude engine" {
  run bash -c "export BUILDER_MODEL=opus; source '$LIB'; _builder_cmd /repo /prompt.txt /run/builder.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --print --model opus"* ]]
}

@test "_builder_cmd composes the cursor agent invocation when BUILDER_ENGINE=cursor" {
  run bash -c "export BUILDER_ENGINE=cursor; source '$LIB'; _builder_cmd /repo /prompt.txt /run/builder.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent --print --force --trust"* ]]
  [[ "$output" == *"--workspace /repo"* ]]
  [[ "$output" == *"< /prompt.txt"* ]]
  [[ "$output" == *"> /run/builder.out"* ]]
}

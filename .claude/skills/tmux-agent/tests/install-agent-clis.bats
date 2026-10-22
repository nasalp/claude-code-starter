#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/install-agent-clis.sh"
  BIN="$(mktemp -d)"; export BIN
  LOG="$BIN/calls.log"; export LOG
  # stub curl + npm to record invocation instead of installing
  cat > "$BIN/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "$LOG"
EOF
  cat > "$BIN/npm" <<EOF
#!/bin/bash
echo "npm \$*" >> "$LOG"
EOF
  chmod +x "$BIN/curl" "$BIN/npm"
}
teardown() { rm -rf "$BIN"; }

@test "installs both CLIs when absent (curl for cursor, npm for gemini)" {
  run bash -c "PATH='$BIN:/usr/bin:/bin' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  run cat "$LOG"
  [[ "$output" == *"curl"*"cursor.com/install"* ]]
  [[ "$output" == *"npm"*"@google/gemini-cli"* ]]
}

@test "--check reports presence without installing" {
  run bash -c "PATH='$BIN:/usr/bin:/bin' bash '$SCRIPT' --check"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]   # nothing installed
}

@test "does not reinstall a CLI that is already present" {
  cat > "$BIN/agent" <<'EOF'
#!/bin/bash
true
EOF
  cat > "$BIN/gemini" <<'EOF'
#!/bin/bash
true
EOF
  chmod +x "$BIN/agent" "$BIN/gemini"
  run bash -c "PATH='$BIN:/usr/bin:/bin' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]   # both present => no curl/npm
}

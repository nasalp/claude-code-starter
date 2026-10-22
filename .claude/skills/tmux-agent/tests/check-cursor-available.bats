#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-cursor-available.sh"
  BIN="$(mktemp -d)"; export BIN
}
teardown() { rm -rf "$BIN"; }

@test "reports available + exit 0 when agent is on PATH and authed" {
  cat > "$BIN/agent" <<'EOF'
#!/bin/bash
[ "$1" = "status" ] && { echo "Logged in"; exit 0; }
EOF
  chmod +x "$BIN/agent"
  run bash -c "PATH='$BIN:$PATH' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"available"* ]] || [[ "$output" == *"OK"* ]]
}

@test "reports unavailable + recommends claude+sonnet fallback when agent absent" {
  run bash -c "PATH='$BIN:/usr/bin:/bin' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"sonnet"* ]]
}

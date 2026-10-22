#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/check-watchers.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "_session_alive returns 0 when tmux has-session succeeds" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
[ "$1" = "has-session" ] && exit 0
exit 1
EOF
  chmod +x "$TMP/tmux"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _session_alive watch-scroll-RUN"
  [ "$status" -eq 0 ]
}

@test "_session_alive returns 1 when tmux has-session fails" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _session_alive watch-scroll-RUN"
  [ "$status" -eq 1 ]
}

@test "_loop_pid returns first pgrep line" {
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
echo 12345
echo 12346
EOF
  chmod +x "$TMP/pgrep"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _loop_pid scroll"
  [ "$status" -eq 0 ]
  [ "$output" = "12345" ]
}

@test "_loop_pid returns empty when pgrep finds nothing" {
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/pgrep"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _loop_pid scroll"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_watchers reports DEFECT when session missing" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
echo 999
EOF
  chmod +x "$TMP/pgrep"

  run bash -c "PATH='$TMP:$PATH' bash '$LIB' RUN42 scroll"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEFECT"* ]]
  [[ "$output" == *"scroll"* ]]
  [[ "$output" == *"session"* ]]
}

@test "check_watchers reports DEFECT when loop pid missing" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TMP/tmux"
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/pgrep"

  run bash -c "PATH='$TMP:$PATH' bash '$LIB' RUN42 scroll"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEFECT"* ]]
  [[ "$output" == *"PID"* ]]
}

@test "check_watchers reports OK when both checks pass" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TMP/tmux"
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
echo 12345
EOF
  chmod +x "$TMP/pgrep"

  run bash -c "PATH='$TMP:$PATH' bash '$LIB' RUN42 scroll rules"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK scroll"* ]]
  [[ "$output" == *"OK rules"* ]]
}

@test "check_watchers requires at least one watcher name" {
  run bash -c "bash '$LIB' RUN42"
  [ "$status" -ne 0 ]
}

@test "_extract_diagnostic_line ignores body lines starting with BLIND (false-positive fix)" {
  mkdir -p "$TMP/vd"
  cat > "$TMP/vd/pass-20260529T020000Z.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 9
watching_branch: fix/foo
ref_requested: origin/fix/foo
sha_resolved: cafebabe1234abcd
sha_unchanged_since_pass: 0
file_being_audited: /tmp/builder.out
file_size_bytes: 100
last_activity_ts: 2026-05-29T02:00:00Z
=== END DIAGNOSTIC ===

audit body discusses a BLIND spot in the test coverage here.
EOF
  run bash -c "source '$LIB'; _extract_diagnostic_line scroll '$TMP/vd'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"BLIND"* ]]
  [[ "$output" == *"sha=cafebabe"* ]]
}

@test "_extract_diagnostic_line does NOT prepend tag (caller adds it)" {
  mkdir -p "$TMP/vd2"
  cat > "$TMP/vd2/pass-20260529T020100Z.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
sha_resolved: deadbeef00112233
sha_unchanged_since_pass: 0
=== END DIAGNOSTIC ===
EOF
  run bash -c "source '$LIB'; _extract_diagnostic_line scroll '$TMP/vd2'"
  [ "$status" -eq 0 ]
  [[ "$output" != scroll* ]]
}

@test "_extract_diagnostic_line returns one-line summary from latest verdict" {
  mkdir -p "$TMP/verdicts-scroll"
  cat > "$TMP/verdicts-scroll/pass-20260529T010000Z.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 4
watching_branch: fix/foo
ref_requested: origin/fix/foo
sha_resolved: abc1234deadbeef
sha_unchanged_since_pass: 0
file_being_audited: /tmp/builder.out
file_size_bytes: 84234
last_activity_ts: 2026-05-29T01:00:00Z
overall_verdict_running_total: PASS=1 REJECT=2 N/A=3
=== END DIAGNOSTIC ===

actual verdict body here
EOF
  run bash -c "source '$LIB'; _extract_diagnostic_line scroll '$TMP/verdicts-scroll'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha=abc1234"* ]]
  [[ "$output" == *"pass=4"* ]]
  [[ "$output" == *"unchanged=0"* ]]
}

@test "_extract_diagnostic_line flags BLIND state" {
  mkdir -p "$TMP/verdicts-rules"
  cat > "$TMP/verdicts-rules/pass-20260529T010000Z.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 2
watching_branch: fix/missing
ref_requested: origin/fix/missing
sha_resolved: NONE
sha_unchanged_since_pass: 2
BLIND: branch not on origin yet
=== END DIAGNOSTIC ===
EOF
  run bash -c "source '$LIB'; _extract_diagnostic_line rules '$TMP/verdicts-rules'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLIND"* ]]
}

@test "check_watchers in --diagnostic mode reports per-watcher line" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TMP/tmux"
  cat > "$TMP/pgrep" <<'EOF'
#!/bin/bash
echo 12345
EOF
  chmod +x "$TMP/pgrep"
  mkdir -p "$TMP/scroll-verdicts"
  cat > "$TMP/scroll-verdicts/pass-20260529T010000Z.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
watching_branch: fix/foo
ref_requested: origin/fix/foo
sha_resolved: deadbeef
sha_unchanged_since_pass: 0
file_size_bytes: 100
=== END DIAGNOSTIC ===
EOF
  run bash -c "PATH='$TMP:$PATH' bash '$LIB' --diagnostic --verdicts-dir '$TMP' RUN42 scroll"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK scroll"* || "$output" == *"sha=deadbeef"* ]]
}

#!/usr/bin/env bats
# AC-NL-* tests for spec/features/night-loop/night-loop.md

setup() {
  TMP="$(mktemp -d)"
  export TMP
  STUB="$TMP/stubs"
  mkdir -p "$STUB" "$TMP/runs/run-1" "$TMP/repo"
  printf 'repo: %s\nrun_id: run-1\nphase: AUDIT\nissue_number: 99\n' "$TMP/repo" > "$TMP/runs/run-1/orchestrator-state.md"

  LIB="${BATS_TEST_DIRNAME}/../scripts/night-loop.sh"
  MIRROR_LIB="${BATS_TEST_DIRNAME}/../scripts/lib/issue-mirror.sh"
  export NIGHT_LOOP_TEST_MODE=1
  export NIGHT_LOOP_SKIP_WATCHERS=1
  export TMUX_AGENT_TMPDIR="$TMP/runs"
  export NIGHT_LOOP_STUB_DIR="$STUB"

  # Stub gh (issue mirror) and audit-cycle (always green)
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"

  cat > "$STUB/audit-cycle.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB/audit-cycle.sh"
  ln -sf "${BATS_TEST_DIRNAME}/../scripts/audit-cycle.sh" "$STUB/audit-cycle-real.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "$TMP"
}

# AC-NL-1
@test "_state_write uses atomic temp+mv" {
  run_dir="$TMP/runs/atomic-1"
  mkdir -p "$run_dir"
  # shellcheck source=/dev/null
  source "$MIRROR_LIB"
  _state_write "$run_dir" "phase: BUILD"$'\n'"repo: /tmp"
  [ -f "$run_dir/orchestrator-state.md" ]
  ! ls "$run_dir"/*.tmp.* >/dev/null 2>&1
  grep -q '^phase: BUILD' "$run_dir/orchestrator-state.md"
}

# AC-NL-2
@test "_issue_mirror calls gh issue comment" {
  run_dir="$TMP/runs/run-1"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
exit 0
EOF
  chmod +x "$STUB/gh"
  export GH_LOG="$TMP/gh.log"
  export PATH="$STUB:$PATH"
  # shellcheck source=/dev/null
  source "$MIRROR_LIB"
  _issue_mirror "$run_dir" "phase advanced to SHIP"
  grep -q 'issue comment 99' "$GH_LOG"
}

# AC-NL-3
@test "resume reconstructs RUN_ID from issue body" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo 'RUN_ID: resumed-run-42'
  echo 'phase: BUILD'
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  # shellcheck source=/dev/null
  source "$MIRROR_LIB"
  run _issue_resume 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUN_ID=resumed-run-42"* ]]
  [[ "$output" == *"RUN_DIR=$TMP/runs/resumed-run-42"* ]]
  [ -f "$TMP/runs/resumed-run-42/orchestrator-state.md" ]
}

# AC-NL-4
@test "advance-phase blocked on watcher reject" {
  echo '{"verdict":"reject","confidence":0.9,"reason":"rule violation"}' > "$TMP/runs/run-1/watcher-verdict-composer.json"
  run bash -c "NIGHT_LOOP_TEST_MODE=1 NIGHT_LOOP_SKIP_WATCHERS=1 TMUX_AGENT_TMPDIR='$TMP/runs' source '$LIB'; night_loop_main advance-phase --run-dir '$TMP/runs/run-1'"
  [ "$status" -ne 0 ]
  grep -q '^phase: AUDIT' "$TMP/runs/run-1/orchestrator-state.md"
}

# AC-NL-5
@test "advance-phase succeeds on unanimous approve" {
  echo '{"verdict":"approve","confidence":0.9,"reason":"ok"}' > "$TMP/runs/run-1/watcher-verdict-composer.json"
  echo '{"verdict":"approve","confidence":0.8,"reason":"ok"}' > "$TMP/runs/run-1/watcher-verdict-gemini-flash.json"
  cat > "$STUB/audit-cycle.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB/audit-cycle.sh"
  run bash -c "NIGHT_LOOP_TEST_MODE=1 NIGHT_LOOP_SKIP_WATCHERS=1 TMUX_AGENT_TMPDIR='$TMP/runs' source '$LIB'; night_loop_main advance-phase --run-dir '$TMP/runs/run-1'"
  [ "$status" -eq 0 ]
  grep -q '^phase: ASSESS' "$TMP/runs/run-1/orchestrator-state.md"
}

# AC-NL-6
@test "_nl_wait_builder_terminal times out when builder never finishes" {
  out="$TMP/runs/run-1/agent-builder-hang.out"
  touch "$out"
  run env -u NIGHT_LOOP_TEST_MODE NIGHT_LOOP_BUILDER_WAIT_SEC=1 NIGHT_LOOP_MONITOR_SLEEP=1 \
    bash -c "source '$LIB'; _nl_wait_builder_terminal '$out' task-hang" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"timed out"* ]]
}

@test "_nl_wait_builder_terminal requires terminal marker" {
  out="$TMP/runs/run-1/agent-builder-task1.out"
  touch "$out"
  run bash -c "NIGHT_LOOP_TEST_MODE=1 source '$LIB'; _nl_wait_builder_terminal '$out' task1"
  [ "$status" -ne 0 ]
  touch "${out}.terminal"
  run bash -c "NIGHT_LOOP_TEST_MODE=1 source '$LIB'; _nl_wait_builder_terminal '$out' task1"
  [ "$status" -eq 0 ]
}

# AC-NL-8
@test "ship invokes pre-admin-merge-gate after draft PR in test mode" {
  run_dir="$TMP/runs/ship-1"
  mkdir -p "$run_dir"
  printf 'repo: %s\nrun_id: ship-1\nphase: SHIP\nissue_number: 1\n' "$TMP/repo" > "$run_dir/orchestrator-state.md"
  echo "BUILD SUCCESS" > "$run_dir/verify.log"
  echo '{"verdict":"approve","confidence":1,"reason":"ok"}' > "$run_dir/verdict-assessor-a.md"
  echo 'VERDICT: APPROVE' >> "$run_dir/verdict-assessor-a.md"
  echo '{"verdict":"approve","confidence":1,"reason":"ok"}' > "$run_dir/verdict-assessor-b.md"
  echo 'VERDICT: APPROVE' >> "$run_dir/verdict-assessor-b.md"
  echo '{"verdict":"approve","confidence":1,"reason":"ok"}' > "$run_dir/verdict-assessor-c.md"
  echo 'VERDICT: APPROVE' >> "$run_dir/verdict-assessor-c.md"

  cat > "$STUB/pre-admin-merge-gate.sh" <<EOF
#!/usr/bin/env bash
echo "gate-called \$*" >> "$TMP/gate.log"
exit 0
EOF
  chmod +x "$STUB/pre-admin-merge-gate.sh"

  run bash -c "export TMUX_AGENT_TMPDIR='$TMP/runs' NIGHT_LOOP_TEST_MODE=1 NIGHT_LOOP_SKIP_TEARDOWN=1 NIGHT_LOOP_STUB_DIR='$STUB'; source '$LIB'; _nl_ship '$run_dir' ship-1 '$TMP/repo'"
  [ "$status" -eq 0 ]
  [ -f "$run_dir/draft-pr-body.md" ]
  grep -q 'gate-called 99' "$TMP/gate.log"
  gate_line="$(grep -n 'gate-called' "$TMP/gate.log" | cut -d: -f1)"
  [ -n "$gate_line" ]
  [ -f "$run_dir/draft-pr-body.md" ]
}

# AC-NL-9
@test "gh stub receives --draft flag" {
  run_dir="$TMP/runs/ship-2"
  mkdir -p "$run_dir"
  printf 'repo: %s\nrun_id: ship-2\nphase: SHIP\nissue_number: 2\n' "$TMP/repo" > "$run_dir/orchestrator-state.md"
  echo "BUILD SUCCESS" > "$run_dir/verify.log"

  cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$TMP/gh-ship.log"
if [[ "\$*" == *"pr create"* && "\$*" == *"--draft"* ]]; then
  echo "https://github.com/org/repo/pull/99"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB/gh"

  cat > "$STUB/pre-admin-merge-gate.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB/pre-admin-merge-gate.sh"

  export NIGHT_LOOP_PR_NUMBER=99
  export NIGHT_LOOP_SKIP_TEARDOWN=1
  unset NIGHT_LOOP_TEST_MODE
  run bash -c "TMUX_AGENT_TMPDIR='$TMP/runs' NIGHT_LOOP_PR_NUMBER=99 NIGHT_LOOP_SKIP_TEARDOWN=1 NIGHT_LOOP_STUB_DIR='$STUB' source '$LIB'; _nl_ship '$run_dir' ship-2 '$TMP/repo'"
  [ "$status" -eq 0 ]
  grep -q -- '--draft' "$TMP/gh-ship.log"
}

# AC-NL-10
@test "night-loop.sh has no gh pr merge" {
  ! grep -qE 'gh[[:space:]]+pr[[:space:]]+merge' "$BATS_TEST_DIRNAME/../scripts/night-loop.sh"
}

@test "resume rejects unsafe RUN_ID from issue body" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo 'RUN_ID: evil; rm -rf /'
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  # shellcheck source=/dev/null
  source "$MIRROR_LIB"
  run _issue_resume 66
  [ "$status" -ne 0 ]
}

@test "run requires builder packet when not in test mode" {
  run_dir="$TMP/runs/prod-1"
  mkdir -p "$run_dir"
  printf 'repo: %s\nrun_id: prod-1\nphase: INIT\n' "$TMP/repo" > "$run_dir/orchestrator-state.md"
  run bash -c "unset NIGHT_LOOP_TEST_MODE; TMUX_AGENT_TMPDIR='$TMP/runs' source '$LIB'; _nl_run_main --repo '$TMP/repo' --run-id prod-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"builder packet missing"* ]]
}

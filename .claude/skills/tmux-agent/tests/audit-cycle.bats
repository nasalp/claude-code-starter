#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  export TMUX_AGENT_TMPDIR="$TMP/runs"
  LIB="${BATS_TEST_DIRNAME}/../scripts/audit-cycle.sh"
  CHECKS="$TMP/checks"
  mkdir -p "$CHECKS" "$TMUX_AGENT_TMPDIR"
}

teardown() {
  rm -rf "$TMP"
}

make_repo() {
  local repo="$TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  printf 'x\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
  printf '%s\n' "$repo"
}

make_run() {
  local run_id="$1"
  local repo="$2"
  local run_dir="$TMUX_AGENT_TMPDIR/$run_id"
  mkdir -p "$run_dir"
  printf 'repo: %s\n' "$repo" > "$run_dir/orchestrator-state.md"
}

write_check() {
  local name="$1"
  local body="$2"
  cat > "$CHECKS/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$CHECKS/$name"
}

@test "audit-cycle emits no warnings for an empty repo" {
  repo="$(make_repo)"
  make_run "empty-1" "$repo"
  write_check "verify-mocks-vs-e2e.sh" "exit 0"

  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "empty-1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ls "$TMUX_AGENT_TMPDIR/empty-1"/audit-cycle-*.log >/dev/null
}

@test "audit-cycle emits watcher-stale warning from child check" {
  repo="$(make_repo)"
  make_run "stale-1" "$repo"
  write_check "audit-watcher-claims.sh" "echo 'WARN watcher-stale: approved proof command failed'"

  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "stale-1"

  [ "$status" -eq 0 ]
  [ "$output" = "WARN watcher-stale: approved proof command failed" ]
}

@test "audit-cycle emits mock-on-it warning from child check" {
  repo="$(make_repo)"
  make_run "mock-1" "$repo"
  write_check "verify-mocks-vs-e2e.sh" "echo 'WARN mock-on-it: CustomerHealthSnapshotWriterJobIT.java uses @MockitoBean'"

  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "mock-1"

  [ "$status" -eq 0 ]
  [ "$output" = "WARN mock-on-it: CustomerHealthSnapshotWriterJobIT.java uses @MockitoBean" ]
}

@test "audit-cycle combines multiple warning categories and dedupes repeated category" {
  repo="$(make_repo)"
  make_run "combined-1" "$repo"
  write_check "one.sh" "printf '%s\n' 'WARN proof-blank: first' 'WARN proof-blank: duplicate'"
  write_check "two.sh" "echo 'WARN mock-on-it: integration mock'"

  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "combined-1"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "WARN proof-blank: first" ]
  [ "${lines[1]}" = "WARN mock-on-it: integration mock" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "audit-cycle rejects invalid RUN_ID" {
  repo="$(make_repo)"
  make_run "valid-1" "$repo"

  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "../bad"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid RUN_ID"* ]]
}

@test "audit-cycle rejects missing RUN_DIR" {
  run env AUDIT_CHECKS_DIR="$CHECKS" bash "$LIB" "missing-1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"RUN_DIR missing"* ]]
}

@test "audit-cycle removes temporary scratch directory after completion" {
  repo="$(make_repo)"
  make_run "cleanup-1" "$repo"
  write_check "cleanup.sh" "exit 0"
  scratch_parent="$TMP/scratch"
  mkdir -p "$scratch_parent"

  run env AUDIT_CHECKS_DIR="$CHECKS" TMPDIR="$scratch_parent" bash "$LIB" "cleanup-1"

  [ "$status" -eq 0 ]
  [ -z "$(find "$scratch_parent" -mindepth 1 -maxdepth 1 -type d -print)" ]
}

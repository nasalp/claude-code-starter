#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  export TMUX_AGENT_TMPDIR="$TMP/runs"
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/audit-watcher-claims.sh"
  mkdir -p "$TMP/repo" "$TMUX_AGENT_TMPDIR/run-1/verdicts-rules"
}

teardown() {
  rm -rf "$TMP"
}

@test "audit-watcher-claims emits watcher-stale when approved proof command fails" {
  cat > "$TMUX_AGENT_TMPDIR/run-1/checklist.md" <<'EOF'
- [x] item
  PROOF: test -f proof.txt
EOF
  echo "APPROVE" > "$TMUX_AGENT_TMPDIR/run-1/verdicts-rules/pass-1.md"

  run bash "$LIB" --repo "$TMP/repo" --run-dir "$TMUX_AGENT_TMPDIR/run-1"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ watcher-stale:* ]]
  [[ "$output" == *"test -f proof.txt"* ]]
}

@test "audit-watcher-claims emits no warning when approved proof command succeeds" {
  touch "$TMP/repo/proof.txt"
  cat > "$TMUX_AGENT_TMPDIR/run-1/checklist.md" <<'EOF'
PROOF: test -f proof.txt
EOF
  echo "APPROVE" > "$TMUX_AGENT_TMPDIR/run-1/verdicts-rules/pass-1.md"

  run bash "$LIB" --repo "$TMP/repo" --run-dir "$TMUX_AGENT_TMPDIR/run-1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "audit-watcher-claims ignores proof commands until watcher approves" {
  cat > "$TMUX_AGENT_TMPDIR/run-1/checklist.md" <<'EOF'
PROOF: test -f proof.txt
EOF
  echo "REJECT" > "$TMUX_AGENT_TMPDIR/run-1/verdicts-rules/pass-1.md"

  run bash "$LIB" --repo "$TMP/repo" --run-dir "$TMUX_AGENT_TMPDIR/run-1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

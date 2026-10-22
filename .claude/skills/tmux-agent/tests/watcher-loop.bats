#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  # Library under test
  LIB="${BATS_TEST_DIRNAME}/../scripts/watcher-loop.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "_now_ts returns 14-char compact UTC timestamp" {
  run bash -c "source '$LIB'; _now_ts"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

@test "_resolve_branch_sha returns sha when git rev-parse succeeds" {
  cat > "$TMP/git" <<'EOF'
#!/bin/bash
[ "$1" = "fetch" ] && exit 0
[ "$1" = "rev-parse" ] && echo "abc1234deadbeef"
EOF
  chmod +x "$TMP/git"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _resolve_branch_sha origin/main"
  [ "$status" -eq 0 ]
  [ "$output" = "abc1234deadbeef" ]
}

@test "_resolve_branch_sha returns empty string on failure" {
  cat > "$TMP/git" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/git"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _resolve_branch_sha origin/nope"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_file_size returns byte count for existing file" {
  printf 'abcdef' > "$TMP/f"
  run bash -c "source '$LIB'; _file_size '$TMP/f'"
  [ "$status" -eq 0 ]
  [ "$output" = "6" ]
}

@test "_file_size returns 0 for missing file" {
  run bash -c "source '$LIB'; _file_size '$TMP/missing'"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "_activity_detected fires when sha changes" {
  run bash -c "source '$LIB'; _activity_detected new_sha old_sha 100 100"
  [ "$status" -eq 0 ]
}

@test "_activity_detected fires when output grows" {
  run bash -c "source '$LIB'; _activity_detected same same 200 100"
  [ "$status" -eq 0 ]
}

@test "_activity_detected does NOT fire when sha and size unchanged" {
  run bash -c "source '$LIB'; _activity_detected same same 100 100"
  [ "$status" -ne 0 ]
}

@test "_activity_detected does NOT fire when sha empty" {
  run bash -c "source '$LIB'; _activity_detected '' '' 100 100"
  [ "$status" -ne 0 ]
}

# --- _should_audit cache-guard (carry-over from 2026-05-31 consensus) ---

@test "_should_audit fires on sha change regardless of delta" {
  run bash -c "source '$LIB'; _should_audit newsha oldsha 100 100 $(date +%s) 2048 900"
  [ "$status" -eq 0 ]
}

@test "_should_audit fires when size delta meets MIN_DELTA threshold" {
  # Delta = 200 - 100 = 100, MIN_DELTA = 50 → audit fires
  run bash -c "source '$LIB'; _should_audit same same 200 100 $(date +%s) 50 900"
  [ "$status" -eq 0 ]
}

@test "_should_audit SKIPS when size delta below MIN_DELTA and quiet age below MAX" {
  # Delta = 50, MIN_DELTA = 2048 → below threshold; last_audit_ts recent → no heartbeat
  run bash -c "source '$LIB'; _should_audit same same 150 100 $(date +%s) 2048 900"
  [ "$status" -ne 0 ]
}

@test "_should_audit fires (heartbeat) when quiet age exceeds MAX_QUIET" {
  # Delta tiny, last audit 1000s ago, max_quiet 900 → heartbeat fires
  local old=$(($(date +%s) - 1000))
  run bash -c "source '$LIB'; _should_audit same same 110 100 $old 2048 900"
  [ "$status" -eq 0 ]
}

@test "_should_audit does NOT heartbeat when last_audit_ts is 0 (first iteration)" {
  # last_audit_ts=0 means we've never audited; bootstrap suppresses heartbeat path
  # (sha-change or delta will handle the first real audit)
  run bash -c "source '$LIB'; _should_audit same same 100 100 0 2048 900"
  [ "$status" -ne 0 ]
}

@test "_should_audit does NOT fire when sha is empty" {
  run bash -c "source '$LIB'; _should_audit '' '' 100 100 $(date +%s) 2048 900"
  [ "$status" -ne 0 ]
}

@test "_should_audit fires when size decreased (truncation / log rotation)" {
  # size = 50, last_size = 100 → negative delta → audit fires so baseline resets.
  # Without this guard, the size-trigger would stay below MIN_DELTA forever.
  #.
  run bash -c "source '$LIB'; _should_audit same same 50 100 $(date +%s) 2048 900"
  [ "$status" -eq 0 ]
}

@test "_builder_alive returns 0 when tmux has-session succeeds" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
[ "$1" = "has-session" ] && exit 0
exit 1
EOF
  chmod +x "$TMP/tmux"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _builder_alive 'builder-RUN42'"
  [ "$status" -eq 0 ]
}

@test "_builder_alive returns 1 when tmux has-session fails" {
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _builder_alive 'builder-RUN42'"
  [ "$status" -eq 1 ]
}

@test "_drain_elapsed returns 1 (false) when quiet_since is 0" {
  run bash -c "source '$LIB'; _drain_elapsed 0 300"
  [ "$status" -eq 1 ]
}

@test "_drain_elapsed returns 0 (true) when elapsed exceeds threshold" {
  local past=$(($(date +%s) - 400))
  run bash -c "source '$LIB'; _drain_elapsed $past 300"
  [ "$status" -eq 0 ]
}

@test "_drain_elapsed returns 1 (false) when elapsed below threshold" {
  local recent=$(($(date +%s) - 100))
  run bash -c "source '$LIB'; _drain_elapsed $recent 300"
  [ "$status" -eq 1 ]
}

@test "_run_audit_pass writes verdict file and calls claude" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "AUDIT_VERDICT: PASS"
EOF
  chmod +x "$TMP/claude"
  echo "audit brief content" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/verdict.txt" ]
  grep -q "AUDIT_VERDICT: PASS" "$TMP/verdict.txt"
}

@test "_run_audit_pass prepends audit-cycle WARN lines before brief" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
cat
EOF
  chmod +x "$TMP/claude"
  mkdir -p "$TMP/repo" "$TMP/runs/run-1" "$TMP/checks"
  printf 'repo: %s\n' "$TMP/repo" > "$TMP/runs/run-1/orchestrator-state.md"
  cat > "$TMP/checks/warn.sh" <<'EOF'
#!/usr/bin/env bash
echo "WARN mock-on-it: integration test uses mock seam"
EOF
  chmod +x "$TMP/checks/warn.sh"
  echo "BRIEF_BODY" > "$TMP/brief.md"

  run bash -c "PATH='$TMP:$PATH'; RUN_ID=run-1 TMUX_AGENT_TMPDIR='$TMP/runs' AUDIT_CHECKS_DIR='$TMP/checks' source '$LIB'; RUN_ID=run-1 TMUX_AGENT_TMPDIR='$TMP/runs' AUDIT_CHECKS_DIR='$TMP/checks' _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"

  [ "$status" -eq 0 ]
  grep -q "WARN mock-on-it: integration test uses mock seam" "$TMP/verdict.txt"
  warn_line="$(grep -n "WARN mock-on-it" "$TMP/verdict.txt" | cut -d: -f1)"
  brief_line="$(grep -n "BRIEF_BODY" "$TMP/verdict.txt" | cut -d: -f1)"
  [ "$warn_line" -lt "$brief_line" ]
  grep -q "WARN mock-on-it: integration test uses mock seam" "$TMP/runs/run-1/warnings-prepend.txt"
}

@test "_run_audit_pass appends live tmux pane when BUILDER_SESSION set and capturable" {
  # Stub claude to echo back the combined prompt it receives on stdin so we
  # can assert the pane block was injected.
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
cat
EOF
  chmod +x "$TMP/claude"
  # Stub tmux: has-session OK, capture-pane returns canned output.
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session) exit 0 ;;
  capture-pane) echo "LIVE_PANE_LINE_1"; echo "LIVE_PANE_LINE_2"; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF_BODY" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; BUILDER_SESSION='builder-RUN9' source '$LIB'; BUILDER_SESSION='builder-RUN9' _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/verdict.txt" ]
  grep -q "BRIEF_BODY" "$TMP/verdict.txt"
  grep -q "LIVE BUILDER TMUX PANE" "$TMP/verdict.txt"
  grep -q "LIVE_PANE_LINE_1" "$TMP/verdict.txt"
  grep -q "LIVE_PANE_LINE_2" "$TMP/verdict.txt"
}

@test "_run_audit_pass reports 'not capturable' when session dead" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
cat
EOF
  chmod +x "$TMP/claude"
  # tmux has-session fails — session gone.
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF_BODY" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; BUILDER_SESSION='builder-GONE' source '$LIB'; BUILDER_SESSION='builder-GONE' _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "BRIEF_BODY" "$TMP/verdict.txt"
  grep -q "not capturable" "$TMP/verdict.txt"
}

@test "_run_audit_pass dispatches to codex when WATCHER_ENGINE=codex" {
  # Stub codex to write a recognizable marker so we can assert dispatch.
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
echo "CODEX_RAN args=$*"
cat
EOF
  chmod +x "$TMP/codex"
  # Stub claude to fail loudly if it gets called (it shouldn't).
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "CLAUDE_RAN_BUG"; exit 1
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF_BODY" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; WATCHER_ENGINE=codex source '$LIB'; WATCHER_ENGINE=codex _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "CODEX_RAN" "$TMP/verdict.txt"
  ! grep -q "CLAUDE_RAN_BUG" "$TMP/verdict.txt"
  grep -q "BRIEF_BODY" "$TMP/verdict.txt"
}

@test "_run_audit_pass routes a non-claude/non-codex engine through the provider registry" {
  # composer provider's command is `agent`; stub it to prove the lib branch ran.
  cat > "$TMP/agent" <<'EOF'
#!/bin/bash
echo "AGENT_RAN args=$*"
cat
EOF
  chmod +x "$TMP/agent"
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "CLAUDE_RAN_BUG"; exit 1
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF_BODY" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; WATCHER_ENGINE=composer source '$LIB'; WATCHER_ENGINE=composer _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "AGENT_RAN" "$TMP/verdict.txt"
  ! grep -q "CLAUDE_RAN_BUG" "$TMP/verdict.txt"
}

@test "_run_audit_pass dispatches to claude by default (no WATCHER_ENGINE)" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "CLAUDE_RAN args=$*"
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
echo "CODEX_RAN_BUG"; exit 1
EOF
  chmod +x "$TMP/codex"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; unset WATCHER_ENGINE; source '$LIB'; _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "CLAUDE_RAN" "$TMP/verdict.txt"
  ! grep -q "CODEX_RAN_BUG" "$TMP/verdict.txt"
}

@test "_run_audit_pass routes claude engine through Headroom wrapper when exported" {
  cat > "$TMP/headroom-python" <<'EOF'
#!/bin/bash
echo "HEADROOM_WRAPPER args=$*"
cat
EOF
  chmod +x "$TMP/headroom-python"
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "RAW_CLAUDE_RAN_BUG"; exit 1
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; export HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON='$TMP/headroom-python' HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9995; WATCHER_ENGINE=claude source '$LIB'; WATCHER_ENGINE=claude _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "HEADROOM_WRAPPER" "$TMP/verdict.txt"
  grep -q "headroom.cli wrap claude" "$TMP/verdict.txt"
  grep -q -- "--port 9995" "$TMP/verdict.txt"
  grep -q -- "--no-context-tool --no-mcp --no-serena -- --print" "$TMP/verdict.txt"
  grep -q "BRIEF" "$TMP/verdict.txt"
  ! grep -q "RAW_CLAUDE_RAN_BUG" "$TMP/verdict.txt"
}

@test "_run_audit_pass honours WATCHER_MODEL on claude engine" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
echo "CLAUDE_RAN args=$*"
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; WATCHER_ENGINE=claude WATCHER_MODEL=sonnet source '$LIB'; WATCHER_ENGINE=claude WATCHER_MODEL=sonnet _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "model sonnet" "$TMP/verdict.txt"
}

@test "_run_audit_pass reports 'not capturable' when BUILDER_SESSION unset" {
  cat > "$TMP/claude" <<'EOF'
#!/bin/bash
cat
EOF
  chmod +x "$TMP/claude"
  cat > "$TMP/tmux" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TMP/tmux"
  echo "BRIEF_BODY" > "$TMP/brief.md"
  run bash -c "PATH='$TMP:$PATH'; unset BUILDER_SESSION; source '$LIB'; _run_audit_pass '$TMP/repo' '$TMP/brief.md' '$TMP/verdict.txt'"
  [ "$status" -eq 0 ]
  grep -q "BRIEF_BODY" "$TMP/verdict.txt"
  grep -q "not capturable" "$TMP/verdict.txt"
}

@test "_post_pr_comment skips when no PR found" {
  cat > "$TMP/gh" <<'EOF'
#!/bin/bash
case "$1" in
  pr) [ "$2" = "list" ] && echo "" && exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMP/gh"
  echo "body" > "$TMP/v.txt"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no PR"* ]]
}

@test "_post_pr_comment posts when PR exists" {
  cat > "$TMP/gh" <<'EOF'
#!/bin/bash
case "$2" in
  list) echo "42"; exit 0 ;;
  comment) echo "POSTED $3 $5"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMP/gh"
  echo "body" > "$TMP/v.txt"
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"POSTED 42"* ]]
}

@test "_post_pr_comment skips when verdict body is empty (diagnostic-only pass)" {
  cat > "$TMP/gh" <<'EOF'
#!/bin/bash
case "$2" in
  list) echo "42"; exit 0 ;;
  comment) echo "POSTED $3"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMP/gh"
  cat > "$TMP/v.txt" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 5
sha_resolved: abc123
=== END DIAGNOSTIC ===
EOF
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP empty"* ]]
  [[ "$output" != *"POSTED"* ]]
}

@test "_post_pr_comment skips when body identical to last posted" {
  cat > "$TMP/gh" <<'EOF'
#!/bin/bash
case "$2" in
  list) echo "42"; exit 0 ;;
  comment) echo "POSTED $3"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMP/gh"
  cat > "$TMP/v.txt" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
=== END DIAGNOSTIC ===

REJECT: missing test coverage on AC-FOO-1
EOF
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"POSTED 42"* ]]
  # Second pass with same body (different diagnostic) MUST skip.
  cat > "$TMP/v.txt" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 2
=== END DIAGNOSTIC ===

REJECT: missing test coverage on AC-FOO-1
EOF
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP duplicate"* ]]
}

@test "_post_pr_comment strips diagnostic header from posted body" {
  cat > "$TMP/gh" <<EOF
#!/bin/bash
case "\$2" in
  list) echo "42"; exit 0 ;;
  comment)
    shift
    while [ \$# -gt 0 ]; do
      if [ "\$1" = "--body-file" ]; then cp "\$2" "$TMP/posted-body.txt"; exit 0; fi
      shift
    done
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "$TMP/gh"
  cat > "$TMP/v.txt" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
=== END DIAGNOSTIC ===

WATCH: builder pushing phase 3 commits
EOF
  run bash -c "PATH='$TMP:$PATH'; source '$LIB'; _post_pr_comment owner/repo fix/foo '$TMP/v.txt'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/posted-body.txt" ]
  ! grep -q "WATCHER DIAGNOSTIC" "$TMP/posted-body.txt"
  grep -q "WATCH: builder" "$TMP/posted-body.txt"
}

@test "watcher_loop_main requires 7 arguments" {
  run bash -c "source '$LIB'; watcher_loop_main one two three four five six"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"argument"* ]]
}

@test "_diagnostic_header emits structured block with sha and pass number" {
  run bash -c "source '$LIB'; _diagnostic_header 7 fix/foo origin/fix/foo abc1234 5 /tmp/builder.out 84234"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== WATCHER DIAGNOSTIC ==="* ]]
  [[ "$output" == *"pass_number: 7"* ]]
  [[ "$output" == *"watching_branch: fix/foo"* ]]
  [[ "$output" == *"sha_resolved: abc1234"* ]]
  [[ "$output" == *"sha_unchanged_since_pass: 5"* ]]
  [[ "$output" == *"file_size_bytes: 84234"* ]]
  [[ "$output" == *"=== END DIAGNOSTIC ==="* ]]
}

@test "_diagnostic_header reports NONE when sha empty (BLIND state)" {
  run bash -c "source '$LIB'; _diagnostic_header 3 fix/foo origin/fix/foo '' 3 /tmp/builder.out 0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha_resolved: NONE"* ]]
  [[ "$output" == *"BLIND"* ]]
}

@test "_extract_learnings pulls LEARNING CANDIDATES block from verdict body" {
  cat > "$TMP/v.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 5
sha_resolved: abc123
=== END DIAGNOSTIC ===

stuff stuff stuff

=== LEARNING CANDIDATES ===
- pattern: tests use assertThatNoException as sole assertion
  occurrences: 6
  rule_suggestion: forbid assertThatNoException as sole assertion
- pattern: containsKeys on PageEnvelope is tautological
  occurrences: 3
=== END LEARNINGS ===

trailing body
EOF
  run bash -c "source '$LIB'; _extract_learnings '$TMP/v.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pattern: tests use assertThatNoException"* ]]
  [[ "$output" == *"pattern: containsKeys"* ]]
  [[ "$output" != *"trailing body"* ]]
  [[ "$output" != *"stuff stuff"* ]]
}

@test "_extract_learnings empty output when no block present" {
  cat > "$TMP/v2.md" <<'EOF'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
=== END DIAGNOSTIC ===

audit body without learnings block
EOF
  run bash -c "source '$LIB'; _extract_learnings '$TMP/v2.md'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_append_learnings adds dated header + content to learnings file" {
  cat > "$TMP/v3.md" <<'EOF'
=== LEARNING CANDIDATES ===
- pattern: foo
=== END LEARNINGS ===
EOF
  run bash -c "source '$LIB'; _append_learnings '$TMP/v3.md' 7 cafebabe '$TMP/learnings.md'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/learnings.md" ]
  grep -q "pass=7" "$TMP/learnings.md"
  grep -q "sha=cafebabe" "$TMP/learnings.md"
  grep -q "pattern: foo" "$TMP/learnings.md"
}

@test "_diagnostic_header includes learnings_file path when set" {
  run bash -c "source '$LIB'; _diagnostic_header 3 fix/foo origin/fix/foo abc1234 0 /tmp/b.out 100 /tmp/learn.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"learnings_file: /tmp/learn.md"* ]]
}

@test "_write_blind_verdict produces a file containing BLIND tag" {
  run bash -c "source '$LIB'; _write_blind_verdict 2 fix/missing origin/fix/missing '$TMP/blind.md'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/blind.md" ]
  grep -q "BLIND" "$TMP/blind.md"
  grep -q "ref_requested: origin/fix/missing" "$TMP/blind.md"
}

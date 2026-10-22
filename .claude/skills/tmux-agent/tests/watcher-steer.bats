#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  STEER_LIB="${BATS_TEST_DIRNAME}/../scripts/lib/steer.sh"
  LB_LIB="${BATS_TEST_DIRNAME}/../scripts/launch-builder.sh"
  RUN_DIR="$TMP/run"
  mkdir -p "$RUN_DIR"
}

teardown() {
  rm -rf "$TMP"
}

# --- AC-STEER-1 ---

@test "_write_steer writes all five fields" {
  run bash -c "source '$STEER_LIB'; _steer_write '$RUN_DIR' reject 'missing test' 'add bats test' 'core.md'"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/STEER.md" ]
  grep -q '^severity: reject$' "$RUN_DIR/STEER.md"
  grep -q "^whats_wrong: missing test$" "$RUN_DIR/STEER.md"
  grep -q "^required_change: add bats test$" "$RUN_DIR/STEER.md"
  grep -q '^rule_ref: core.md$' "$RUN_DIR/STEER.md"
  grep -q '^ts: ' "$RUN_DIR/STEER.md"
  grep -q '^phase: ' "$RUN_DIR/STEER.md"
}

@test "_steer_process_verdict parses flat reject JSON into clean STEER fields" {
  cat > "$TMP/reject-flat.json" <<'EOF'
{"verdict":"reject","confidence":0.9,"reason":"found a TODO","required_changes":["remove the TODO and finish the path"],"violated_rules":["no-deferred-work.md"]}
EOF
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$RUN_DIR' '$TMP/reject-flat.json'"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/STEER.md" ]
  grep -q '^severity: reject$' "$RUN_DIR/STEER.md"
  grep -q "^whats_wrong: found a TODO$" "$RUN_DIR/STEER.md"
  grep -q "^required_change: remove the TODO and finish the path$" "$RUN_DIR/STEER.md"
  grep -q '^rule_ref: no-deferred-work.md$' "$RUN_DIR/STEER.md"
  grep -q '^ts: ' "$RUN_DIR/STEER.md"
  grep -q '^phase: ' "$RUN_DIR/STEER.md"
  required="$(grep '^required_change: ' "$RUN_DIR/STEER.md" | sed 's/^required_change: //')"
  [ "$required" != '[' ]
  [[ "$required" == *"remove the TODO and finish the path"* ]]
}

@test "_steer_process_verdict collapses multi-line reason and required_changes to single STEER lines" {
  cat > "$TMP/reject-multiline.json" <<'EOF'
{"verdict":"reject","reason":"first line\nsecond line","required_changes":["step one\nstep two"],"violated_rules":["rule-a\nrule-b"]}
EOF
  local run_ml="$TMP/run-multiline"
  mkdir -p "$run_ml"
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$run_ml' '$TMP/reject-multiline.json'"
  [ "$status" -eq 0 ]
  [ -f "$run_ml/STEER.md" ]
  wrong="$(grep '^whats_wrong: ' "$run_ml/STEER.md" | sed 's/^whats_wrong: //')"
  required="$(grep '^required_change: ' "$run_ml/STEER.md" | sed 's/^required_change: //')"
  rule_ref="$(grep '^rule_ref: ' "$run_ml/STEER.md" | sed 's/^rule_ref: //')"
  [[ "$wrong" == *"first line second line"* ]]
  [[ "$required" == *"step one step two"* ]]
  [[ "$rule_ref" == *"rule-a rule-b"* ]]
  [[ "$required" != *$'\n'* ]]
  line_count="$(grep -c '^required_change: ' "$run_ml/STEER.md")"
  [ "$line_count" -eq 1 ]
}

@test "_steer_process_verdict parses pretty-printed reject JSON into clean STEER fields" {
  cat > "$TMP/reject-pretty.json" <<'EOF'
{ "verdict": "reject", "reason": "found a TODO",
  "required_changes": [
    "remove the TODO and finish the path"
  ],
  "violated_rules": [
    "no-deferred-work.md"
  ] }
EOF
  local run2="$TMP/run-pretty"
  mkdir -p "$run2"
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$run2' '$TMP/reject-pretty.json'"
  [ "$status" -eq 0 ]
  [ -f "$run2/STEER.md" ]
  grep -q '^severity: reject$' "$run2/STEER.md"
  grep -q "^whats_wrong: found a TODO$" "$run2/STEER.md"
  grep -q "^required_change: remove the TODO and finish the path$" "$run2/STEER.md"
  grep -q '^rule_ref: no-deferred-work.md$' "$run2/STEER.md"
  required="$(grep '^required_change: ' "$run2/STEER.md" | sed 's/^required_change: //')"
  [ "$required" != '[' ]
  [[ "$required" == *"remove the TODO and finish the path"* ]]
}

# --- AC-STEER-2 ---

@test "clean verdict writes no STEER.md" {
  cat > "$TMP/approve.json" <<'EOF'
{"verdict":"approve","confidence":0.9,"reason":"all good"}
EOF
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$RUN_DIR' '$TMP/approve.json'"
  [ "$status" -eq 1 ]
  [ ! -f "$RUN_DIR/STEER.md" ]
}

# --- AC-STEER-3 ---

@test "_steer_severity_from_verdict maps structured warn verdict to warn" {
  cat > "$TMP/warn-structured.json" <<'EOF'
{"verdict":"warn","reason":"minor drift","required_changes":["tighten naming"],"violated_rules":["style.md"]}
EOF
  run bash -c "source '$STEER_LIB'; _steer_severity_from_verdict '$TMP/warn-structured.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "warn" ]
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$RUN_DIR' '$TMP/warn-structured.json'"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/STEER.md" ]
  grep -q '^severity: warn$' "$RUN_DIR/STEER.md"
  grep -q '^whats_wrong: minor drift$' "$RUN_DIR/STEER.md"
  grep -q '^required_change: tighten naming$' "$RUN_DIR/STEER.md"
}

@test "_steer_detect_forbidden matches skip with BSD-grep-safe pattern" {
  printf 'it.skip("later");\n' > "$TMP/skip-marker.txt"
  run bash -c "source '$STEER_LIB'; _steer_detect_forbidden '$TMP/skip-marker.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  printf 'noskipword\n' > "$TMP/no-skip.txt"
  run bash -c "source '$STEER_LIB'; _steer_detect_forbidden '$TMP/no-skip.txt'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "forbidden pattern triggers a warn steer (backstop)" {
  cat > "$TMP/warn-verdict.txt" <<'EOF'
{"verdict":"approve","confidence":0.8,"reason":"looks fine"}
some code with TODO left in
EOF
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$RUN_DIR' '$TMP/warn-verdict.txt'"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/STEER.md" ]
  grep -q '^severity: warn$' "$RUN_DIR/STEER.md"
  grep -q 'TODO' "$RUN_DIR/STEER.md"
}

@test "forbidden pattern in pane only triggers warn steer (backstop)" {
  cat > "$TMP/clean-verdict.json" <<'EOF'
{"verdict":"approve","confidence":0.95,"reason":"all good"}
EOF
  cat > "$TMP/builder-out.txt" <<'EOF'
builder working on feature
// TODO: finish this before commit
EOF
  local run3="$TMP/run-pane"
  mkdir -p "$run3"
  run bash -c "source '$STEER_LIB'; _steer_process_verdict '$run3' '$TMP/clean-verdict.json' '$TMP/builder-out.txt'"
  [ "$status" -eq 0 ]
  [ -f "$run3/STEER.md" ]
  grep -q '^severity: warn$' "$run3/STEER.md"
  grep -q 'TODO' "$run3/STEER.md"
  grep -q 'forbidden pattern:' "$run3/STEER.md"
}

# --- AC-STEER-4 ---

@test "builder brief contains read-STEER instruction" {
  run bash -c "source '$LB_LIB'; _steer_brief_snippet '$RUN_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STEER.md"* ]]
  [[ "$output" == *"$RUN_DIR/STEER.md"* ]]
  [[ "$output" == *"before each phase"* ]]
  [[ "$output" == *"before each commit"* ]]
  [[ "$output" == *"STEER_ACK"* ]]
  [[ "$output" == *"STEER.halt"* ]]
}

# --- AC-STEER-5 ---

@test "loop-guard caps steers per phase" {
  run bash -c "
    source '$STEER_LIB'
    export STEER_MAX_PER_PHASE=3
    phase='phase-a'
    mkdir -p '$RUN_DIR/steer/state'
    echo \"\$phase\" > '$RUN_DIR/steer/state/phase'
    for i in 1 2 3; do
      _steer_write '$RUN_DIR' warn \"wrong-\$i\" \"fix-\$i\" 'rule.md' || exit 1
    done
    _steer_write '$RUN_DIR' warn 'wrong-4' 'fix-4' 'rule.md'
    rc=\$?
    [[ \$rc -eq 3 ]] || exit 1
    grep -q 'cap_suppressed' '$RUN_DIR/steer/trail.ndjson'
  "
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/steer/trail.ndjson" ]
  grep -q 'cap_suppressed' "$RUN_DIR/steer/trail.ndjson"
}

# --- AC-STEER-6 ---

@test "identical steer is deduped" {
  run bash -c "
    source '$STEER_LIB'
    phase='phase-dedup'
    mkdir -p '$RUN_DIR/steer/state'
    echo \"\$phase\" > '$RUN_DIR/steer/state/phase'
    _steer_write '$RUN_DIR' escalate 'same issue' 'same fix' 'testing.md' || exit 1
    _steer_write '$RUN_DIR' escalate 'same issue' 'same fix' 'testing.md'
    rc2=\$?
    [[ \$rc2 -eq 2 ]] || exit 1
    count=\$(cat '$RUN_DIR/steer/state/count')
    [[ \"\$count\" == '1' ]] || exit 1
    grep -q 'dedup_suppressed' '$RUN_DIR/steer/trail.ndjson'
  "
  [ "$status" -eq 0 ]
  grep -q 'dedup_suppressed' "$RUN_DIR/steer/trail.ndjson"
}

# --- AC-STEER-7 ---

@test "reject severity sets halt marker" {
  run bash -c "source '$STEER_LIB'; _steer_write '$RUN_DIR' reject 'bad pattern' 'remove skip' 'no-silent-pass-in-ci.md'"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/STEER.halt" ]
  local run2="$TMP/run-warn"
  mkdir -p "$run2"
  run bash -c "source '$STEER_LIB'; _steer_write '$run2' warn 'minor' 'fix minor' 'style.md'"
  [ "$status" -eq 0 ]
  [ ! -f "$run2/STEER.halt" ]
}

# --- AC-STEER-8 ---

@test "phase boundary resets steer count and dedup via _steer_process_verdict" {
  run bash -c "
    source '$STEER_LIB'
    export STEER_MAX_PER_PHASE=3
    run_dir='$RUN_DIR'
    cat > '$TMP/verdict-sha-a.md' <<'VERDICT_A'
=== WATCHER DIAGNOSTIC ===
pass_number: 1
sha_resolved: abc111phase
=== END DIAGNOSTIC ===

{\"verdict\":\"reject\",\"reason\":\"issue a\",\"required_changes\":[\"fix a\"],\"violated_rules\":[\"core.md\"]}
VERDICT_A
    cat > '$TMP/verdict-sha-b.md' <<'VERDICT_B'
=== WATCHER DIAGNOSTIC ===
pass_number: 2
sha_resolved: def222phase
=== END DIAGNOSTIC ===

{\"verdict\":\"reject\",\"reason\":\"issue b\",\"required_changes\":[\"fix b\"],\"violated_rules\":[\"core.md\"]}
VERDICT_B
    _steer_process_verdict \"\$run_dir\" '$TMP/verdict-sha-a.md' || exit 1
    _steer_process_verdict \"\$run_dir\" '$TMP/verdict-sha-a.md'; rc=\$?; [[ \$rc -eq 0 || \$rc -eq 2 ]] || exit 1
    count_a=\$(cat \"\$run_dir/steer/state/count\")
    [[ \"\$count_a\" == '1' ]] || exit 1
    hash_count=\$(ls -1 \"\$run_dir/steer/state/hashes\" 2>/dev/null | wc -l | tr -d ' ')
    [[ \"\$hash_count\" == '1' ]] || exit 1
    _steer_process_verdict \"\$run_dir\" '$TMP/verdict-sha-b.md' || exit 1
    count_b=\$(cat \"\$run_dir/steer/state/count\")
    [[ \"\$count_b\" == '1' ]] || exit 1
    grep -q 'phase_reset' \"\$run_dir/steer/trail.ndjson\"
    _steer_process_verdict \"\$run_dir\" '$TMP/verdict-sha-b.md'; rc=\$?; [[ \$rc -eq 0 || \$rc -eq 2 ]] || exit 1
    count_b2=\$(cat \"\$run_dir/steer/state/count\")
    [[ \"\$count_b2\" == '1' ]] || exit 1
  "
  [ "$status" -eq 0 ]
  grep -q 'phase_reset' "$RUN_DIR/steer/trail.ndjson"
}

#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/check-codex-available.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "_codex_present returns 0 when codex is on PATH" {
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
echo ok
EOF
  chmod +x "$TMP/codex"
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _codex_present"
  [ "$status" -eq 0 ]
}

@test "_codex_present returns 1 when codex is absent" {
  # Empty PATH so codex resolution fails deterministically.
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _codex_present"
  [ "$status" -ne 0 ]
}

@test "_status_line prints AVAILABLE when codex present" {
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$TMP/codex"
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _status_line"
  [ "$status" -eq 0 ]
  [[ "$output" == AVAILABLE* ]]
  [[ "$output" == *"$TMP/codex"* ]]
}

@test "_status_line prints MISSING when codex absent" {
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _status_line"
  [ "$status" -eq 0 ]
  [[ "$output" == MISSING* ]]
}

@test "_action_hint suggests 2-codex+1-claude when present" {
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$TMP/codex"
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _action_hint"
  [[ "$output" == *"2 codex"* ]]
  [[ "$output" == *"1 claude"* ]]
}

@test "_action_hint suggests fallback when codex absent" {
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; _action_hint"
  [[ "$output" == *fallback* ]]
  [[ "$output" == *"3 claude"* ]]
  [[ "$output" == *"https://github.com/openai/codex-cli"* ]]
}

@test "check_codex_main prints both lines and propagates exit 0 when present" {
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$TMP/codex"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == AVAILABLE* ]]
  [[ "${lines[1]}" == ACTION* ]]
}

@test "check_codex_main propagates exit 1 when absent" {
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB'"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == MISSING* ]]
  [[ "${lines[1]}" == ACTION* ]]
}

@test "first token of first line is grep-able state word" {
  cat > "$TMP/codex" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$TMP/codex"
  # Use the proven `export PATH; source` form (the PATH-prefix + piped form is
  # CI-flaky); do the head/awk in the test shell, not inside a curated-PATH pipe.
  run bash -c "export PATH='$TMP:/usr/bin:/bin'; source '$LIB'; check_codex_main"
  [ "$status" -eq 0 ]
  first="$(printf '%s\n' "$output" | head -1 | awk '{print $1}')"
  [ "$first" = "AVAILABLE" ]
}

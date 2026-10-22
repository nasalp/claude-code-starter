#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/gen-packet.sh"
  TMP="$(mktemp -d)"; export TMP
  RULES="$TMP/rules"; mkdir -p "$RULES"; export SELECT_RULES_DIR="$RULES"
  cat > "$RULES/critical-sentinel.md" <<'EOF'
---
roles: [watcher]
severity: critical
---
# RULE_SENTINEL_MARKER
EOF
  echo "TASK_SENTINEL: do the thing" > "$TMP/task.md"
  echo "DIFF_SENTINEL diff body" > "$TMP/diff.txt"
}
teardown() { rm -rf "$TMP"; }

@test "gen_packet writes a packet for the role" {
  run bash "$SCRIPT" watcher "$TMP/out.md" --task "$TMP/task.md" --diff "$TMP/diff.txt"
  [ "$status" -eq 0 ]
  [ -f "$TMP/out.md" ]
}

@test "gen_packet places the rules block BEFORE the dynamic task block (cache discipline)" {
  bash "$SCRIPT" watcher "$TMP/out.md" --task "$TMP/task.md" --diff "$TMP/diff.txt"
  rules_line="$(grep -n 'RULE_SENTINEL_MARKER' "$TMP/out.md" | head -1 | cut -d: -f1)"
  task_line="$(grep -n 'TASK_SENTINEL' "$TMP/out.md" | head -1 | cut -d: -f1)"
  [ -n "$rules_line" ]
  [ -n "$task_line" ]
  [ "$rules_line" -lt "$task_line" ]
}

@test "gen_packet for watcher embeds the verdict schema" {
  bash "$SCRIPT" watcher "$TMP/out.md" --task "$TMP/task.md"
  run grep -c '"verdict"' "$TMP/out.md"
  [ "$status" -eq 0 ]
}

@test "gen_packet fails for an unknown role (no template)" {
  run bash "$SCRIPT" frobnicate "$TMP/out.md" --task "$TMP/task.md"
  [ "$status" -ne 0 ]
}

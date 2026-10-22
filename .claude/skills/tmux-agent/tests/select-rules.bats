#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/select-rules.sh"
  RULES="$(mktemp -d)"; export SELECT_RULES_DIR="$RULES"

  cat > "$RULES/security.md" <<'EOF'
---
roles: [reviewer, watcher]
severity: critical
---
# Security
EOF

  cat > "$RULES/builder-only.md" <<'EOF'
---
roles:
  - builder
severity: high
---
# Builder only
EOF

  cat > "$RULES/no-metadata.md" <<'EOF'
# A plain rule with no frontmatter
EOF

  cat > "$RULES/low-rule.md" <<'EOF'
---
roles: [watcher]
severity: low
---
# Low
EOF
}
teardown() { rm -rf "$RULES"; }

@test "select-rules --role watcher lists watcher rules + metadata-less rule (safe default)" {
  run bash "$SCRIPT" --role watcher
  [ "$status" -eq 0 ]
  [[ "$output" == *"security.md"* ]]
  [[ "$output" == *"low-rule.md"* ]]
  [[ "$output" == *"no-metadata.md"* ]]   # no roles => applies to all roles
  [[ "$output" != *"builder-only.md"* ]]  # builder role only
}

@test "select-rules --role builder excludes watcher-only rules" {
  run bash "$SCRIPT" --role builder
  [ "$status" -eq 0 ]
  [[ "$output" == *"builder-only.md"* ]]
  [[ "$output" == *"no-metadata.md"* ]]
  [[ "$output" != *"low-rule.md"* ]]
}

@test "select-rules --severity critical,high filters by severity" {
  run bash "$SCRIPT" --role watcher --severity critical,high
  [ "$status" -eq 0 ]
  [[ "$output" == *"security.md"* ]]      # critical, watcher
  [[ "$output" != *"low-rule.md"* ]]       # low severity excluded
}

@test "select-rules output is deterministically sorted" {
  run bash "$SCRIPT" --role watcher
  sorted="$(printf '%s\n' "$output" | sort)"
  [ "$output" = "$sorted" ]
}

@test "select-rules fails without --role" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

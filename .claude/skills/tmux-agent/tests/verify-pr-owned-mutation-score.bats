#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-pr-owned-mutation-score.sh"
}

teardown() {
  rm -rf "$TMP"
}

init_repo() {
  local repo="$TMP/repo"
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" checkout -q -b main
  mkdir -p "$repo/src/main/java/app"
  printf 'line1\nline2\nline3\n' > "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "feat: baseline"
  git -C "$repo" checkout -q -b feature
  printf 'line1\nchanged-by-pr\nline3\n' > "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "feat: change Foo"
  printf '%s\n' "$repo"
}

@test "verify-pr-owned-mutation-score warns when PR-owned score is below threshold" {
  repo="$(init_repo)"
  cat > "$TMP/report.txt" <<'EOF'
KILLED src/main/java/app/Foo.java:2
SURVIVED src/main/java/app/Foo.java:2
EOF

  run bash "$LIB" --repo "$repo" --base main --report "$TMP/report.txt" --threshold 80

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ pr-owned-mutation:* ]]
  [[ "$output" == *"50%"* ]]
}

@test "verify-pr-owned-mutation-score ignores legacy survivors" {
  repo="$(init_repo)"
  cat > "$TMP/report.txt" <<'EOF'
SURVIVED src/main/java/app/Foo.java:1
EOF

  run bash "$LIB" --repo "$repo" --base main --report "$TMP/report.txt" --threshold 80

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-pr-owned-mutation-score resolves bare filename via git ls-files" {
  repo="$(init_repo)"
  cat > "$TMP/report.txt" <<'EOF'
KILLED Foo.java:2
SURVIVED Foo.java:2
EOF

  run bash "$LIB" --repo "$repo" --base main --report "$TMP/report.txt" --threshold 80

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ pr-owned-mutation:* ]]
  [[ "$output" == *"50%"* ]]
}

@test "verify-pr-owned-mutation-score accepts PR-owned score at threshold" {
  repo="$(init_repo)"
  cat > "$TMP/report.txt" <<'EOF'
KILLED src/main/java/app/Foo.java:2
KILLED src/main/java/app/Foo.java:2
SURVIVED src/main/java/app/Foo.java:2
SURVIVED src/main/java/app/Foo.java:1
EOF

  run bash "$LIB" --repo "$repo" --base main --report "$TMP/report.txt" --threshold 66

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  cd "$TMP"
  git init -q --initial-branch=main
  git config user.email t@e
  git config user.name t
  echo seed > seed.txt
  git add seed.txt
  git commit -q -m "seed"
  git branch -q feat
  git checkout -q feat
  GUARD="${BATS_TEST_DIRNAME}/../scripts/pre-push-proof-guard.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "REJECT when commit body lacks proof markers" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "feat: thing without proof"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 1 ]
  [[ "$output$stderr" =~ "lacks proof-tail" ]]
}

@test "OK when commit body has BUILD SUCCESS marker" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "feat: thing"$'\n\n'"[INFO] BUILD SUCCESS"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 0 ]
}

@test "OK when commit body has Tests run zero-failure marker" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "feat: thing"$'\n\n'"Tests run: 42, Failures: 0"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 0 ]
}

@test "OK when commit body references an existing docs/proof/phase-*.md in the commit" {
  mkdir -p docs/proof
  echo "proof" > docs/proof/phase-1-x.md
  echo x >> a.txt && git add a.txt docs/proof/phase-1-x.md
  git commit -q -m "feat: thing"$'\n\n'"see docs/proof/phase-1-x.md"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 0 ]
}

@test "REJECT when commit body references docs/proof/phase-*.md not in the commit" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "feat: thing"$'\n\n'"see docs/proof/phase-1-x.md"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 1 ]
  [[ "$output$stderr" =~ "not in this commit" ]]
}

@test "OK when commit body has BROKEN-PRE-EXISTING annotation" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "chore: thing"$'\n\n'"BROKEN-PRE-EXISTING: lint script missing on main"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 0 ]
}

@test "REJECT when diff introduces test.skip without allow-skip comment" {
  cat > a.test.ts <<'EOF'
test.skip('flaky thing', () => {})
EOF
  git add a.test.ts
  git commit -q -m "test: skip flaky"$'\n\n'"Tests run: 1, Failures: 0"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 1 ]
  [[ "$output$stderr" =~ "skip-as-progress" ]]
}

@test "OK when diff introduces test.skip with allow-skip comment" {
  cat > a.test.ts <<'EOF'
test.skip('flaky thing', () => {}) // allow-skip: PROJ-123
EOF
  git add a.test.ts
  git commit -q -m "test: skip flaky"$'\n\n'"Tests run: 1, Failures: 0"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 0 ]
}

@test "REJECT when diff introduces @Disabled in a Java file" {
  cat > Foo.java <<'EOF'
@Disabled
public class Foo {}
EOF
  git add Foo.java
  git commit -q -m "test: park Foo"$'\n\n'"Tests run: 1, Failures: 0"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 1 ]
  [[ "$output$stderr" =~ "@Disabled" ]]
}

@test "REJECT when diff introduces continue-on-error: true in workflow yml" {
  mkdir -p .github/workflows
  cat > .github/workflows/ci.yml <<'EOF'
jobs:
  build:
    steps:
      - run: ./scripts/run.sh
        continue-on-error: true
EOF
  git add .github/workflows/ci.yml
  git commit -q -m "ci: be lenient"$'\n\n'"Tests run: 1, Failures: 0"
  run bash "$GUARD" HEAD main
  [ "$status" -eq 1 ]
  [[ "$output$stderr" =~ "continue-on-error" ]]
}

@test "exits 2 on usage error when no upstream and no base passed" {
  echo x >> a.txt && git add a.txt
  git commit -q -m "feat: thing"$'\n\n'"BUILD SUCCESS"
  run bash "$GUARD" HEAD
  [ "$status" -eq 2 ]
}

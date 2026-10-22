#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-mocks-vs-e2e.sh"
  mkdir -p "$TMP/repo/src/test/java/app"
}

teardown() {
  rm -rf "$TMP"
}

@test "verify-mocks-vs-e2e emits mock-on-it for MockitoBean in Java IT" {
  cat > "$TMP/repo/src/test/java/app/CustomerHealthSnapshotWriterJobIT.java" <<'EOF'
class CustomerHealthSnapshotWriterJobIT {
  @MockitoBean CustomerPort customerPort;
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ mock-on-it:* ]]
  [[ "$output" == *"CustomerHealthSnapshotWriterJobIT.java"* ]]
}

@test "verify-mocks-vs-e2e ignores mocks outside integration tests" {
  cat > "$TMP/repo/src/test/java/app/CustomerHealthSnapshotWriterJobTest.java" <<'EOF'
class CustomerHealthSnapshotWriterJobTest {
  @MockitoBean CustomerPort customerPort;
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-mocks-vs-e2e skips node_modules integration tests" {
  mkdir -p "$TMP/repo/node_modules/pkg"
  cat > "$TMP/repo/node_modules/pkg/CustomerHealthSnapshotWriterJobIT.java" <<'EOF'
class CustomerHealthSnapshotWriterJobIT {
  @MockitoBean CustomerPort customerPort;
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-mocks-vs-e2e reads custom mock patterns from checks-config.yml" {
  cat > "$TMP/repo/checks-config.yml" <<'EOF'
mock_patterns:
  - CustomIntegrationMock
EOF
  cat > "$TMP/repo/src/test/java/app/Billing.integration.test.ts" <<'EOF'
CustomIntegrationMock("billing-client")
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ mock-on-it:* ]]
  [[ "$output" == *"CustomIntegrationMock"* ]]
}

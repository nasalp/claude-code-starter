#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-test-asserts-behavior.sh"
  mkdir -p "$TMP/repo/src/test/java/app" "$TMP/repo/frontend/src"
}

teardown() {
  rm -rf "$TMP"
}

@test "verify-test-asserts-behavior warns on fs.readFileSync regex tests" {
  cat > "$TMP/repo/frontend/src/source-shape.test.ts" <<'EOF'
const source = fs.readFileSync("controller.ts", "utf8")
expect(/withSpan/.test(source)).toBe(true)
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ regex-over-source:* ]]
  [[ "$output" == *"source-shape.test.ts"* ]]
}

@test "verify-test-asserts-behavior warns on readFileSync literal toContain assertions" {
  cat > "$TMP/repo/frontend/src/chart.test.ts" <<'EOF'
const source = fs.readFileSync("Chart.tsx", "utf8")
expect(source).toContain("export function Chart")
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ regex-over-source:* ]]
  [[ "$output" == *"toContain"* ]]
}

@test "verify-test-asserts-behavior accepts Playwright toHaveCount on rendered DOM" {
  cat > "$TMP/repo/frontend/src/chart.test.ts" <<'EOF'
test("chart", async ({ page }) => {
  await expect(page.locator("path")).toHaveCount(4)
})
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-test-asserts-behavior warns on JUnit test without assertion" {
  cat > "$TMP/repo/src/test/java/app/FooTest.java" <<'EOF'
class FooTest {
  @Test
  void doesSomething() {
    service.run();
  }
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ regex-over-source:* ]]
  [[ "$output" == *"FooTest.java"* ]]
}

@test "verify-test-asserts-behavior skips node_modules test files" {
  mkdir -p "$TMP/repo/node_modules/pkg"
  cat > "$TMP/repo/node_modules/pkg/FooTest.java" <<'EOF'
class FooTest {
  @Test
  void doesSomething() {
    service.run();
  }
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-test-asserts-behavior accepts JUnit test with behavioral assertion" {
  cat > "$TMP/repo/src/test/java/app/FooTest.java" <<'EOF'
class FooTest {
  @Test
  void doesSomething() {
    assertThat(service.run()).isEqualTo("ok");
  }
}
EOF

  run bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

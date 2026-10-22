#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-red-then-green.sh"
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
  printf 'class Foo {}\n' > "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "feat: baseline"
  git -C "$repo" checkout -q -b feature
  printf '%s\n' "$repo"
}

@test "verify-red-then-green emits no warning when branch has no fix commits" {
  repo="$(init_repo)"
  printf 'class Bar {}\n' > "$repo/src/main/java/app/Bar.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "feat: add Bar"

  run bash "$LIB" --repo "$repo" --base main

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-red-then-green emits no-red-commit when fix parent is not test commit" {
  repo="$(init_repo)"
  printf '// unrelated\n' >> "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "chore: unrelated parent"
  printf '// fixed\n' >> "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "fix: repair Foo"

  run bash "$LIB" --repo "$repo" --base main

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ no-red-commit:* ]]
  [[ "$output" == *"fix: repair Foo"* ]]
}

@test "verify-red-then-green accepts fix immediately after related test commit" {
  repo="$(init_repo)"
  mkdir -p "$repo/src/test/java/app"
  printf 'class FooTest { String subject = "Foo"; }\n' > "$repo/src/test/java/app/FooTest.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "test: failing reproduction for Foo"
  printf '// fixed\n' >> "$repo/src/main/java/app/Foo.java"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "fix: repair Foo"

  run bash "$LIB" --repo "$repo" --base main

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

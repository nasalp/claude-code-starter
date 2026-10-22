#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-screenshot-not-blank.sh"
  printf 'fake png\n' > "$TMP/screenshot.png"
}

teardown() {
  rm -rf "$TMP"
}

stub_file_as_png() {
  cat > "$TMP/file" <<'EOF'
#!/usr/bin/env bash
echo "$1: PNG image data"
EOF
  chmod +x "$TMP/file"
}

stub_magick_colors() {
  local count="$1"
  cat > "$TMP/magick" <<EOF
#!/usr/bin/env bash
echo "$count"
EOF
  chmod +x "$TMP/magick"
}

@test "verify-screenshot-not-blank emits proof-blank for low-colour image" {
  stub_file_as_png
  stub_magick_colors 3

  run env PATH="$TMP:$PATH" AUDIT_DISABLE_VISION=1 bash "$LIB" "$TMP/screenshot.png"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ proof-blank:* ]]
  [[ "$output" == *"3 unique colors"* ]]
}

@test "verify-screenshot-not-blank emits no warning for populated image" {
  stub_file_as_png
  stub_magick_colors 9

  run env PATH="$TMP:$PATH" AUDIT_DISABLE_VISION=1 bash "$LIB" "$TMP/screenshot.png"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "verify-screenshot-not-blank rejects a missing image path as runtime error" {
  run bash "$LIB" "$TMP/missing.png"

  [ "$status" -ne 0 ]
  [[ "$output" == *"image not found"* ]]
}

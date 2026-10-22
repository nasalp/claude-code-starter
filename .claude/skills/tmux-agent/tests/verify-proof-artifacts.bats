#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/checks/verify-proof-artifacts.sh"
  mkdir -p "$TMP/repo/docs/proof"
}

teardown() {
  rm -rf "$TMP"
}

write_mock_file_as_png() {
  cat > "$TMP/file" <<'EOF'
#!/usr/bin/env bash
echo "$1: PNG image data"
EOF
  chmod +x "$TMP/file"
}

write_mock_magick_colors() {
  local count="$1"
  cat > "$TMP/magick" <<EOF
#!/usr/bin/env bash
echo "$count"
EOF
  chmod +x "$TMP/magick"
}

write_mock_gh() {
  cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "api" && "$2" == *"missing"* ]]; then
  exit 1
fi
printf 'fake png bytes\n'
EOF
  chmod +x "$TMP/gh"
}

@test "verify-proof-artifacts emits proof-404 for missing GitHub image URL" {
  write_mock_gh
  write_mock_file_as_png
  write_mock_magick_colors 9
  cat > "$TMP/repo/docs/proof/phase-1.md" <<'EOF'
![missing](https://github.com/owner/repo/releases/download/proof-pr1-cycle1/missing.png)
EOF

  run env PATH="$TMP:$PATH" AUDIT_DISABLE_VISION=1 bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ proof-404:* ]]
  [[ "$output" == *"missing.png"* ]]
}

@test "verify-proof-artifacts emits proof-blank for low-colour downloaded image" {
  write_mock_gh
  write_mock_file_as_png
  write_mock_magick_colors 3
  cat > "$TMP/repo/docs/proof/phase-1.md" <<'EOF'
![blank](https://github.com/owner/repo/releases/download/proof-pr1-cycle1/chart.png)
EOF

  run env PATH="$TMP:$PATH" AUDIT_DISABLE_VISION=1 bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == WARN\ proof-blank:* ]]
  [[ "$output" == *"chart.png"* ]]
}

@test "verify-proof-artifacts emits no warning for populated image URL" {
  write_mock_gh
  write_mock_file_as_png
  write_mock_magick_colors 12
  cat > "$TMP/repo/docs/proof/phase-1.md" <<'EOF'
![populated](https://github.com/owner/repo/releases/download/proof-pr1-cycle1/chart.png)
EOF

  run env PATH="$TMP:$PATH" AUDIT_DISABLE_VISION=1 bash "$LIB" --repo "$TMP/repo"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

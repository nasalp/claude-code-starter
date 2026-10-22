#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  GUARD="${BATS_TEST_DIRNAME}/../scripts/quota-preflight.sh"
  export TMP
}

teardown() {
  rm -rf "$TMP"
}

@test "exits 2 with usage on missing provider arg" {
  run bash "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "usage:" ]]
}

@test "exits 2 on unknown provider" {
  run bash "$GUARD" totally-unknown
  [ "$status" -eq 2 ]
  [[ "$output$stderr" =~ "unknown PROVIDER" ]]
}

@test "anthropic UNKNOWN (rc=0) when ANTHROPIC_API_KEY unset" {
  run bash -c "unset ANTHROPIC_API_KEY; bash '$GUARD' anthropic"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic: UNKNOWN no-ANTHROPIC_API_KEY-set" ]]
}

@test "anthropic UNKNOWN dry-run advertises probe URL" {
  run bash -c "ANTHROPIC_API_KEY=dummy QUOTA_PROBE_DRY_RUN=1 bash '$GUARD' anthropic"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic: UNKNOWN dry-run" ]]
  [[ "$output" =~ "https://api.anthropic.com" ]]
}

@test "anthropic OK when curl returns sufficient headroom" {
  # Fake curl writes a reset header 4h in the future to the -D file
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
# parse args: find -D <file>
hdr_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" = "-D" ]]; then hdr_file="$2"; shift 2; continue; fi
  shift
done
future=$(date -u -v+4H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+4 hours" +"%Y-%m-%dT%H:%M:%SZ")
cat > "$hdr_file" <<H
HTTP/1.1 200 OK
anthropic-ratelimit-tokens-reset: $future
H
exit 0
EOF
  chmod +x "$TMP/bin/curl"
  run bash -c "PATH='$TMP/bin:$PATH'; ANTHROPIC_API_KEY=dummy bash '$GUARD' anthropic 3600"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic: OK" ]]
}

@test "anthropic LOW (rc=1) when reset is within MIN_HEADROOM" {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
hdr_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" = "-D" ]]; then hdr_file="$2"; shift 2; continue; fi
  shift
done
soon=$(date -u -v+5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%SZ")
cat > "$hdr_file" <<H
HTTP/1.1 200 OK
anthropic-ratelimit-tokens-reset: $soon
H
exit 0
EOF
  chmod +x "$TMP/bin/curl"
  run bash -c "PATH='$TMP/bin:$PATH'; ANTHROPIC_API_KEY=dummy bash '$GUARD' anthropic 3600"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "anthropic: LOW" ]]
}

@test "anthropic UNKNOWN when curl fails" {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$TMP/bin/curl"
  run bash -c "PATH='$TMP/bin:$PATH'; ANTHROPIC_API_KEY=dummy bash '$GUARD' anthropic"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic: UNKNOWN curl-failed" ]]
}

@test "codex UNKNOWN when neither OPENAI_API_KEY nor auth file present" {
  run bash -c "unset OPENAI_API_KEY; CODEX_AUTH_FILE='$TMP/nope.json' bash '$GUARD' openai-codex"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "openai-codex: UNKNOWN" ]]
}

@test "both runs both probes (UNKNOWN-UNKNOWN keeps rc=0)" {
  run bash -c "unset ANTHROPIC_API_KEY OPENAI_API_KEY; CODEX_AUTH_FILE='$TMP/nope.json' bash '$GUARD' both"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic:" ]]
  [[ "$output" =~ "openai-codex:" ]]
}

#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/list-gemini-findings.sh"
}

teardown() {
  rm -rf "$TMP"
}

# Build a fake `gh` on PATH that emits canned JSON for each subcommand
# the script invokes (api ... pulls/<#>/comments and api ... issues/<#>/comments).
# Args: <gh-binary-dir> <inline-json-file> <pr-json-file>
_mock_gh() {
  local dir="$1" inline="$2" pr="$3"
  cat > "$dir/gh" <<EOF
#!/bin/bash
# repo view: report a canned repo
if [[ "\$1" == "repo" && "\$2" == "view" ]]; then
  echo "owner/repo"
  exit 0
fi
# api pulls/<#>/comments
if [[ "\$1" == "api" && "\$2" == *"/pulls/"*"/comments" ]]; then
  cat "$inline"
  exit 0
fi
# api issues/<#>/comments
if [[ "\$1" == "api" && "\$2" == *"/issues/"*"/comments" ]]; then
  cat "$pr"
  exit 0
fi
exit 1
EOF
  chmod +x "$dir/gh"
}

@test "_parse_severity recognises high/medium/low/unknown" {
  run bash -c "source '$LIB'; _parse_severity '![high](x.svg) body'"
  [ "$output" = "HIGH" ]
  run bash -c "source '$LIB'; _parse_severity '![medium](x.svg) body'"
  [ "$output" = "MEDIUM" ]
  run bash -c "source '$LIB'; _parse_severity '![low](x.svg) body'"
  [ "$output" = "LOW" ]
  run bash -c "source '$LIB'; _parse_severity 'no marker just text'"
  [ "$output" = "UNKNOWN" ]
}

@test "_parse_severity also matches by URL substring (no badge syntax)" {
  run bash -c "source '$LIB'; _parse_severity 'https://www.gstatic.com/codereviewagent/high-priority.svg here'"
  [ "$output" = "HIGH" ]
}

@test "_summarize strips badge marker and collapses whitespace, max 120 chars" {
  body=$'![medium](https://x/medium-priority.svg)\n\nThis is the\tactual  finding body.\n\nMore.'
  run bash -c "source '$LIB'; _summarize '$body'"
  [[ "$output" != *"![medium]"* ]]
  [[ "$output" != *$'\n'* ]]
  [[ "$output" != *$'\t'* ]]
  [[ "$output" == *"This is the actual finding body."* ]]
}

@test "_summarize truncates at 120 chars" {
  long=$(printf 'x%.0s' {1..200})
  run bash -c "source '$LIB'; _summarize '$long'"
  [ "${#output}" -le 120 ]
}

@test "_emit_finding produces tab-separated 5-column line" {
  run bash -c "source '$LIB'; _emit_finding HIGH INLINE 42 path.md:7 'summary text'"
  [ "$status" -eq 0 ]
  # 5 columns → exactly 4 tabs
  count=$(printf '%s' "$output" | awk -F'\t' '{print NF}')
  [ "$count" -eq 5 ]
}

@test "list_gemini_main usage error when no PR arg" {
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB'"
  [ "$status" -eq 2 ]
}

@test "list_gemini_main returns 0 (clean) when zero gemini comments" {
  echo "[]" > "$TMP/inline.json"
  echo "[]" > "$TMP/pr.json"
  _mock_gh "$TMP" "$TMP/inline.json" "$TMP/pr.json"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB' 99 --repo owner/repo"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_gemini_main emits INLINE finding for gemini inline comment" {
  cat > "$TMP/inline.json" <<'EOF'
[
  {"id": 123, "user": {"login": "gemini-code-assist[bot]"}, "path": "foo.md", "line": 42, "body": "![high](x/high-priority.svg)\n\nReal bug here"},
  {"id": 124, "user": {"login": "some-human"}, "path": "bar.md", "line": 7, "body": "human comment, should be ignored"}
]
EOF
  echo "[]" > "$TMP/pr.json"
  _mock_gh "$TMP" "$TMP/inline.json" "$TMP/pr.json"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB' 99 --repo owner/repo"
  [ "$status" -eq 0 ]
  [[ "$output" == HIGH*INLINE*123*foo.md:42*"Real bug here"* ]]
  [[ "$output" != *"human comment"* ]]
}

@test "list_gemini_main emits PR finding for gemini issue-comment" {
  echo "[]" > "$TMP/inline.json"
  cat > "$TMP/pr.json" <<'EOF'
[
  {"id": 555, "user": {"login": "gemini-code-assist[bot]"}, "body": "![medium](x/medium-priority.svg)\n\nPR summary finding"}
]
EOF
  _mock_gh "$TMP" "$TMP/inline.json" "$TMP/pr.json"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB' 99 --repo owner/repo"
  [ "$status" -eq 0 ]
  # Column shape: severity\tkind\tid\tlocation\tsummary  →  MEDIUM PR 555 PR <summary>
  [[ "$output" == "MEDIUM"$'\t'"PR"$'\t'"555"$'\t'"PR"$'\t'*"PR summary finding"* ]]
}

@test "list_gemini_main infers repo via gh repo view when --repo omitted" {
  cat > "$TMP/inline.json" <<'EOF'
[{"id": 1, "user": {"login": "gemini-code-assist[bot]"}, "path": "a.md", "line": 1, "body": "![low](x/low-priority.svg)\n\nx"}]
EOF
  echo "[]" > "$TMP/pr.json"
  _mock_gh "$TMP" "$TMP/inline.json" "$TMP/pr.json"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB' 99"
  [ "$status" -eq 0 ]
  [[ "$output" == LOW*INLINE* ]]
}

@test "list_gemini_main exits 2 when gh missing" {
  # Force gh genuinely absent regardless of host: empty PATH + absolute bash.
  # (GH Actions runners ship gh in /usr/bin, so /usr/bin:/bin is NOT gh-free.)
  # The gh check is the first validation and uses only shell builtins to reach
  # `return 2`, so no external binary is needed on PATH.
  local empty bash_bin
  empty="$(mktemp -d)"
  bash_bin="$(command -v bash)"
  run env PATH="$empty" "$bash_bin" "$LIB" 99 --repo owner/repo
  rm -rf "$empty"
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == *"gh CLI not on PATH"* ]]
}

@test "first column severity is grep-able for HIGH-only pre-merge gate" {
  cat > "$TMP/inline.json" <<'EOF'
[
  {"id": 1, "user": {"login": "gemini-code-assist[bot]"}, "path": "a", "line": 1, "body": "![high](x/high-priority.svg)\n\nbad"},
  {"id": 2, "user": {"login": "gemini-code-assist[bot]"}, "path": "b", "line": 2, "body": "![low](x/low-priority.svg)\n\nnit"}
]
EOF
  echo "[]" > "$TMP/pr.json"
  _mock_gh "$TMP" "$TMP/inline.json" "$TMP/pr.json"
  run bash -c "PATH='$TMP:/usr/bin:/bin' bash '$LIB' 99 --repo owner/repo | awk -F'\t' '\$1 == \"HIGH\"' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/cost-ledger.sh"
  RUN="$(mktemp -d)"
  export RUN
}
teardown() { rm -rf "$RUN"; }

@test "ledger_append writes one JSONL row per call" {
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"builder\",\"provider\":\"composer\",\"tier\":\"cheap\",\"verdict\":\"approve\"}'"
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"reviewer\",\"provider\":\"gemini\",\"tier\":\"premium\",\"verdict\":\"reject\"}'"
  run bash -c "wc -l < '$RUN/cost-ledger.jsonl'"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
}

@test "ledger_append rejects malformed json" {
  run bash -c "source '$LIB'; ledger_append '$RUN' 'not-json{'"
  [ "$status" -ne 0 ]
}

@test "ledger_append stamps a timestamp field if absent" {
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"builder\",\"provider\":\"composer\"}'"
  run bash -c "jq -r '.ts' '$RUN/cost-ledger.jsonl' | head -1"
  [ -n "$output" ]
  [ "$output" != "null" ]
}

@test "ledger_summary reports calls per provider and per tier" {
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"builder\",\"provider\":\"composer\",\"tier\":\"cheap\",\"verdict\":\"approve\"}'"
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"builder\",\"provider\":\"composer\",\"tier\":\"cheap\",\"verdict\":\"approve\"}'"
  bash -c "source '$LIB'; ledger_append '$RUN' '{\"role\":\"reviewer\",\"provider\":\"gemini\",\"tier\":\"premium\",\"verdict\":\"reject\",\"escalated\":true}'"
  run bash -c "source '$LIB'; ledger_summary '$RUN'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"composer"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" == *"cheap"* ]]
  [[ "$output" == *"premium"* ]]
}

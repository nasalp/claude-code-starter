#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/agent-budget.sh"
  RUN="$(mktemp -d)"
  export RUN
}
teardown() { rm -rf "$RUN"; }

@test "budget_init writes budget.json with zeroed counters and caps" {
  run bash -c "source '$LIB'; budget_init '$RUN'"
  [ "$status" -eq 0 ]
  [ -f "$RUN/budget.json" ]
  run bash -c "jq -r '.counters.iterations' '$RUN/budget.json'"; [ "$output" = "0" ]
  run bash -c "jq -r '.caps.max_iterations' '$RUN/budget.json'"; [ "$output" != "null" ]
}

@test "budget_incr bumps a counter" {
  bash -c "source '$LIB'; budget_init '$RUN'; budget_incr '$RUN' premium_calls; budget_incr '$RUN' premium_calls"
  run bash -c "jq -r '.counters.premium_calls' '$RUN/budget.json'"
  [ "$output" = "2" ]
}

@test "budget_incr adds a cost amount for est_cost_usd" {
  bash -c "source '$LIB'; budget_init '$RUN'; budget_incr '$RUN' est_cost_usd 1.50; budget_incr '$RUN' est_cost_usd 0.50"
  run bash -c "jq -r '.counters.est_cost_usd' '$RUN/budget.json'"
  [ "$output" = "2" ]
}

@test "budget_check returns 0 when budget.json is missing (no caps configured)" {
  # $RUN is a fresh tmpdir with no budget.json (budget_init not called).
  run bash -c "source '$LIB'; budget_check '$RUN'"
  [ "$status" -eq 0 ]
}

@test "budget_check passes when under caps" {
  bash -c "source '$LIB'; budget_init '$RUN'"
  run bash -c "source '$LIB'; budget_check '$RUN'"
  [ "$status" -eq 0 ]
}

@test "budget_check fails and names the cap when iterations exceeded" {
  run bash -c "AGENT_MAX_ITERATIONS=2 bash -c 'source \"$LIB\"; budget_init \"$RUN\"; budget_incr \"$RUN\" iterations; budget_incr \"$RUN\" iterations; budget_incr \"$RUN\" iterations; budget_check \"$RUN\"'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"max_iterations"* ]]
}

@test "env AGENT_MAX_* overrides the configured cap" {
  bash -c "AGENT_MAX_PREMIUM_CALLS=5 bash -c 'source \"$LIB\"; budget_init \"$RUN\"'"
  run bash -c "jq -r '.caps.max_premium_calls' '$RUN/budget.json'"
  [ "$output" = "5" ]
}

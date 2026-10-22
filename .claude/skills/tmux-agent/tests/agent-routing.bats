#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/agent-routing.sh"
}

@test "route_role returns the default provider per role" {
  run bash -c "source '$LIB'; route_role planner";    [ "$output" = "claude" ]
  run bash -c "source '$LIB'; route_role architect";  [ "$output" = "claude" ]
  run bash -c "source '$LIB'; route_role builder";    [ "$output" = "composer" ]
  run bash -c "source '$LIB'; route_role watcher";    [ "$output" = "composer" ]
  run bash -c "source '$LIB'; route_role reviewer";   [ "$output" = "gemini" ]
  run bash -c "source '$LIB'; route_role arbitrator"; [ "$output" = "claude" ]
  run bash -c "source '$LIB'; route_role reconciler"; [ "$output" = "claude" ]
}

@test "route_role honors AGENT_ROUTE_<ROLE> env override" {
  run bash -c "export AGENT_ROUTE_BUILDER=codex; source '$LIB'; route_role builder"
  [ "$output" = "codex" ]
}

@test "route_role env override is case-insensitive on role" {
  run bash -c "export AGENT_ROUTE_REVIEWER=composer; source '$LIB'; route_role reviewer"
  [ "$output" = "composer" ]
}

@test "route_role fails on unknown role" {
  run bash -c "source '$LIB'; route_role frobnicate"
  [ "$status" -ne 0 ]
}

@test "role_tier returns premium for planner, cheap for builder" {
  run bash -c "source '$LIB'; role_tier planner"; [ "$output" = "premium" ]
  run bash -c "source '$LIB'; role_tier builder"; [ "$output" = "cheap" ]
}

@test "role_effort: low for watcher, high for planner; env override wins" {
  run bash -c "source '$LIB'; role_effort watcher"; [ "$output" = "low" ]
  run bash -c "source '$LIB'; role_effort planner"; [ "$output" = "high" ]
  run bash -c "export AGENT_EFFORT_BUILDER=high; source '$LIB'; role_effort builder"
  [ "$output" = "high" ]
}

@test "watcher_fleet is the cheap fleet (composer + gemini-flash), not codex" {
  run bash -c "source '$LIB'; watcher_fleet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"composer"* ]]
  [[ "$output" == *"gemini-flash"* ]]
  [[ "$output" != *"codex"* ]]
}

#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/agent-escalation.sh"
  TMP="$(mktemp -d)"; export TMP
}
teardown() { rm -rf "$TMP"; }

@test "validate_watcher_verdict accepts a well-formed verdict" {
  run bash -c "source '$LIB'; validate_watcher_verdict '{\"verdict\":\"approve\",\"confidence\":0.9,\"reason\":\"clean\"}'"
  [ "$status" -eq 0 ]
}

@test "validate_watcher_verdict rejects a bad enum value" {
  run bash -c "source '$LIB'; validate_watcher_verdict '{\"verdict\":\"maybe\",\"confidence\":0.9,\"reason\":\"x\"}'"
  [ "$status" -ne 0 ]
}

@test "validate_watcher_verdict rejects confidence out of range" {
  run bash -c "source '$LIB'; validate_watcher_verdict '{\"verdict\":\"approve\",\"confidence\":1.4,\"reason\":\"x\"}'"
  [ "$status" -ne 0 ]
}

@test "validate_reviewer_verdict accepts a well-formed verdict with a blocking issue" {
  run bash -c "source '$LIB'; validate_reviewer_verdict '{\"verdict\":\"reject\",\"confidence\":0.8,\"blocking_issues\":[{\"rule\":\"R1\",\"severity\":\"high\",\"description\":\"d\",\"required_change\":\"c\"}]}'"
  [ "$status" -eq 0 ]
}

@test "validate_reviewer_verdict accepts approve with empty blocking_issues" {
  run bash -c "source '$LIB'; validate_reviewer_verdict '{\"verdict\":\"approve\",\"confidence\":0.95,\"blocking_issues\":[]}'"
  [ "$status" -eq 0 ]
}

@test "validate_reviewer_verdict rejects a blocking issue with a bad severity enum" {
  run bash -c "source '$LIB'; validate_reviewer_verdict '{\"verdict\":\"reject\",\"confidence\":0.8,\"blocking_issues\":[{\"rule\":\"R1\",\"severity\":\"sorta-bad\",\"description\":\"d\",\"required_change\":\"c\"}]}'"
  [ "$status" -ne 0 ]
}

@test "validate_reviewer_verdict rejects a blocking issue missing required_change" {
  run bash -c "source '$LIB'; validate_reviewer_verdict '{\"verdict\":\"reject\",\"confidence\":0.8,\"blocking_issues\":[{\"rule\":\"R1\",\"severity\":\"high\",\"description\":\"d\"}]}'"
  [ "$status" -ne 0 ]
}

@test "validate_watcher_verdict rejects violated_rules that is not an array of strings" {
  run bash -c "source '$LIB'; validate_watcher_verdict '{\"verdict\":\"reject\",\"confidence\":0.5,\"reason\":\"x\",\"violated_rules\":[1,2]}'"
  [ "$status" -ne 0 ]
}

@test "should_escalate: verdict=escalate escalates" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"escalate\",\"confidence\":0.9,\"reason\":\"x\"}' '' 0"
  [[ "$output" == escalate* ]]
}

@test "should_escalate: reject with no critical path and high confidence below 1 round stays ok" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"reject\",\"confidence\":0.95,\"reason\":\"x\"}' 'src/Foo.java' 0"
  [[ "$output" == ok* ]]
}

@test "should_escalate: low confidence escalates" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":0.4,\"reason\":\"x\"}' 'src/Foo.java' 0"
  [[ "$output" == escalate* ]]
  [[ "$output" == *"confidence"* ]]
}

@test "should_escalate: sensitive path escalates regardless of verdict" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":0.99,\"reason\":\"x\"}' 'src/main/db/migration/V2__x.sql' 0"
  [[ "$output" == escalate* ]]
  [[ "$output" == *"sensitive"* ]]
}

@test "should_escalate: repeat_count at/over threshold escalates" {
  run bash -c "AGENT_ESCALATE_AFTER_N=3 bash -c 'source \"$LIB\"; should_escalate \"{\\\"verdict\\\":\\\"approve\\\",\\\"confidence\\\":0.99,\\\"reason\\\":\\\"x\\\"}\" \"src/Foo.java\" 3'"
  [[ "$output" == escalate* ]]
  [[ "$output" == *"repeat"* ]]
}

@test "should_escalate: sensitive path with spaces in filename still matches" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":0.99,\"reason\":\"x\"}' 'src/main/auth/My Login Handler.java' 0"
  [[ "$output" == escalate* ]]
  [[ "$output" == *"sensitive"* ]]
}

@test "should_escalate: ROOT-level sensitive path (no dir prefix) still escalates" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":0.99,\"reason\":\"x\"}' 'V2__add_table.sql' 0"
  [[ "$output" == escalate* ]]
  [[ "$output" == *"sensitive"* ]]
}

@test "should_escalate: root-level security/ dir still escalates" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":0.99,\"reason\":\"x\"}' 'security/Config.java' 0"
  [[ "$output" == escalate* ]]
}

@test "should_escalate: non-numeric confidence is handled safely (no crash, no false escalate)" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"approve\",\"confidence\":\"oops\",\"reason\":\"x\"}' 'src/Foo.java' 0"
  [ "$status" -eq 0 ]
  [[ "$output" == ok* ]]
}

@test "should_escalate: reject with critical sensitive change escalates" {
  run bash -c "source '$LIB'; should_escalate '{\"verdict\":\"reject\",\"confidence\":0.9,\"reason\":\"x\"}' 'src/auth/Login.java' 0"
  [[ "$output" == escalate* ]]
}

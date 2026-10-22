#!/usr/bin/env bats
# Unit tests for the pre-admin-merge-gate predicate functions.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/orchestration/pre-admin-merge-gate.sh"
    # shellcheck source=/dev/null
    source "$SCRIPT"
    TMP="$(mktemp -d "${BATS_TMPDIR}/pamg-XXXXXX")"
}

teardown() { rm -rf "$TMP"; }

@test "usage exits 2 with no args" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "_diff_touches_ui true for a tsx page diff" {
    run _diff_touches_ui $'+++ b/frontend/src/app/pages/foo.tsx\n+code'
    [ "$status" -eq 0 ]
}

@test "_diff_touches_ui false for a backend java diff" {
    run _diff_touches_ui $'+++ b/src/main/java/Foo.java\n+code'
    [ "$status" -eq 1 ]
}

@test "_local_build_green true when a BUILD SUCCESS tail exists" {
    echo "[INFO] BUILD SUCCESS" > "$TMP/verify.log"
    run _local_build_green "$TMP" "deadbeef0"
    [ "$status" -eq 0 ]
}

@test "_local_build_green false when no success marker" {
    echo "[INFO] BUILD FAILURE" > "$TMP/verify.log"
    run _local_build_green "$TMP" "deadbeef0"
    [ "$status" -eq 1 ]
}

@test "_assessor_tally counts 3 of 3 approve" {
    printf 'x\nVERDICT: APPROVE\n' > "$TMP/verdict-a.md"
    printf 'x\nVERDICT: APPROVE\n' > "$TMP/verdict-b.md"
    printf 'x\nVERDICT: APPROVE\n' > "$TMP/verdict-c.md"
    run _assessor_tally "$TMP"
    [ "$output" = "3 3" ]
}

@test "_assessor_tally surfaces a reject as approve<total" {
    printf 'VERDICT: APPROVE\n' > "$TMP/verdict-a.md"
    printf 'VERDICT: APPROVE\n' > "$TMP/verdict-b.md"
    printf 'VERDICT: REJECT\n'  > "$TMP/verdict-c.md"
    run _assessor_tally "$TMP"
    [ "$output" = "2 3" ]
}

@test "_body_has_screenshot true for user-attachments url" {
    run _body_has_screenshot "see ![x](https://github.com/user-attachments/assets/a.png)"
    [ "$status" -eq 0 ]
}

@test "_body_has_screenshot false for no image" {
    run _body_has_screenshot "no image here"
    [ "$status" -eq 1 ]
}

@test "_diff_adds_suppression true for added @SuppressWarnings" {
    run _diff_adds_suppression $'+    @SuppressWarnings("NullAway")'
    [ "$status" -eq 0 ]
}

@test "_diff_adds_suppression true for non-teardown || true" {
    run _diff_adds_suppression $'+  ./mvnw verify || true'
    [ "$status" -eq 0 ]
}

@test "_diff_adds_suppression false for teardown || true" {
    run _diff_adds_suppression $'+  docker stop c || true'
    [ "$status" -eq 1 ]
}

@test "_diff_adds_suppression false for clean added line" {
    run _diff_adds_suppression $'+  return service.compute();'
    [ "$status" -eq 1 ]
}

@test "_body_has_issue_trail true with plan + production checklist refs" {
    run _body_has_issue_trail "Plan-of-work #41. Production-checklist #42."
    [ "$status" -eq 0 ]
}

@test "_body_has_issue_trail false when checklist ref missing" {
    run _body_has_issue_trail "Plan-of-work #41 only"
    [ "$status" -eq 1 ]
}

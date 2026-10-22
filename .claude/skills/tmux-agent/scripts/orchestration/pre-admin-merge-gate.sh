#!/usr/bin/env bash
# Deterministic pre-merge gate for tmux-agent --admin merges.
# Fails closed: exits non-zero if any guardrail is unproven.
# See .claude/rules/orchestration-determinism-and-issue-trail.md
set -euo pipefail

# Print usage and exit 2.
_usage() {
    echo "usage: pre-admin-merge-gate.sh <PR_NUMBER> <RUN_DIR> [--repo OWNER/REPO]" >&2
    echo "  RUN_DIR must contain: verify tail (verify*.log), assessor verdicts (verdict-*.md or 5xx[abc].out)" >&2
    exit 2
}

# Emit a blocking finding to stderr.
_fail() { echo "GATE-FAIL: $1" >&2; }

# True when the PR diff (3-dot merge-base) touches a UI source file.
_diff_touches_ui() {
    local diff="$1"
    grep -qE '\.(tsx|vue|svelte)$' <<<"$diff" \
        && grep -qE '/(pages|components|app)/' <<<"$diff"
}

# True when a captured build-success tail for HEAD_SHA exists in RUN_DIR.
_local_build_green() {
    local run_dir="$1" head_sha="$2"
    local f
    for f in "$run_dir"/verify*.log "$run_dir"/*verify*.log; do
        [[ -f "$f" ]] || continue
        grep -qE 'BUILD SUCCESS|Tests run: [0-9]+, Failures: 0|Test Files .*passed' "$f" || continue
        # accept when the tail names the PR head sha, or no sha is recorded (single-run dirs)
        if ! grep -qE '[0-9a-f]{7,40}' "$f" || grep -q "${head_sha:0:9}" "$f"; then
            return 0
        fi
    done
    return 1
}

# Count APPROVE / total among assessor verdict files; echoes "approve total".
_assessor_tally() {
    local run_dir="$1"
    local approve=0 total=0 v last
    shopt -s nullglob
    for v in "$run_dir"/verdict-*.md "$run_dir"/verdicts-*/*.md "$run_dir"/5[0-9][0-9][abc].out; do
        [[ -f "$v" ]] || continue
        last="$(grep -E '^VERDICT:' "$v" | tail -1 || true)"
        [[ -n "$last" ]] || continue
        total=$((total + 1))
        grep -qE '^VERDICT:[[:space:]]*APPROVE' <<<"$last" && approve=$((approve + 1))
    done
    shopt -u nullglob
    echo "$approve $total"
}

# True if the PR body contains a GitHub-hosted screenshot URL.
_body_has_screenshot() {
    grep -qE 'https://(github\.com/user-attachments|user-images\.githubusercontent\.com|github\.githubassets\.com)/' <<<"$1"
}

# True if the diff ADDS a banned suppression/silencer.
_diff_adds_suppression() {
    local diff="$1"
    # added lines only (leading +, not +++ header)
    local added
    added="$(grep -E '^\+[^+]' <<<"$diff" || true)"
    grep -qE '@Disabled|@SuppressWarnings|NOPMD|CHECKSTYLE:OFF|continue-on-error' <<<"$added" && return 0
    # || true not preceded by a teardown verb (per no-silent-pass-in-ci.md)
    grep -E '\|\|[[:space:]]*true' <<<"$added" \
        | grep -vqE '\b(stop|kill|rm|rmdir|down|prune|clean|clear|umount|unmount|destroy|terminate|disconnect|close|shutdown|logout|unset)\b' \
        && return 0
    return 1
}

# True if PR body references both the consensus-plan and production-checklist issues.
_body_has_issue_trail() {
    grep -qiE 'plan-of-work|consensus plan|#[0-9]+' <<<"$1" \
        && grep -qiE 'production[- ]checklist|production[- ]readiness' <<<"$1"
}

main() {
    [[ $# -ge 2 ]] || _usage
    local pr="$1" run_dir="$2"; shift 2
    local repo_arg=()
    [[ "${1:-}" == "--repo" && -n "${2:-}" ]] && repo_arg=(--repo "$2")
    [[ -d "$run_dir" ]] || { _fail "RUN_DIR not found: $run_dir"; exit 1; }

    local failures=0
    local body diff head_sha
    body="$(gh pr view "$pr" "${repo_arg[@]}" --json body --jq .body 2>/dev/null || true)"
    head_sha="$(gh pr view "$pr" "${repo_arg[@]}" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
    diff="$(gh pr diff "$pr" "${repo_arg[@]}" 2>/dev/null || true)"
    [[ -n "$body$diff" ]] || { _fail "could not read PR #$pr (gh auth?)"; exit 1; }
    [[ -n "$head_sha" ]] || { _fail "could not resolve HEAD SHA for PR #$pr"; exit 1; }

    _local_build_green "$run_dir" "$head_sha" \
        || { _fail "no green local-build tail for head ${head_sha:0:9} in $run_dir"; failures=$((failures + 1)); }

    local min_assessors="${TMUX_AGENT_ASSESSOR_MIN:-3}"
    read -r approve total < <(_assessor_tally "$run_dir")
    if [[ "$total" -lt "$min_assessors" || "$approve" -lt "$min_assessors" || "$approve" -ne "$total" ]]; then
        _fail "assessor consensus not unanimous: approve=$approve total=$total (need ${min_assessors}/${min_assessors})"; failures=$((failures + 1))
    fi

    if _diff_touches_ui "$diff"; then
        _body_has_screenshot "$body" \
            || { _fail "UI diff but no GitHub-hosted screenshot URL in PR body"; failures=$((failures + 1)); }
    fi

    if _diff_adds_suppression "$diff"; then
        _fail "diff adds a banned suppression/silencer (@Disabled/@SuppressWarnings/NOPMD/continue-on-error/|| true)"; failures=$((failures + 1))
    fi

    _body_has_issue_trail "$body" \
        || { _fail "PR body missing consensus-plan + production-checklist issue references"; failures=$((failures + 1)); }

    if [[ "$failures" -gt 0 ]]; then
        echo "PRE-MERGE GATE: FAIL ($failures blocking) — do NOT merge PR #$pr" >&2
        exit 1
    fi
    echo "PRE-MERGE GATE: PASS — PR #$pr cleared (build green, 3/3 APPROVE, proof present, no suppressions, issue trail present)"
}

# Only run main when executed directly, so bats can source + unit-test functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

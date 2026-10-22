#!/usr/bin/env bash
# pre-push-proof-guard.sh — block builder pushes that lack proof or add disabled tests
#
# Usage (run from within the builder worktree before every `git push`):
#   bash .claude/skills/tmux-agent/scripts/pre-push-proof-guard.sh [HEAD_REF] [BASE_REF]
#
# HEAD_REF defaults to HEAD; BASE_REF defaults to the branch's upstream tracking ref.
# Exit codes:
#   0 — push is allowed
#   1 — push REJECTED; printed reason explains why
#   2 — usage error
#
# Two checks (both must pass):
#   1. Proof-tail: HEAD commit body MUST contain ONE of:
#      - A canonical success marker (BUILD SUCCESS / Tests run: N, Failures: 0 / Test Files .* passed)
#      - A reference to a `docs/proof/phase-*.md` file that exists in the commit
#      - An explicit `BROKEN-PRE-EXISTING:` annotation
#      - An explicit `DEFER:` block naming the skipped gate AND the substitute that ran
#   2. No-skip-as-progress: the BASE..HEAD diff MUST NOT introduce any of:
#      test.skip, it.skip, describe.skip, test.describe.skip, xit, xdescribe,
#      @Disabled, -DskipTests, --no-verify, continue-on-error: true
#      UNLESS the added line carries the trailing comment `# allow-skip: <ticket>`
#
# Operationalises the consensus from the 2026-05-31 3-reviewer review of the 217 run.

set -uo pipefail

HEAD_REF="${1:-HEAD}"
BASE_REF="${2:-}"

if [[ -z "$BASE_REF" ]]; then
  BASE_REF=$(git rev-parse --abbrev-ref --symbolic-full-name "$HEAD_REF@{u}" 2>/dev/null || echo "")
fi

if [[ -z "$BASE_REF" ]]; then
  echo "ERROR: cannot resolve upstream for $HEAD_REF; pass BASE_REF explicitly" >&2
  exit 2
fi

# ----- Check 1: proof-tail in the head commit body -----

_check_proof_tail() {
  local body
  body=$(git log -1 --format=%B "$HEAD_REF" 2>/dev/null) || return 1

  # 1a. Canonical success marker
  if grep -qE 'BUILD SUCCESS|Tests run: [0-9]+, Failures: 0|Test Files .* passed|mutation score: [0-9]+' <<<"$body"; then
    return 0
  fi

  # 1b. docs/proof/phase-*.md reference whose file exists in the commit
  local proof_ref
  proof_ref=$(grep -oE 'docs/proof/phase-[A-Za-z0-9_.-]+\.md' <<<"$body" | head -1)
  if [[ -n "$proof_ref" ]]; then
    if git ls-tree -r --name-only "$HEAD_REF" -- "$proof_ref" | grep -q .; then
      return 0
    fi
    echo "REJECT: commit body references $proof_ref but the file is not in this commit" >&2
    return 1
  fi

  # 1c. Explicit BROKEN-PRE-EXISTING annotation
  if grep -qE '^BROKEN-PRE-EXISTING:' <<<"$body"; then
    return 0
  fi

  # 1d. Explicit DEFER block naming the substitute that ran
  if grep -qE '^DEFER:' <<<"$body"; then
    return 0
  fi

  echo "REJECT: HEAD commit body lacks proof-tail." >&2
  echo "  Need ONE of: canonical success marker, docs/proof/phase-*.md reference," >&2
  echo "    BROKEN-PRE-EXISTING: annotation, or DEFER: block." >&2
  echo "  See ~/.claude/rules/ci-budget-discipline.md §4a." >&2
  return 1
}

# ----- Check 2: no skip-as-progress in the diff -----

_check_no_skip_as_progress() {
  local added
  added=$(git diff "$BASE_REF...$HEAD_REF" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.java' '*.kt' '*.py' '*.go' '*.yml' '*.yaml' 2>/dev/null \
            | grep -E '^\+' | grep -vE '^\+\+\+') || true

  if [[ -z "$added" ]]; then
    return 0
  fi

  local pattern violations
  # Patterns that are forbidden as "additions" without explicit allow-skip comment.
  pattern='test\.skip\(|it\.skip\(|describe\.skip\(|test\.describe\.skip\(|\bxit\(|\bxdescribe\(|@Disabled\b|-DskipTests\b|--no-verify\b|continue-on-error:\s*true'

  violations=$(grep -nE "$pattern" <<<"$added" | grep -vE 'allow-skip:' || true)

  if [[ -z "$violations" ]]; then
    return 0
  fi

  echo "REJECT: new lines add skip-as-progress patterns:" >&2
  echo "$violations" | sed 's/^/  /' >&2
  echo "  See ~/.claude/rules/no-deferred-work.md — skips need '# allow-skip: <ticket>'." >&2
  return 1
}

# ----- Run both checks; aggregate verdict -----

_main() {
  local rc=0
  _check_proof_tail || rc=1
  _check_no_skip_as_progress || rc=1
  if (( rc == 0 )); then
    echo "pre-push-proof-guard: OK ($HEAD_REF over $BASE_REF)"
  fi
  return $rc
}

# Allow direct invocation; allow sourcing for tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _main
fi

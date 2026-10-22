# phase 6 ship deploy

# Phase 6 — ship + deploy babysit

## 6.0 — Gemini-code-assist comments are a HARD pre-merge gate (MANDATORY)

**Before any merge step (auto, admin, or manual), every open
`gemini-code-assist` finding on the PR MUST be addressed.** No
exceptions. "I'll fix it in a follow-up" is FORBIDDEN per
`no-deferred-work.md`. Findings are addressed in the SAME PR or the PR
does not merge.

### Why this is mandatory

Gemini-code-assist surfaces real bugs the parent orchestrator + the 3
Phase 4½ watchers consistently miss:

- Shell-portability bugs (macOS BSD `timeout` absence, `cut` vs `awk`
  on `: ` separators, regex anchors mismatching grep's output line
  shape).
- Race conditions in cache-guard logic (size-decrease deadlock).
- ERE vs BRE confusion in CI workflow filters.
- Off-by-one in `_should_audit` bookkeeping.

Calibration: across four stacked harness PRs, gemini flagged 11 findings; 3 were `HIGH` (the size-decrease deadlock
in `_should_audit`, the `timeout` missing on macOS, the RFC-7230 colon
parsing). All three would have shipped silently if gemini was treated
as "advisory." The pattern: human + 3 watchers all missed them; gemini
caught them.

### How to address them (in order)

**Step 1 — enumerate findings via the canonical script** (BATS-covered,
shellcheck-clean; merges inline + PR-level comments, parses severity
from the gemini badge syntax):

```bash
scripts/list-gemini-findings.sh <PR#> --repo <owner/repo>
```

Output format (one finding per line, tab-separated):

```
<severity>\t<kind>\t<id>\t<location>\t<summary>
```

- `severity` ∈ {`HIGH`, `MEDIUM`, `LOW`, `UNKNOWN`}
- `kind` ∈ {`INLINE`, `PR`}
- `location`: `<path>:<line>` for inline, `PR` for PR-level
- `summary`: first 120 chars, single-line

Exit codes: `0` = success (output empty when clean), `2` = usage error.

**Step 2 — gate on `HIGH` count** (the cheap pre-merge check):

```bash
high_count=$(scripts/list-gemini-findings.sh "$PR" --repo "$REPO" \
              | awk -F'\t' '$1 == "HIGH"' | wc -l | tr -d ' ')
if (( high_count > 0 )); then
  echo "BLOCKED: $high_count HIGH gemini findings unresolved"
  scripts/list-gemini-findings.sh "$PR" --repo "$REPO" | awk -F'\t' '$1 == "HIGH"'
  exit 1
fi
```

**Step 3 — classify by severity** (the rest):

| Severity | Required action |
|---|---|
| `HIGH` | MUST fix this PR. No deferral, no exception. |
| `MEDIUM` | MUST fix this PR unless explicit deferral approved by USER in writing on the PR thread. |
| `LOW` | SHOULD fix this PR. May defer with a documented follow-up issue. |

**Step 4 — fix in the same branch.** New commit per finding cluster
(don't squash before review — gemini re-reviews on push).

**Step 5 — reply to each finding with the fix commit SHA:**

```bash
gh api repos/<owner>/<repo>/pulls/<PR#>/comments/<id>/replies \
  -f body="Fixed in <SHA>: <one-line description>"
```

Or, if the reply API fails (rate limit, etc.), use a PR-level fallback:

```bash
gh pr comment <PR#> --body "Re: gemini comment <id> — fixed in <SHA>."
```

**Step 6 — re-run step 1** to confirm zero `HIGH` and the count of
`MEDIUM` / `LOW` matches expected.

### What counts as "addressed"

- **Code change** that resolves the finding → cite the SHA.
- **Documented decision** to NOT change, with reasoning, posted as a
  reply to gemini's comment → still requires USER approval in the PR
  thread.
- **`HIGH` findings cannot be deferred.** Period.

### What does NOT count as addressed

- Silence (the finding sits open while you merge).
- "Will fix in follow-up #999" without the follow-up issue actually
  existing AND a USER ack.
- A reply that argues with gemini but doesn't change behavior, when
  gemini's point is technically correct.
- Squash-merging before gemini has a chance to re-review the fix
  commits.

## 6.1 — Merge mechanics

After §6.0 is clean (every gemini finding addressed):

- Squash-merge with `gh pr merge --squash --delete-branch`.
- **`--auto`** is the default — let CI gate green before merging.
- **`--admin`** ONLY if the USER explicitly authorizes a bypass AND
  the failure is acceptable (failure is genuinely
  implementation-orthogonal, pre-existing, documented in
  `/tmp/<repo>-blockers.md` or equivalent).

### Pre-merge checklist (paste into PR body before flipping ready-for-review)

```text
- [ ] All gemini-code-assist findings addressed (commits cited per comment)
- [ ] All 3 Phase 5 assessors APPROVE on file
- [ ] Local verify gate green; tail pasted in PR body
- [ ] `gh pr checks <#>` shows zero red, including non-required checks
- [ ] Per-phase proof files committed under `docs/proof/phase-<X>-*.md`
- [ ] Concurrency group set on long-running CI workflows (no fan-out on push)
```

## 6.2 — Watch the main CI run

After merge, follow the CI run on `main`:

```bash
gh run watch $(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
```

If `main` goes red because the merge interacted badly with a
concurrent merge (rare but real), follow the recovery
protocol immediately — revert or fix in `main`, do not "fix forward"
through a chain of red commits.

## 6.3 — Deploy approval gate

Recognize WHICH mechanism the repo uses (some repos use both):

- **GitHub Environments** → `pending_deployments` API + POST approve:

  ```bash
  RUN_ID=$(gh run list --branch main --workflow deploy --limit 1 --json databaseId --jq '.[0].databaseId')
  gh api repos/<owner>/<repo>/actions/runs/$RUN_ID/pending_deployments \
    --method POST --field environment_ids[]=<env-id> --field state=approved --field comment="auto-approve from orchestrator"
  ```

- **`trstringer/manual-approval@v1`** → an issue is created; the
  approver comments `approved` / `approve` / `lgtm` / `yes`:

  ```bash
  gh issue comment <approval-issue#> --body "approved"
  ```

The orchestrator's auto-approver MUST handle BOTH. Detect which is
used by inspecting the deploy workflow's `jobs.<job>.environment` (GH
Environments) vs `uses: trstringer/manual-approval` (action-based).

## 6.4 — Post-deploy verification

After `PROD_LIVE`:

1. Hit a real prod health URL if one exists (`/actuator/health`,
   `/health`, `/api/health`, project-specific).
2. Confirm to the USER with:
   - The merge SHA.
   - The deploy job URL.
   - The HTTP status from the health check (and the response body if
     short).
   - The gemini finding-resolution summary (number of findings, all
     addressed).

Format:

```
✅ PROD_LIVE
   merge:  <sha>  (PR #<num>)
   deploy: <url>
   health: 200 OK ({"status": "UP"})
   gemini: 5 findings, all addressed (3 HIGH, 2 MEDIUM)
```

## 6.5 — Calibration

This phase was hardened after a chain of four stacked PRs. The original phase-6 doc treated gemini as
advisory. Across 4 PRs, 11 gemini findings landed; 3 were `HIGH`
bugs (size-decrease deadlock, missing `timeout`, RFC-7230 colon
parsing) that the 3 Phase 4½ watchers + the parent orchestrator all
missed. Treating gemini as a hard gate is the structural fix; the
honesty markers in `no-deferred-work.md` already preclude "I'll fix
it later" framing.

## Cross-references

- `.claude/rules/no-deferred-work.md` — partner. "Will fix gemini
  finding in follow-up" without an actual follow-up issue is the
  deferred-as-done anti-pattern.
- `.claude/rules/ai-generated-config-security.md` — gemini
  frequently catches the 6 config-security classes; treat its config
  findings with extra weight.
- `.claude/skills/tmux-agent/docs/phase-5-assessor-consensus.md` —
  the 3 human/assessor APPROVE gate runs alongside gemini. Both must
  be clean to merge.

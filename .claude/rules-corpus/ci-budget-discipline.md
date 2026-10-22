---
topic: process.ci
name: CI budget + PR discipline
description: Verify locally first, batch fixes, push once, use draft PRs for in-flight work, and never mark a PR ready for review without proof of a local green build.
type: rule
priority: CRITICAL
---

# CI Budget + PR Discipline

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

**Burning CI budget through push-per-commit, granular speculative PRs, or skipping local verification is UNACCEPTABLE.** Every push MUST be preceded by green local build. Every in-flight branch needing origin (collaboration, tool needing remote ref, visibility) goes up as **draft PR**. Draft PR flipped to ready-for-review **only** after local canonical build green AND changes reviewable as coherent unit.

Named failure mode: pushing every commit, watching CI ~5 min, pushing fix, watching again — "push-and-pray" loop burning paid quota to discover what local build catches free.

## What is required

### 1. Local verification before EVERY push

Before any `git push` — including reviewer-fix follow-ups, "trivial" docs commits, rebases — project canonical local verification gate MUST exit 0.

```bash
scripts/verify-like-ci.sh          # canonical — matches CI exactly
```

No such script → equivalent is whatever `.github/workflows/*.yml` runs against merge-target branch. **No flags, no shortcuts.** Forbidden as pre-push gate:

- `mvn test -pl <module>` (Surefire only, no Failsafe, no static analysis)
- `mvn verify -pl <module> -am` (doesn't build downstream consumers)
- `mvn -Pfast verify` / `pnpm test --skip-build` (skips analyzers CI enforces)
- `pytest -k <name>` / `go test ./pkg/...` (subset; misses sibling-package compile breaks)

Single-module shortcut = dev-iteration aid, not pre-push gate.

### 2. Batch fixes into single pushes

Before pushing, ask: "other things I'm about to fix in next 30 min?" If yes, hold push, do them all, push once.

**Forbidden push pattern:** Push fix #1 → CI → reviewer notes something → push fix #2 → CI → fix #2 broke something → push fix #3 → CI. **Three CI runs, one PR.**

**Required:** Collect all fixes locally → `scripts/verify-like-ci.sh` green → push once. **One CI run.**

When genuinely don't know whether more fixes coming (reviewer actively reading diff), wait. Pushing speculatively to "show responsiveness" = push-and-pray with extra steps.

### 3. Draft PR by default for in-flight work

Branch needs origin before merge-ready:

- Open as **draft PR** (`gh pr create --draft`).
- Draft state = contract "diff visible, but not asking for human attention yet."
- Draft PR runs only gates repo configures for drafts — if CI matrix runs everything on drafts too, that's bug to fix, not draft state to skip.

**Forbidden:** opening non-draft PR before diff reviewable. "Ready for review" PR with red CI = request for attention you cannot honor.

### 4. Flip to ready-for-review only with PROOF of local green

PR moves `Draft` → `Ready for review` only when you can paste, in PR body or comment, tail of local verification run:

```text
$ scripts/verify-like-ci.sh
... [INFO] BUILD SUCCESS
... Tests run: 246, Failures: 0, Errors: 0, Skipped: 0
```

Same proof-of-work discipline as `common/proof-of-work.md`. "I'm pretty sure it builds" not proof; build output is.

Local build failing and don't know why → **keep PR in draft**. Investigate locally. Do not push to use CI as debugger.

### 4a. Every individual push needs captured proof, not just ready-for-review flip

Ready-for-review flip = LAST gate, not only one. Every individual `git push` to draft branch ALSO needs local-build tail captured before it leaves laptop. Acceptable carriers:

1. Commit body of head commit, containing canonical success marker(s) — `[INFO] BUILD SUCCESS`, `Tests run: N, Failures: 0`, `Test Files X passed (X)`, `mutation score: Y%`, whichever line CI uses as verdict.
2. `docs/proof/phase-*.md` file referenced from commit body, containing same tail.
3. Explicit deferral note in commit body naming which gate skipped locally and why, with substitute that WAS run (e.g. "Stryker deferred to CI — local laptop OOM on worker pool; ran vitest + verified mutation config unchanged from last green run").

Draft push with NONE of those three = push-and-pray pattern this rule prevents. Reviewers (and watcher agents) MUST reject draft commit whose body empty or asserts "tests pass" without quoting output.

### 5. Cancel in-progress runs you're about to obsolete

Know next commit will obsolete in-flight CI run (found bug, switching approach):

```bash
gh run list --branch <branch> --status in_progress --json databaseId,name
gh run cancel <run-id>
```

Most valuable when in-progress run includes long job (PIT mutation, full E2E grid, OWASP scan). 30-min job cancelled at minute 5 saves 25 min; left to finish saves 0.

Also: every long-running workflow MUST have `concurrency: { group: ..., cancel-in-progress: true }` so push-N-times-in-M-minutes doesn't fan out into N concurrent runs.

### 6. PR granularity: cohesive, not chronological

PR = one coherent change reviewable as one unit. Splitting one logical change into 5 PRs ("PR 1 interface, PR 2 impl, PR 3 wire, PR 4 test, PR 5 delete old") burns 5× CI cycles + 5× reviewer context-load.

**Acceptable splits:**

- Independently-deployable slices (spec calls out: "Phase 1 schema migration; Phase 2 code that uses it").
- Mechanical refactors separated from behavioral changes ("PR A: rename only; PR B: behavior change").
- Size budget in `git-workflow.md` (target <400 LOC, max 800 LOC) — splitting 1200 lines into 2 fine; splitting 200 lines into 4 = theatre.

In doubt: one PR per behavior change, not one PR per commit.

## What is forbidden

| Anti-pattern | Why it's banned |
|---|---|
| Pushing without `scripts/verify-like-ci.sh` exit 0 | Discovers in CI what local verify catches free |
| Push-and-pray (push commit, watch CI, push fix, repeat) | Each iteration burns full CI matrix |
| Opening non-draft PR with red CI | Asks reviewers to wait while you fix your own breakage |
| Flipping draft → ready without pasting local build proof | Re-runs CI as "proof"; evidence-shifting, not proof |
| Bumping CI timeout instead of fixing underlying slowness | Turns 30-min waste into 90-min waste |
| Re-running CI "to make sure" when nothing changed | If you didn't push, CI didn't change |
| Splitting 200-line cohesive change into 4 PRs "for reviewability" | 4 PRs = 4 CI cycles = 4 reviewer context-loads for one idea |
| Letting obsolete in-progress run finish when next push obsoletes it | Pure quota burn |

## What is allowed

- Pushing single commit fixing typo in markdown file without full verify gate, IF project gate has markdown-only fast-path CI matches. Otherwise, run gate.
- Multiple PRs for genuinely-independent work on different branches.
- Draft PRs sitting open hours or days while local work continues — draft state working as intended.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/ci-budget-discipline.md`

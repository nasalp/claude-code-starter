# phase 5 assessor consensus

# Phase 5 — assessor-consensus (3 fresh agents)

After the builder pushes the PR, spawn 3 independent assessor agents.
Each gets:

- The PR URL.
- The locked decisions table from Phase 1.
- The CHECKLIST from Phase 1 + the builder's `checklist-status.md`.
- The same rules + skills the builder used.
- A directive: "produce APPROVE or REJECT. For each checklist row, RE-RUN
  the PROOF command yourself and quote your output. Do NOT trust the
  builder's `✓`. Report ≥ 5 cited findings beyond the checklist (rules
  audit, security review, hidden-test review)."

The assessors run independently. Compare verdicts:

- **All 3 APPROVE** → proceed to Phase 6.
- **Any 1 REJECT** → run the multi-round convergence loop below (do NOT
  immediately surface to user as a binary choice — the loop usually
  converges within 2 rounds).

Reuse the `santa-method` skill if helpful — it covers the convergence loop.

## Multi-round assessor convergence (mandatory when any REJECT)

A single-round vote is not the contract; **consensus** is. When N of 3
APPROVE and (3-N) REJECT, run this loop:

1. **Read every REJECT verdict in full** — do not stop at the summary line.
   Each REJECT carries one or more `## Check X: FAIL` rows with file:line
   evidence. Triage them:
   - **Real bug** (test gap, helper bypass, spec drift, etc.) → fix it.
   - **False positive** (assessor misread the code / spec / tests) → write
     a one-line rebuttal in the PR body AND append it verbatim under a
     `## Standing rebuttals` section in `$RUN_DIR/assessor-brief.md` so
     the next round's fresh assessors read it. Fresh assessors have no
     memory of prior rounds; an unwritten rebuttal will reliably produce
     the same false-positive REJECT next round (a deadlock the loop must
     prevent). Do NOT alter the code to placate an incorrect finding.
   - **Scope question** (legitimate finding outside the locked plan) →
     escalate to user; do NOT silently expand scope.

2. **Inject a focused corrective commit** for every "Real bug" finding.
   Each corrective commit:
   - Is a normal phase commit (not a squash-fix-up).
   - Cites the assessor verdict in the commit body
     (`Resolves assessor consensus REJECT findings on PR #N`).
   - Carries its own per-phase proof artifact per the Phase 4 table.
   - Runs the local gate to green BEFORE push.

3. **Re-spawn 3 FRESH assessor agents** (new contexts, new files
   `assessor-{d,e,f}.md`). Do NOT re-prompt the original ones — they
   have stale state. Use the same brief, point at the same PR.

4. **Hard cap: 3 rounds.** If round 2 has any REJECT → repeat the loop
   ONCE more (round 3). If round 3 still has any REJECT, the orchestrator
   MUST halt the loop, post a summary of the unresolved findings as a PR
   comment, and surface to the user for manual re-scoping or override.
   Continuing past round 3 burns API tokens against a process that has
   already failed to converge — the work is off-plan and a fresh look
   from a human is the right next step. The cap also bounds worst-case
   cost at `3 rounds × 3 assessors × Opus` ≈ predictable budget.

5. **Only "ALL 3 APPROVE in the same round" counts as consensus.**
   "2 APPROVE this round + 1 APPROVE last round" does NOT count —
   the round-1 APPROVE was issued against stale code.

### Why fresh agents per round

Subagent contexts accumulate. An assessor that issued REJECT round 1
will read the corrective commit but still carry the "I just said REJECT
to this PR" prior. Fresh contexts give an honest second look.

### File layout in `$RUN_DIR`

```
$RUN_DIR/
├── assessor-brief.md              # single brief, same per round
├── assessor-a.md                  # round 1
├── assessor-b.md                  # round 1
├── assessor-c.md                  # round 1
├── assessor-d.md                  # round 2 (fresh contexts)
├── assessor-e.md                  # round 2
├── assessor-f.md                  # round 2
├── ...                            # round 3 if needed: g/h/i, etc.
```

Each round increments the suffix family; no overwriting. The orchestrator
can audit the convergence trail in `git log` of the PR (corrective
commits between rounds) and in the `assessor-*` files.


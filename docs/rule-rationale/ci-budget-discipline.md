# Rationale — ci-budget-discipline.md

## Interaction with related rules

- `no-deferred-work.md` — partner. CI-budget pressure must NOT push you toward "skip the slow gate, ship unverified." The honest move is to make the gate fast (incremental mode, scoping), not to silence it.
- `no-silent-pass-in-ci.md` — partner. "Save CI minutes by adding `continue-on-error: true`" is forbidden — that's silencing the gate, not conserving its budget.
- `git-workflow.md` Pre-Push Verification section — this rule tightens it to the full-reactor canonical gate and adds the draft-PR mandate.
- `common/proof-of-work.md` — every claim that "the build is green" must be backed by quotable output. Flipping a PR to ready-for-review IS a claim of greenness.

## Clause 4a calibration

The per-push-proof clause (4a) was added 2026-05-29 after three independent same-day incidents on `feat/super-admin-followup-overnight` (broken Java import, missing `@author` Checkstyle violation, Stryker mutation score 40.96% < 60% break threshold) — each caught by the local run the agent claimed to have done. The proof artifact is the structural fix; the assertion of having run the gate is not.

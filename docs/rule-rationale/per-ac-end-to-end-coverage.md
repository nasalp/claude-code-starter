# Rationale — per-ac-end-to-end-coverage.md

## Why

1. **Unit tests prove the code can run; they do not prove the user can
   reach the feature.** A unit test for `EntitlementChecker.hasEntitlement`
   passes whether or not the `EntitlementChecker` bean is wired into the
   activation controller, whether or not the activation route is
   reachable on the deployed app, whether or not the auth wall lets a
   real merchant past. End-to-end tests catch the integration gap that
   unit tests cannot.

2. **AC ↔ click-path map is the operator's contract.** When a merchant
   reports "I can't activate location management," the operator needs
   to look at `spec/features/agentic-location-management.md`, find the
   AC, and ask "does the test exist? does it pass on main?". The test
   IS the proof that the spec's promise is kept. Without it the spec
   becomes wishful prose.

3. **A QA smoke-test exercise showed
   the pattern.** A 4-agent parallel curl-level smoke test of the
   running stack surfaced 5 bugs in 30 minutes — 3 of them (#1, #3,
   #4 in the QA bug report) were API contract issues that all 2200+
   unit tests had silently passed. The bugs only showed because the
   tests hit the running HTTP server. Playwright at the UI layer
   catches the same shape of gap one step earlier (the user does click
   the button) and one step deeper (the SPA route actually renders).

4. **Critical subset must gate PRs because the alternative is "we
   shipped, then the merchant tried, then we found out."** Per-PR blocking
   is the only signal that survives the spec-author-was-careful loop.

5. **Full suite weekly catches drift, not PRs.** Running the full
   200-400 AC suite on every PR would either (a) be slow enough that
   developers route around it, or (b) be flaky enough that "rerun the
   build" becomes the team's main coping strategy. Weekly on a fresh
   Docker stack is the discipline that surfaces drift while keeping
   per-PR feedback fast.

6. **Without local mode, no human can verify a single failure.** A
   weekly suite that fails one AC is useless if the operator can't
   reproduce that one AC against `./dev.sh` in 30 seconds. The
   `--grep 'AC-X'` interactive path is what makes the failure
   debuggable.

## Cross-references

- `core.md` Rule 1 + Rule 2 — SPEC → TEST → IMPLEMENT; this rule
  extends "TEST" to mean "end-to-end, not just unit".
- `.claude/rules/common/proof-of-work.md` — the e2e test IS the
  proof for spec-promised behaviour.
- `.claude/rules/no-deferred-work.md` — "I'll add the e2e test
  later" is the deferred-as-done shape this rule prevents.
- `.claude/rules/no-silent-pass-in-ci.md` — the coverage gate
  cannot be silenced.
- `.claude/rules/senior-review-gates.md` — adds a per-AC e2e
  question to the senior-reviewer checklist.
- `.claude/skills/e2e-testing/SKILL.md` (if present) — Playwright
  pattern reference.
- `.claude/skills/three-layer-test-architecture/SKILL.md` —
  backend ApiIT + frontend Playwright stubs + Java Playwright
  full-stack split; this rule names which layer covers which AC.

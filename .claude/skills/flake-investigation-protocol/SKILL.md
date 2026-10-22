---
name: flake-investigation-protocol
description: Empirical 3x-green-or-OPEN protocol for non-reproducible test failures, forbidding @Disabled and @RetryingTest cover-ups, with a structured investigation document that names hypothesis and reopen c...
origin: ECC
triggers: flaky test, intermittent failure, test passed second time, @Disabled, @RetryingTest, non-reproducible failure, ran green twice, MockMvc 403 vs 400, parallel test runner race, OPEN finding, no-deferred-items
---
# Flake Investigation Protocol

When a test fails once and then "passes on the next run with no code changes", the default agent reflex is to re-run, see green, declare it fine, and move on. That reflex is wrong. This skill defines an empirical, evidence-driven protocol for non-reproducible failures: write the investigation doc, capture three consecutive verify-runs, state the hypothesis, declare the finding **OPEN** until the root cause is understood. `@Disabled` and `@RetryingTest` are forbidden -- they hide the signal the rule exists to surface.

## When to use

- A test failed once during a CI run or local verify, then passed on the immediate next invocation with no source change.
- A reviewer flagged a "wrong-status-code-once" or "wrong-count-once" or "MockMvc 403 vs 400" pattern as a flake.
- The build is otherwise green and a captain wants to ship the wave; the failure is "non-blocking" but unexplained.
- A pre-merge audit asks: "is this a real intermittent bug or a test-runner artefact?"

## When NOT to use

- The test fails reproducibly. That is a normal bug; fix it directly with a regression test.
- The test fails because the code is wrong on every Nth iteration of a property test. That is a property-test failure with a logged seed; reproduce with the seed and fix.
- The test fails only on a specific slow CI runner. That is an infrastructure issue; investigate the runner, do not paper over with the protocol.

## The pattern

Step 0 -- **stop and write**. Do not re-run the build to "see if it happens again". The first run is data; the second is contamination of data. Open `spec/learnings/YYYY-MM-DD-<test-or-area>-flake-investigation.md` and capture the failing run's exact log line, timing, and surrounding state.

Step 1 -- **frontmatter**. Tag with the audit/finding id and status `OPEN`:

```markdown
---
type: investigation
date: 2026-05-05
audit_ids: [MEDIUM-R3-1]
related_tests:
  - com.example.app.diagnostic.adapters.in.DiagnosticRunControllerTest
status: OPEN
---
```

Valid statuses are `OPEN` and `CLOSED`. The only allowed third state is `USER-BLESSED PERMANENT-OPEN` per the project's no-deferred-items rule, and only with the user's verbatim directive plus compensating controls documented in the same file.

Step 2 -- **Summary**. Two paragraphs: (a) what failed, where, and exactly when; (b) why this is more than a "ran fine the second time" handwave. Cite reviewer reports if any. Name the hypothesis category up front (parallel test runner race, MockMvc filter ordering, dirty Spring context, time-of-day boundary, locale-sensitive sort).

Step 3 -- **Empirical resolution**. Run the canonical CI-parity gate three consecutive times back to back, no source edits between runs. Record exit code, wall clock, and the specific test's `Tests run: N, Failures: 0, Errors: 0, Skipped: 0` line for each run.

```markdown
| Run | Start (UTC) | End (UTC) | Duration | <TestClass> | Total |
|-----|-------------|-----------|----------|-------------|-------|
| 1 | 2026-05-05T06:54:03Z | 2026-05-05T06:56:52Z | 169 s | 11/11 (7.256 s) | BUILD SUCCESS |
| 2 | 2026-05-05T06:57:23Z | 2026-05-05T07:00:05Z | 162 s | 11/11 (5.604 s) | BUILD SUCCESS |
| 3 | 2026-05-05T07:00:10Z | 2026-05-05T07:03:15Z | 185 s | 11/11 (5.686 s) | BUILD SUCCESS |
```

Step 4 -- **Hypothesis (unverified)**. State the most plausible explanation explicitly labeled "unverified". Acknowledge what would refute it. Do not promote a hypothesis to "root cause" without a reproducer. Example:

> The most plausible explanation is a warm-cache artefact in JUnit's parallel `ForkJoinPool`-backed runner: when several `@SpringBootTest` slices initialize concurrently, an early MockMvc filter chain may briefly observe a Spring Security configuration before the test's `@TestConfiguration` `@Primary` overrides have been registered. This is **not confirmed by code reading** and **not refuted by reproducer**. The single original observation is the only data point supporting it.

Step 5 -- **Status: OPEN**. Three green runs do not prove the underlying race is gone. Per project rules, audit-finding status is binary CLOSED / OPEN, with USER-BLESSED PERMANENT-OPEN as the only third option. The flake stays OPEN until either (a) a reproducer is found and the root cause is fixed, in which case status flips to CLOSED with the fix linked, or (b) the recurrence condition fires and the investigation is reopened with new data.

Step 6 -- **Reopen condition**. State the precise event that flips the finding back to active investigation:

> If this flake recurs in CI on the merged branch, raise it immediately as an OPEN finding and investigate the parallel test runner / Spring Security filter ordering hypothesis with a reproducer (e.g. `mvn -Dsurefire.parallel=classes -Dsurefire.threadCount=8` repeated runs to provoke the timing window).

Step 7 -- **Forbidden cover-ups**. Do not, under any circumstances:

- Apply `@Disabled` to the test. The test was telling you something; muting it loses the signal.
- Wrap the test in `@RetryingTest(3)`. Retry hides the failure mode by design.
- Add a `try { } catch (Exception e) { }` to the test body.
- Increase Awaitility timeouts past the documented ceiling.
- "Comment out the assertion until we understand it."

Each of these turns an OPEN investigation into a silent regression risk. The rule against them is hard.

## Common gotchas / variants

- **Class-load timing variation is not a flake.** Run 1 taking 7.2s vs runs 2-3 taking ~5.6s is normal Spring context warmup. Do not chase this.
- **MockMvc 403 vs 400 is suspicious.** Spring Security usually returns 401/403 before validation runs. A test that flips between security-rejected and validation-rejected on different runs points to bean-registration ordering, not to "occasional brain fart".
- **Three green runs with one red is not closure.** A 25% failure rate is high; even if the next 100 runs are green, the bayesian prior should not allow CLOSED until you understand why run 1 failed.
- **Do not amend the failing PR's description to remove the flake mention.** That is data destruction. Leave the original observation visible; add the investigation file to the same PR or a follow-up.
- **Document the runner.** Local laptop, CI matrix, GitHub Actions runner SKU -- record it. Race conditions love specific topologies.
- **Do not exempt the flake via project ratchets / allowlists.** ArchUnit allowlists, Surefire excludes, and `failsafe.skip` are escape hatches that lie. The protocol is the right answer; the bypass is not.

## Verification

The protocol was followed correctly when:

1. A `spec/learnings/YYYY-MM-DD-*-flake-investigation.md` file exists with the schema above.
2. The file contains a 3-row table with start/end timestamps and per-test green count.
3. The file is linked from the PR description.
4. The frontmatter status is `OPEN` (or `CLOSED` with a fix link, or `USER-BLESSED PERMANENT-OPEN` with the directive).
5. No `@Disabled`, no `@RetryingTest`, no try-catch suppression in the test class.
6. The reopen condition is concrete enough that an outside reader could trigger it.

If any of those is missing, the protocol was bypassed; the finding is not validly OPEN, it is hidden.

## References

- Companion rule: `.claude/rules/no-deferred-items-claimed-as-done.md` (CLOSED / OPEN / USER-BLESSED vocabulary)
- Companion rule: `.claude/rules/ci-minute-conservation.md` (do not push-and-pray instead of investigating)
- Companion rule: project test rules (no `Thread.sleep`, no shared mutable state, random ports)
- The canonical gate the protocol uses: `scripts/verify-like-ci.sh` (Maven; project-specific)

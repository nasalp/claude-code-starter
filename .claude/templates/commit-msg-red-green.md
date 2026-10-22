# Commit message template — RED→GREEN proof discipline

This is the canonical commit-body shape for any commit that fixes a bug,
adds a behavior, or modifies a test contract.

The goal: a future maintainer reading `git log -p` should be able to
verify what a commit claims **without re-running anything**. The proof
travels with the commit, not in a transient CI log that ages out.

---

## Template

```
<type>(<scope>): <one-line summary, present tense, ≤72 chars> [AC-XYZ-1,2]

<one-paragraph WHY — what user problem, what invariant being preserved.
NOT a restatement of the diff. Maintainers can read the diff; they
cannot read your reasoning.>

## RED → GREEN proof

RED   : <commit sha (or "before this commit")> — <test name that asserts the broken behavior>
        Reproduction:
          $ <exact command>
          <quoted tail showing FAIL>

GREEN : <this commit sha> — <test name that now passes>
        Reproduction:
          $ <exact command>
          <quoted tail showing PASS / BUILD SUCCESS / Tests run: N, passed: N>

## Local verify (this commit, in order)

  typecheck:     PASS | FAIL | BROKEN-PRE-EXISTING
  lint:          PASS | FAIL | BROKEN-PRE-EXISTING
  test:coverage: PASS (lines X% / stmt Y% / branch Z% / fn W%)
  build:         PASS | FAIL
  <project gate>: PASS | FAIL | BROKEN-PRE-EXISTING

Per ~/.claude/rules/common/proof-of-work.md every claim above MUST be
backed by quotable output OR explicitly marked BROKEN-PRE-EXISTING with
its reproduction command.

## ACs covered (if applicable)

- AC-XYZ-1: <one-line>
- AC-XYZ-2: <one-line>

## Files touched

- src/foo/Bar.java         (+15 / -3)   — <what / why>
- src/foo/BarTest.java     (+42 / -0)   — <what / why>

## Not in scope (if anything is intentionally out)

- <bullet> — <reason>; tracked at <link/issue>
```

---

## When to use which sections

| Commit shape | RED→GREEN | Local verify | ACs | Files | Not in scope |
|---|---|---|---|---|---|
| Bug fix | **required** | **required** | optional (if AC) | recommended | optional |
| New feature (phase commit) | recommended | **required** | **required** | recommended | optional |
| Refactor (behavior unchanged) | optional | **required** | optional | recommended | optional |
| Docs / README only | n/a | n/a (note "docs-only") | n/a | optional | optional |
| Corrective commit (assessor REJECT) | **required** | **required** | **required** | **required** | optional |
| Build / CI infra | n/a | **required** | n/a | recommended | recommended |

The "required" cells are HARD — a commit of that shape without them is a
PR-time REJECT candidate.

---

## Anti-patterns specifically banned

- "Fix the bug" with no test name, no reproduction command, no quoted
  failure → next maintainer cannot tell what the bug was OR confirm it
  was fixed.
- "Tests pass" with no Tests-run line → per `proof-of-work.md` a bare
  claim with no evidence is a forgery.
- Multi-paragraph essay with no per-section structure → unscannable;
  future-you won't read it; defeats the purpose.
- `git commit --amend` to "tidy up" the body of a published commit —
  rewrites history of a proof artifact; per `git-workflow.md` Pre-Push
  Verification, create a NEW commit instead.
- Boilerplate "Co-Authored-By" footer added by the harness when commit
  attribution is disabled globally — per `~/.claude/CLAUDE.md`,
  attribution is disabled; don't append it from a template.

---

## Worked example

```
fix(jwks): rate-limit JWKS refresh per distinct unknown kid under
concurrent verification [AC-JWT-12, AC-JWT-13]

DefaultJwtValidator's per-kid refresh check was non-atomic across
concurrent verifications. When M > N distinct unknown kids arrived
inside the rate-limit window, ALL M triggered a refresh fetch, defeating
the cache and saturating the JWKS endpoint.

## RED → GREEN proof

RED   : 0f1234a — DefaultJwtValidatorRs256Tests.concurrentDistinctUnknownKidsAreRefreshRateLimitedWhileJwksCacheIsFresh
        Reproduction:
          $ ./mvnw -pl java/mcp-server test \
              -Dtest=DefaultJwtValidatorRs256Tests#concurrentDistinctUnknownKidsAreRefreshRateLimitedWhileJwksCacheIsFresh
          [INFO] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
          [ERROR] expected refresh count <= 1, was 8

GREEN : <this commit> — same test
        Reproduction:
          $ ./mvnw -pl java/mcp-server test \
              -Dtest=DefaultJwtValidatorRs256Tests#concurrentDistinctUnknownKidsAreRefreshRateLimitedWhileJwksCacheIsFresh
          [INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
          [INFO] BUILD SUCCESS

## Local verify

  typecheck:     PASS (mvn compile)
  spotless:      PASS
  test:          Tests run: 246, passed: 246, skipped: 0 (BUILD SUCCESS)
  spotbugs:      PASS
  jacoco gate:   lines 87.2% / branch 81.4% (above 80% threshold)

## ACs covered
- AC-JWT-12: refresh count ≤ 1 per rate-limit window across N concurrent verifications
- AC-JWT-13: distinct kids in same window do NOT each bypass the limit

## Files touched
- java/mcp-server/src/main/java/com/example/mcp/jwt/DefaultJwtValidator.java (+34 / -8) — atomic refresh-counter using guava RateLimiter per cache window
- java/mcp-server/src/test/java/com/example/mcp/jwt/DefaultJwtValidatorRs256Tests.java (+58 / -0) — failing test now passes; uses CountDownLatch to force concurrent refresh attempts
```

---

## How to wire as a `prepare-commit-msg` hook (optional)

The canonical hook script lives at
`.claude/scripts/prepare-commit-msg-red-green.sh` in the `ai-rules`
harness, with 14 BATS tests at
`tests/bats/prepare-commit-msg-red-green.bats` covering every Git hook
invocation shape (plain commit, `-m`, `-F`, amend, merge, squash,
template) and both authoring states (empty editor file vs user already
wrote a subject/body).

Install per-repo (opt-in):

```bash
cp .claude/scripts/prepare-commit-msg-red-green.sh .git/hooks/prepare-commit-msg
chmod +x .git/hooks/prepare-commit-msg
```

What the script does:

- Pre-populates the editor file with the template section headers as
  Git comments WHEN the file is empty / comment-only AND the commit is
  a fresh interactive commit (`msg_source` is empty — i.e. no `-m`,
  no amend, no merge, no squash, no `--template`).
- Skips silently in every other case so it never interferes with
  `git commit -m "fix: typo"`, amends, merges, squashes, or commits
  where the author has already written a subject line.
- Exits `0` always — a `prepare-commit-msg` hook MUST NOT fail the
  commit; that would block the author's work and is a worse failure
  than no template at all.

What the script deliberately does NOT do:

- It does NOT enforce the template — the author can delete the whole
  comment block for trivial commits per the "When to use which
  sections" table above. The hook scaffolds; `proof-of-work.md` is
  what actually requires the content.
- It does NOT double-append: re-running the hook on a file that
  already has the template comment still produces ONE template
  (the user's subject line is the non-comment trigger that skips it).

The hook is **opt-in per-repo**. The harness does NOT install it
globally because not every commit needs the full shape (see the table
above) and a verbose default hurts trivial commits more than it helps.

Earlier inline-bash drafts of this section had Gemini-flagged logic
bugs (inverted append condition, etc.); externalizing the script and
covering it with BATS made every invocation shape an asserted contract
instead of a comment-block claim.

---

## Cross-references

- `.claude/rules/common/proof-of-work.md` — the universal rule this
  template operationalizes for commits specifically.
- `.claude/rules/no-deferred-work.md` — what NOT to put in "Not in
  scope" (must be genuinely separate work, not deferred completion).
- `.claude/rules/git-workflow.md` — Pre-Push Verification interplay.

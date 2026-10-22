# Testing Requirements

## CRITICAL: Mutation testing must distinguish PR-owned lines from legacy lines

Mutation testing tools (Stryker for JS/TS, PITest for Java, mutmut for Python, go-mutesting for Go) mutate **whole files**, not just lines a PR changed. When a PR ADDS code to an existing file (e.g., adds a method, a wrap-all footer, new branches), Stryker also mutates every untouched legacy line in that file.

Naive iteration loop ("kill every survived mutant") drags team into writing tests for pre-existing legacy code the PR didn't touch — violates `legacy-code.md`'s "don't add tests for untouched code" rule and inflates PR scope beyond what was reviewed.

### Required workflow when a PR fails mutation threshold

For each surviving mutant in the Stryker report:

1. **Look up its origin commit** with `git blame <file> -L <line>,<line>`.
2. **Classify**:
   - **PR-OWNED**: the blame points to a commit that is part of THIS PR (i.e.,
     in the range `git log <PR base>..HEAD`). The author introduced this line
     → they own its test coverage → kill the mutant.
   - **LEGACY**: the blame points to a commit BEFORE the PR base. The line
     pre-existed → skip the mutant per `legacy-code.md`. Document it in the
     PR description as "legacy debt surfaced by Stryker, out of scope".
3. **Iterate only on PR-OWNED survivors.** Stop when:
   - All PR-OWNED survivors are killed (or are demonstrably equivalent), OR
   - Three iterations make no progress on PR-OWNED count.

### Required PR-level scoring

Mutation-tool default score is `killed / total`. Misleading when most of "total" is legacy. Report two scores:

| Score | Numerator | Denominator |
|---|---|---|
| **Project mutation score** (default, threshold-gated by CI) | killed | killed + survived + no-coverage |
| **PR-owned mutation score** (what the author is accountable for) | PR-owned killed | PR-owned killed + PR-owned survived |

CI's break threshold (e.g., Stryker's `break: 80`) gates the project score. PR review should also gate on the PR-owned score being ≥ 80% — otherwise the PR ships under-tested new code while hiding behind legacy test debt.

### Tool integration

For Stryker (`stryker.config.js`):
- Stryker does not natively support "mutate only changed lines". Continue
  mutating whole files, but interpret results through the blame filter.

For PITest (Java):
- Use `<scmMutationCoverage>` plugin with `<analyseLastCommit>true` to
  natively scope mutations to changed lines via git blame.

For mutmut / go-mutesting: same approach as Stryker — blame post-filter.

## CRITICAL: No regex-over-source tests

Tests MUST exercise behavior at runtime. Static-analysis tests that read source files as text (`fs.readFileSync` + regex / grep / AST text walk) and assert "the file contains a string matching pattern X" are NOT acceptable as behavior tests.

### What is banned

- `fs.readFileSync(file)` + `String.includes(...)`, `String.match(/.../)`,
  `RegExp.test(source)` as the assertion mechanism.
- `grep` / `rg` over source files as the assertion (the same pattern,
  one level removed).
- AST walks that only confirm "node of type X with name Y exists" —
  if you never invoke the code, you have not tested behavior.
- "Wrap-shape" / "naming convention" / "import-presence" / "annotation-present"
  tests that prove a literal exists in a file. These are linting,
  not testing. Move them to a lint rule (ESLint, Spotless, ArchUnit).

### What is required

A behavior test for code instrumentation (spans, decorators, wrappers, proxies, AOP) MUST:

1. `require()` / `import` the actual instrumented module at runtime.
2. Invoke an exported method with realistic arguments.
3. Use an in-memory observation harness (e.g., OpenTelemetry's
   `InMemorySpanExporter`, JUnit's `MockTracer`, Spring Boot
   `SimpleMeterRegistry`) to capture the side effect.
4. Assert on the observed effect (span name emitted, attributes
   attached, callback fired) AND on the original behavior (return
   value, thrown exception, side effects on mocks).

For wrap/proxy patterns specifically, the test must prove the wrap preserves: (a) return value, (b) thrown error type+message, (c) `this` binding if applicable, (d) argument forwarding (`fn(a, b, c)` not `fn()`), (e) the expected side effect (span emitted with the right name/status) happened.

### Acceptable uses of static analysis

- **Lint rules** — ESLint, ArchUnit, Spotless, Checkstyle. Guardrails
  enforced by the build, not tests. Different job, different name.
- **Codegen / scaffolding verification** — checking a generator
  produced the expected file is a build correctness check, not a
  behavior test.
- **Spec → test coverage tools** — verifying every AC ID has a test
  annotation (`verify-ac-tests.sh`) is a meta-check, not a test.

If you find yourself reaching for `fs.readFileSync` inside a `.test.{js,ts,py,java}` file: stop, escalate to a lint rule, and write a real behavior test for the underlying contract.

## CRITICAL: Property tests must span gate branches, not just one side

When the production code under test has an internal gate (`if (x == 0) return SKIP; else return compute(x)`), the property test MUST generate `x` across the FULL input space so that BOTH the skip-branch and the compute-branch are exercised. Two separate properties (one per side) miss the cross-branch invariant; a single property fixed on one side of the gate is silently dead code on the other side.

Three accepted shapes:

1. **Generator spans both sides explicitly.** The `@ForAll` range
   includes the gate-tripping value (`0`, `null`, the boundary) AND
   values on the other side. The body asserts invariants that must
   hold on BOTH sides (`score in [0..100]`) plus branch-conditional
   ones inside `if (x == gateValue) ...`.

2. **Boundary value as a separate `@Example`.** When the generator
   can't naturally produce the gate value (e.g. `@ForAll @Positive`
   excludes zero), pair the property with an `@Example` test that
   pins the boundary case explicitly. The two together cover the
   gate.

3. **Property assertion on continuity / idempotence across the
   gate.** When the skip-branch and compute-branch should agree at
   the boundary (e.g. `compute(epsilon) ≈ SKIP_VALUE`), the property
   asserts that continuity directly. This catches gate-misalignment
   bugs neither branch test alone would surface.

The anti-pattern: a "headroom" property test that varies an unrelated parameter while keeping the gate-input fixed (e.g. varies `gImpCurr` while `gImpPrev` is hard-coded non-zero). A formula change that breaks the skip branch passes such a test on every run — reassuring without being protective.

## Minimum Test Coverage: 80%

Test Types (ALL required):
1. **Unit Tests** - Individual functions, utilities, components
2. **Integration Tests** - API endpoints, database operations
3. **E2E Tests** - Critical user flows (framework chosen per language)

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test — it MUST fail (if it passes, the test is wrong or the feature already exists)
3. Write minimal implementation (GREEN)
4. Run test — it MUST pass
5. Refactor (IMPROVE)
6. Verify coverage: run `./mvnw jacoco:report` (Maven) or `./gradlew jacocoTestReport` (Gradle), then check the HTML report in `target/site/jacoco/index.html` or `build/reports/jacoco/test/html/index.html` — line coverage must be 80%+

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Coverage below 80% | Untested branches or error paths | Run coverage report, sort by missed branches, add tests for uncovered paths |
| Test passes before implementation | Test asserts the wrong thing | Verify assertion checks the NEW behavior, not existing/default state |
| Tests fail only in CI | Environment difference (ports, timezones, locale) | Use random ports, explicit `Locale`/`ZoneId`, `@TempDir` for files |
| Flaky test | Shared state or timing dependency | Remove static mutable state; replace `Thread.sleep` with Awaitility |
| Mock returns null unexpectedly | Mock not configured for the called method | Add missing `when(...).thenReturn(...)` stub |

## Agent Support

- **tdd-guide** - Use PROACTIVELY for new features, enforces write-tests-first

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/common__testing.md`

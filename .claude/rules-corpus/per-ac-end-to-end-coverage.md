# Per-AC End-to-End Coverage — Definition of Done

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

For every acceptance criterion (`AC-*`) in feature spec
(`spec/features/<feature>/*.md`), feature is **not done** until:

1. **Every AC has e2e test** exercising running stack —
   Playwright for UI-reachable ACs, REST-assured / API IT for
   backend-only ACs, BATS / shell IT for CLI ACs. Unit tests don't
   count. Test MUST hit real HTTP server, real DB (Testcontainers
   or shared singleton), real downstream stub (WireMock, etc.) — not
   mocks of seams.
2. **"critical" subset (operator-marked) runs every PR** as
   blocking CI gate.
3. **Full suite runs fixed cadence** (weekly default —
   `0 6 * * 1` Monday 06:00 UTC) against deployed-shape stack:
   Docker-composed app + Postgres + Redis + WireMock or equivalent.
4. **Local mode runs same files** against project's
   `./dev.sh` (or equivalent local-stack script). Operator MUST be
   able to invoke single AC test interactively
   (`pnpm test:e2e:devsh --grep 'AC-FREE-3'` or equivalent) to click
   through exact behavior test asserts.

Spec frontmatter `tests:` list MUST include e2e test
classes / Playwright spec files. Per-AC traceability gate
(`scripts/verify-ac-tests.sh` or equivalent) MUST resolve every AC ID
to ≥1 test annotated with that ID.

## What is required

### 1. Test type per AC class

| AC class | Test type |
|---|---|
| **UI-reachable** (merchant clicks a button, sees a state, etc.) | **Playwright** spec under `frontend/tests/ac/<feature>/<US>.ac.spec.ts` (or project equivalent) — drives a real browser against the real app |
| **HTTP API-only** (no UI; called by another service or CLI) | REST-assured / WebTestClient / MockMvc IT under `<module>/src/test/java/.../<feature>/<US>AcceptanceIT.java` |
| **Database invariant** (e.g. ON DELETE CASCADE, unique constraint) | Repository IT under `@SpringBootTest` against Testcontainers Postgres |
| **Background job behaviour** (scheduled, queue drain) | IT that triggers the job and asserts the downstream side effect |
| **CLI behaviour** | BATS IT against the compiled binary |
| **Architecturally local-impossible** (ALB-OIDC sidecar, multi-AZ HA, etc.) | Documented as `unpinned_acceptance_criteria` in the spec frontmatter with a one-line reason; not counted against coverage |

Mixing test types within one spec is normal; an AC can have
multiple tests if behaviour spans layers.

### 2. The `@critical` subset

Per project, operator (or PR author with operator approval) marks
**2–5 ACs per feature spec** as `@critical` — those whose failure
is "ship-blocker." These run every PR.

Marking conventions (use whichever test framework supports
natively):

| Framework | Marking |
|---|---|
| Playwright | `test('@critical AC-FREE-1: …', …)` — picked up by `--grep @critical` |
| JUnit 5 | `@Tag("critical")` plus the existing `@Tag("AC-FREE-1")` — picked up by surefire `<groups>critical</groups>` |
| pytest | `@pytest.mark.critical` plus `@pytest.mark.spec("AC-X")` |
| BATS | `@critical` line in the test's leading comment block — gated by a `grep` filter in CI |

Critical subset is intentionally small; smoke test of the smoke
test. Non-critical body carries bulk of AC coverage, runs weekly.

### 3. Cadences

| Cadence | What runs | Where | Wall-clock budget |
|---|---|---|---|
| **Per PR (blocking)** | `@critical`-tagged tests across all suites | Existing CI job (e.g. `stub-backed playwright` + targeted IT slice) | ≤ 10 min |
| **Weekly (notify, not block)** | Full AC suite | New workflow (`.github/workflows/weekly-ac-coverage.yml`) against a Docker-Composed full stack | ≤ 60 min |
| **Local interactive** | Single AC by `--grep` | `./dev.sh up` + project entry point (`pnpm test:e2e:devsh`, `./mvnw test -Dtest='*AcceptanceIT' -Dac=AC-X`) | ≤ 30 s per AC |
| **Coverage gate** | Every AC ID resolves to ≥ 1 test annotation | `scripts/verify-ac-tests.sh` (per `core.md` Rule 1) | < 5 s |

### 4. Local "click-through" mode

Every project adopting this rule MUST ship single command that:

- Boots local stack (`./dev.sh` or `./mvnw spring-boot:run`, etc.)
- Runs chosen AC's e2e test against that stack
- For UI tests, supports `--headed` / `--debug` so operator
  watches click path live

Example (Playwright + Vite SPA):

```bash
./dev.sh up                                    # one-time stack boot
pnpm test:e2e:devsh --grep 'AC-FREE-3' --headed
# → opens Chromium, drives the snapshot waterfall page,
#   asserts the expected state, halts on first mismatch
```

Single-AC click-through replaces historical "run dev.sh, open
browser, navigate manually, eyeball result" loop with
reproducible artifact.

### 5. Spec frontmatter linkage

Per `core.md` Rule 1, spec frontmatter `tests:` list MUST name
e2e test file (Playwright spec) or class (JUnit IT) for every AC.
Per-AC verifier (`verify-ac-tests.sh` or equivalent) MUST resolve
every AC ID to ≥1 annotated test. Missing entries are
build-time failure; not a TODO.

## What is forbidden

| Pattern | Why |
|---|---|
| Shipping a feature with green unit tests + no e2e for any AC | Unit tests don't prove the seam is wired |
| Marking every AC `@critical` so the per-PR job approximates "the full suite" | Defeats the cadence split; per-PR job balloons past 10 min |
| Marking zero ACs `@critical` so the per-PR job stays fast | The full suite is monthly-effective in practice; zero per-PR coverage hides regressions |
| Skipping the local "click-through" mode "because CI runs it anyway" | A failing CI run that an operator can't reproduce locally is undebuggable |
| Coverage gate (`verify-ac-tests.sh`) marked `continue-on-error: true` to silence missing tests | The whole rule defeats itself; banned per `no-silent-pass-in-ci.md` |
| Using mocks of the seams in the e2e tests (mocked DB, mocked downstream HTTP) | E2e by definition exercises the real seam; mocks belong in unit tests |
| Counting `xfail` / `@Disabled` ACs as covered | Same as missing |
| Marking ACs as `unpinned_acceptance_criteria` in the frontmatter to dodge coverage | `unpinned_*` is for architecturally local-impossible ACs (ALB sidecar, multi-AZ), not "I didn't get to it" |

## What is allowed

- Single test method asserting multiple ACs simultaneously (test
  is registered as covering every AC ID it touches; see
  `core.md` Rule 1 — "multi-AC tests are explicitly allowed").
- Feature spec with zero `@critical` ACs IF operator
  documented rationale (e.g. "feature is dev-only, ships behind
  a flag, full suite alone is sufficient").
- Test files outside standard layout, IF path is registered
  in project's test-runner config so `verify-ac-tests.sh` finds
  it.
- Per-PR job using `@critical` subset PLUS one or two
  representative non-critical ACs ("sanity slice") — useful when
  critical set is very small and operator wants per-PR
  coverage of broader surface.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/per-ac-end-to-end-coverage.md`

---
name: stryker-vitest-mutation-frontend
description: Configure Stryker mutation testing for a Vitest + TypeScript frontend with TS checker, mutate globs, 90/80/60 thresholds, concurrency 2, and 60s timeout — the frontend mirror of PITest STRONGER 80%
origin: ECC
triggers: stryker, mutation testing frontend, stryker.config.mjs, vitest mutation, mutation kill rate, frontend pitest equivalent, mutation score react
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/stryker*.conf*"
---
# Stryker for Vitest + TypeScript Frontend

The frontend mirror of the PITest 80%-mutation-kill rule. Stryker mutates `src/**/*.{ts,tsx}`, runs the existing Vitest suite for each surviving mutant, and fails the build if the kill rate drops below threshold. The TypeScript checker eliminates compile-broken mutants before they're run, cutting wall-clock time roughly in half. Concurrency and timeout are tuned to the typical CI runner — bump them on beefier hardware.

## When to use

- The frontend already has a Vitest suite with ≥80 % line coverage.
- You suspect tests are too forgiving (assert-not-null patterns, no boundary checks) and want a kill-rate signal.
- You want parity between backend (PITest STRONGER, 80 %) and frontend mutation testing — both gates appear in CI as pass/fail with a numeric score.
- Mutation runs are gated to nightly or PR-merge (not every commit) — a typical Stryker run is 5–30 minutes.

## When NOT to use

- Coverage is below 70 %. Mutation testing on under-tested code produces a flood of survived mutants and no signal — fix line coverage first.
- The codebase has heavy E2E tests (Playwright). Stryker should NEVER run E2E — `mutate` already excludes test files; make sure your `vitest.config.ts` test glob is unit/integration only.
- The team treats mutation score as a vanity metric. Without a consequence (CI failure at `break: 60`), Stryker rots.
- The frontend is mostly declarative JSX with little logic. Mutating `<div className="foo">` to `<div className="">` produces low-signal mutants. Apply Stryker to `lib/`, `hooks/`, `services/`, NOT `components/` rendering only.

## The pattern

### `frontend/stryker.config.mjs`

```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: 'vitest',
  vitest: {
    configFile: 'vitest.config.ts',
  },
  checkers: ['typescript'],
  tsconfigFile: 'tsconfig.json',
  mutate: [
    'src/**/*.ts',
    'src/**/*.tsx',
    '!src/test/**',
    '!src/**/*.d.ts',
    '!src/styles/**',
  ],
  reporters: ['html', 'clear-text', 'progress'],
  thresholds: {
    high: 90,
    low: 80,
    break: 60,
  },
  concurrency: 2,
  timeoutMS: 60000,
}
```

### Why each setting

- **`testRunner: 'vitest'` + `vitest.configFile`.** Stryker spawns Vitest in-process per mutant. Pointing at the project's own `vitest.config.ts` ensures aliases (`@/` → `src/`), setup files, and JSDOM are honored. Without this, Vitest boots with defaults and every test fails for unrelated reasons.
- **`checkers: ['typescript']` + `tsconfigFile`.** `@stryker-mutator/typescript-checker` type-checks each mutant before running tests. Mutants that break the type system (e.g. negating `!== null` to `== null` where the next line dereferences) are killed by the checker — no Vitest run needed. This typically removes 30–50 % of mutants from the test phase. Required dev dep: `@stryker-mutator/typescript-checker`.
- **`mutate` globs.** Include both `.ts` and `.tsx` for React components. Exclude:
  - `src/test/**` — test fixtures (Stryker would mutate them and break itself).
  - `src/**/*.d.ts` — type-only declarations have no runtime, no mutants apply.
  - `src/styles/**` — CSS-in-TS / token files, all string literals.
- **`thresholds`.**
  - `high: 90` — green badge.
  - `low: 80` — yellow ("acceptable but improve").
  - `break: 60` — build fails. This is the gate. **Set `break` no higher than your team will tolerate failing CI** — a single PR with a survived-mutant cluster can drop the score 5–10 points.
- **`reporters: ['html', 'clear-text', 'progress']`.** `progress` for live CI logs, `clear-text` for the PR comment summary, `html` for the post-mortem at `reports/mutation/mutation.html` showing per-line survived/killed.
- **`concurrency: 2`.** Vitest spawns its own worker per Stryker worker. On a 4-core CI runner, `concurrency: 2` keeps total threads ≤ 8 (Stryker × Vitest workers). Higher concurrency on shared CI hardware causes Vitest startup timeouts. Local dev: `4` is usually fine; bump to `8` on a 16-core workstation.
- **`timeoutMS: 60000`.** Per-mutant timeout. The default (5–10 s) is too tight for Vitest cold starts inside Stryker workers. 60 s catches infinite-loop mutants without killing legitimately-slow integration-style tests.

### Pairing with PITest

The backend has PITest STRONGER, threshold 80, on `backend`. The frontend Stryker config is the parity gate — same 80% target (`thresholds.low`), with a softer `break: 60` while the suite matures. When the frontend kill rate is reliably ≥80 %, raise `break` to `80` to match PITest exactly.

## Common gotchas / variants

- **Stryker doesn't see your test files.** It runs Vitest's own glob. If `vitest.config.ts` has `include: ['src/**/*.test.ts']`, Stryker uses that. To run Stryker against a SUBSET of tests (faster iteration), use `--mutate "src/lib/foo.ts"` on the CLI, not by editing the test glob — editing the test glob breaks regular `npm run test`.
- **`tsconfig.json` has `"noEmit": true`.** Required for the TS checker. If you have `"isolatedModules": true` and `"noEmit": false`, the checker errors with "tsconfig must be isolatedModules-compatible".
- **JSX-only files have low mutation density.** A 200-line React component with 5 `if` statements gets ~10 mutants. The same logic in a hook (`use*.ts`) gets ~30. Move logic out of components into hooks/utilities — this is good design AND boosts the mutation signal.
- **Mutant "string literal" noise.** Stryker mutates `"" → "Stryker was here!"`. For className/data-test-id strings, this produces survived mutants of zero value. Either refactor strings to constants and exclude `src/constants/**`, or use `disableTypeChecks: false` and live with the noise.
- **CI cache.** Stryker writes a `.stryker-tmp/` sandbox per run. Don't cache it between CI jobs — stale sandboxes silently use old code. Add `.stryker-tmp/` to `.gitignore` and to the CI artifact-cleanup step.
- **Coverage analysis.** Stryker uses Vitest's coverage to skip mutants in untested files (faster). If `vitest.config.ts` doesn't enable v8 coverage, every mutant is run — slow. Enable `coverage: { provider: 'v8' }` even when you only run Stryker, not coverage gates.
- **`concurrency` on a Mac M-series.** Tested at `concurrency: 6` on M2 Pro: Stryker run drops from 18 min to 6 min. Tune to your hardware.
- **Variant: incremental.** `--incremental` writes `reports/stryker-incremental.json`. Subsequent runs only mutate changed files. Massive speedup in local iteration, NOT recommended in CI (a clean baseline catches survivors hidden by stale state).

## Verification

- `npx stryker run` (or `npm run mutation`) reports a kill rate, not a crash.
- The HTML report at `reports/mutation/mutation.html` shows per-file survived/killed in colored highlights.
- A deliberately weak test (`expect(result).toBeTruthy()` instead of `toBe(7)`) survives a `7 → 0` mutant — confirming Stryker would have caught the missing assertion.
- CI fails when score < 60; passes when ≥ 60; emits a yellow status when 60–80; green ≥ 90.

## References

- `frontend/stryker.config.mjs` — the canonical config.
- Stryker docs: https://stryker-mutator.io/docs/stryker-js/configuration/
- Vitest runner plugin: https://stryker-mutator.io/docs/stryker-js/vitest-runner/
- TypeScript checker plugin: https://stryker-mutator.io/docs/stryker-js/typescript-checker/

# Rationale: prefer-existing-library-blocks

## Origin incident

This rule was written because on 2026-05-15 a W8 agent set out to use
`PostgresAdvisoryLockJdbcTemplateLockProvider` from ShedLock, found
ShedLock 7.7.0 doesn't ship that exact class, and **decided to
implement a custom advisory-lock provider** — while a sibling service already
had a working `ShedLockConfig` wiring the standard
`JdbcTemplateLockProvider` + a `shedlock` Flyway table migration that
had been in production for months.

## Calibration

"Did I check whether this already exists?" is a question to answer
explicitly before every custom class. The answer should be a list
of greps and inventory commands run, not a vague "I think it doesn't
exist."

## Cross-service business-math duplication

Library-block rule usually framed around in-process libraries. Same discipline one level out: business math ALREADY exists in sibling service or external dependency you can't easily call → re-implement = uncontrolled drift surface.

Three common shapes:

1. **Cross-language port.** Python/JS scorer ported to Java because original wrong runtime. Two implementations look identical until they don't.
2. **Cross-service compute migration.** Compute moving service A → B (latency/decoupling). Both linger because "removing A's is out of scope".
3. **External-dependency mirror.** Third party computes X; re-implement internally to dodge latency/cost/reliability. Same divergence risk, harder to detect because third-party formula not in source control.

Each shape needs same defence: **parity test asserting both implementations agree across controlled input matrix, gated in CI**. Written BEFORE second implementation lands.

Originating calibration: 4 implementations of same Customer Health scoring math across 4 services with no parity test.

## Cost of custom block when existing one fits

1. **Code surface nobody else maintains.** Library code gets security updates, bug fixes, performance work, CVE patches. Hand-rolled copies do not.
2. **Subtle behavioural drift.** Custom implementation diverges from what users expect from name like `PostgresAdvisoryLockProvider` — column types, lock release semantics on connection drop, error handling.
3. **Test debt.** Every custom block needs own contention, timeout, recovery tests. Library code has these upstream.
4. **Migration risk.** When library later ships the class, migrating off custom one = refactor with backward-compat concerns nobody wants to own.

## Cross-references

- `search-first` skill — broader research-before-coding workflow.
- `simplify` skill — code review pass for reuse, quality, efficiency.
- `common/coding-standards.md` — broader DRY/KISS; this rule tightens "library doesn't ship exact name → write custom one."

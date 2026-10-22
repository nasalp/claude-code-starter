# Rationale: no-silent-pass-in-ci

## Why

- Silent passes mask real problems. Last reviewer assumed CI was green because CI said green. It said green because someone added `continue-on-error: true` to the step that found the bug.
- The hardening sequence is: introduce check → identify backlog of real failures → close the backlog → flip to hard gate. Skipping straight from "introduce" to "hard gate with continue-on-error" leaves the backlog open with no forcing function to close it.
- Specific banned shapes that have shown up in this fleet:
  - GitHub Actions: `continue-on-error: true` on a real check.
  - Shell: `./check.sh || true`, `./check.sh || exit 0`.
  - Spring Flyway: `FLYWAY_REPAIR_ON_MIGRATE=true` + `FLYWAY_IGNORE_MIGRATION_PATTERNS=*:missing` as production defaults — silently auto-repair the very mismatch that should fail the deploy.
  - Test runners: `mvn ... | grep -q FAIL && exit 0` patterns that munge surefire output.
  - npm: `"test": "vitest run || true"` style scripts.
  - Wrapping `set -e` scripts in `set +e` blocks specifically to swallow failure.

## Cross-reference

- `.claude/rules/no-deferred-work.md` — silently passing a failing check is the deferred-as-done anti-pattern in CI form.

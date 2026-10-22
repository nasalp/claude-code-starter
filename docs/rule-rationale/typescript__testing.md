# Rationale — typescript/testing.md

## CRITICAL: `.toBeInTheDocument()` over `.toBeDefined()` on throwing queries — Why

`getBy*` queries throw on miss → `.toBeDefined()` is unreachable if the
element is absent (the test errors before the assertion runs). The
assertion is dead code. If someone later refactors to `queryBy*` (which
returns `null` on miss), `.toBeDefined()` silently passes on `null` and a
real regression slips through. `.toBeInTheDocument()` fails loudly in both
cases.

**Calibration 2026-05-31**: An assessor audit of the 227 PR found
~17 `getBy*(...).toBeDefined()` sites across `SalesContent.test.tsx`
and `LocationDetailPage.test.tsx`. None caught real bugs because
they were already structurally tautological. Flagged as a
silent-tautology pattern.

## ESLint enforcement — Why

The `jest-dom/prefer-to-be-in-the-document` rule from
[`eslint-plugin-jest-dom`](https://github.com/testing-library/eslint-plugin-jest-dom)
is the canonical enforcement — it flags `.toBeDefined()` /
`.toBeTruthy()` on DOM elements and prefers `.toBeInTheDocument()`.
Use it instead of a fragile grep-CI gate over source text.

Same rule applies to `findBy*` (async-throwing) and `userEvent`-driven
follow-ups: prefer explicit-intent matchers (`.toBeInTheDocument()`,
`.toHaveTextContent()`, `.toHaveAttribute()`, `.toBeChecked()`) over
generic JavaScript truthiness matchers.

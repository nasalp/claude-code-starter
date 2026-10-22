# Rationale — typescript/type-safety.md

## CRITICAL: `strict: true` — What It Enables

**`strict: true` is non-negotiable.** It enables:
- `strictNullChecks` — no implicit null/undefined
- `noImplicitAny` — no untyped values
- `strictFunctionTypes` — correct function variance
- `strictBindCallApply` — correct this binding

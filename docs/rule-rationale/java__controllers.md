# Rationale — java/controllers.md

## Rationale

- Method injection is explicit, testable, and framework-managed
- Static calls create hidden dependencies and make testing harder
- Controllers should not reach into global state — if security info is needed, let the framework inject it

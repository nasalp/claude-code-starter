# Rationale — java/observability.md

## Why It's Mandatory

- Ensures trace/span IDs propagate across thread boundaries
- Auto-instruments `@Async`, `CompletableFuture`, `Executor`
- Without it, you lose trace context in async code

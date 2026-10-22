# Rationale — testing.md

## Why AssertJ

Better error messages, fluent API, IDE completion.

## Calibration: Singleton Container for Parallel ITs

When integration tests run in parallel (and they MUST — see [performance.md](performance.md)), the standard `@Testcontainers` + `@Container` lifecycle fights you. JUnit creates the container **per test class instance**, and parallel class execution interleaves container starts/stops with schema migrations. Real-world failure mode: **22 of 22 ITs fail intermittently** with cryptic "connection refused" or "relation does not exist" errors because Flyway runs against a container that JUnit shuts down mid-test.

## Calibration: Per-Test Data Isolation

Once the container is shared across all tests, `@BeforeEach { repository.deleteAll(); }` becomes a parallel-test foot-gun: test A truncates the table while test B is mid-insert.

## Custom Assertions — When to Create / Skip

**When to create:**
- Domain object has 3+ fields to validate
- Same assertions repeated across multiple tests
- Validation logic is non-trivial

**When to skip:**
- Simple DTOs
- Objects with 1-2 fields
- One-off tests

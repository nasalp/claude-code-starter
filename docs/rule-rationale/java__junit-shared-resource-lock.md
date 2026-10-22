# Rationale — `@ResourceLock` for shared singletons under parallel class execution

## Why

Concurrent class execution + a shared singleton DB (or broker, or
filesystem fixture) produces races that look like a fresh bug every
CI run:

- Class A inserts a row keyed by `accounts.primary_email = "x@y"` while
  Class B's `@BeforeEach` truncates the table — A's next assertion
  hits "0 rows" or "duplicate key".
- Class A commits on connection X; Class B's `findAll` on connection
  Y briefly misses the row because Postgres MVCC visibility lags
  between commits and other transactions' snapshots.
- `ON DELETE CASCADE` from a parent table wipes a sibling class's
  child rows mid-test.

Per-test Awaitility wraps, per-test UUIDs, and removing `@BeforeEach
deleteAll()` all help — but they treat symptoms. The root cause is
**concurrent class execution against a singleton resource that has no
session boundary between classes**. `@ResourceLock` addresses the root.

## Cross-references

- `~/.claude/rules/common/testing.md` — "Singleton Container for
  Parallel ITs" + "Per-Test Data Isolation, Not `deleteAll`". This
  rule is the partner: how to keep classes parallel **and** safe
  against the shared container.
- `~/.claude/rules/no-deferred-work.md` — partner. "Just flip
  `same_thread` and move on" is the deferred-as-done shortcut this
  rule blocks.
- JUnit 5 user guide — [Synchronization](https://junit.org/junit5/docs/current/user-guide/#writing-tests-parallel-execution-synchronization).
